-- Civil timestamps always represent Europe/Istanbul, independent of session/browser TZ.
create extension if not exists btree_gist with schema extensions;
create table public.team_plans (
  team_id uuid primary key references public.teams(id) on delete cascade,
  version bigint not null default 0 check(version >= 0),
  published_version bigint,
  published_at timestamptz,
  time_zone text not null default 'Europe/Istanbul' check(time_zone = 'Europe/Istanbul')
);
create table public.team_shift_drafts (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null,
  starts_at timestamp without time zone not null,
  ends_at timestamp without time zone not null,
  break_minutes integer not null,
  label text not null check(length(btrim(label)) between 1 and 100),
  note text not null default '' check(length(note) <= 2000),
  foreign key(team_id,user_id) references public.team_members(team_id,user_id),
  check(isfinite(starts_at) and isfinite(ends_at) and ends_at > starts_at),
  check(date_trunc('minute',starts_at)=starts_at and date_trunc('minute',ends_at)=ends_at),
  check(break_minutes >= 0 and break_minutes * interval '1 minute' <= ends_at-starts_at),
  exclude using gist (team_id extensions.gist_uuid_ops with =, user_id extensions.gist_uuid_ops with =,
    tsrange(starts_at,ends_at,'[)') with &&)
);
-- Independent values, no reference to a mutable draft or template.
create table public.team_shift_published (
  id uuid not null,
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  starts_at timestamp without time zone not null,
  ends_at timestamp without time zone not null,
  break_minutes integer not null,
  label text not null,
  note text not null,
  primary key(team_id,id)
);
create index team_shift_published_user on public.team_shift_published(team_id,user_id,starts_at);
alter table public.team_plans enable row level security;
alter table public.team_shift_drafts enable row level security;
alter table public.team_shift_published enable row level security;
-- RPC-only access: even authenticated clients cannot bypass validation or impersonate a user.
revoke all on public.team_plans, public.team_shift_drafts, public.team_shift_published from public,anon,authenticated;

create function private.lock_team_plan(target uuid, expected bigint) returns bigint
language plpgsql security definer set search_path='' as $$
declare current_version bigint;
begin
  if not private.can_manage_team(target) then raise exception 'Not authorized' using errcode='42501'; end if;
  insert into public.team_plans(team_id) values(target) on conflict do nothing;
  select version into current_version from public.team_plans where team_id=target for update;
  if expected is null or expected <> current_version then
    raise exception 'Plan changed; refresh before retrying' using errcode='40001';
  end if;
  return current_version;
end $$;
revoke all on function private.lock_team_plan(uuid,bigint) from public,anon,authenticated;

create function public.read_team_plan(target_team uuid, draft boolean default false) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.is_team_member(target_team) or draft is null or
    (draft and not private.can_manage_team(target_team)) then
    raise exception 'Not authorized' using errcode='42501';
  end if;
  -- One SQL snapshot covers metadata and rows, including during concurrent publication.
  select jsonb_build_object('version',coalesce(p.version,0),
    'published_version',p.published_version,'published_at',p.published_at,
    'time_zone','Europe/Istanbul','shifts',coalesce((
      select jsonb_agg(to_jsonb(s) order by s.starts_at,s.id) from (
        select d.* from public.team_shift_drafts d where draft and d.team_id=target_team
        union all
        select x.* from public.team_shift_published x where not draft and x.team_id=target_team
          and (x.user_id=auth.uid() or private.can_manage_team(target_team))
      ) s
    ),'[]'::jsonb)) into result
    from (select target_team as id) t left join public.team_plans p on p.team_id=t.id;
  return result;
end $$;

create function public.save_team_shift(target_team uuid, expected_version bigint,
  target_shift uuid, assigned_user uuid, shift_start timestamp without time zone,
  shift_end timestamp without time zone, unpaid_break integer, shift_label text, shift_note text default '')
returns bigint language plpgsql security definer set search_path='' as $$
declare v bigint;
begin
  v := private.lock_team_plan(target_team,expected_version);
  if not exists(select 1 from public.team_members where team_id=target_team and user_id=assigned_user) then
    raise exception 'Assignee must be a team member' using errcode='22023';
  end if;
  if shift_start is null or shift_end is null or not isfinite(shift_start) or not isfinite(shift_end)
    or shift_end <= shift_start or date_trunc('minute',shift_start) <> shift_start
    or date_trunc('minute',shift_end) <> shift_end or unpaid_break is null or unpaid_break < 0
    or unpaid_break * interval '1 minute' > shift_end-shift_start
    or shift_label is null or length(btrim(shift_label)) not between 1 and 100
    or shift_note is null or length(shift_note)>2000 then
    raise exception 'Invalid shift interval, break or name' using errcode='22023';
  end if;
  if target_shift is null then
    insert into public.team_shift_drafts(team_id,user_id,starts_at,ends_at,break_minutes,label,note)
      values(target_team,assigned_user,shift_start,shift_end,unpaid_break,btrim(shift_label),shift_note);
  else
    update public.team_shift_drafts set user_id=assigned_user,starts_at=shift_start,ends_at=shift_end,
      break_minutes=unpaid_break,label=btrim(shift_label),note=shift_note where team_id=target_team and id=target_shift;
    if not found then raise exception 'Shift changed; refresh' using errcode='40001'; end if;
  end if;
  update public.team_plans set version=v+1 where team_id=target_team;
  return v+1;
end $$;
create function public.delete_team_shift(target_team uuid, expected_version bigint, target_shift uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare v bigint;
begin
  v := private.lock_team_plan(target_team,expected_version);
  delete from public.team_shift_drafts where team_id=target_team and id=target_shift;
  if not found then raise exception 'Shift changed; refresh' using errcode='40001'; end if;
  update public.team_plans set version=v+1 where team_id=target_team;
  return v+1;
end $$;
create function public.publish_team_plan(target_team uuid, expected_version bigint)
returns bigint language plpgsql security definer set search_path='' as $$
declare v bigint;
begin
  v := private.lock_team_plan(target_team,expected_version);
  delete from public.team_shift_published where team_id=target_team;
  insert into public.team_shift_published select * from public.team_shift_drafts where team_id=target_team;
  update public.team_plans set version=v+1,published_version=v+1,published_at=clock_timestamp() where team_id=target_team;
  return v+1;
end $$;
revoke all on function public.read_team_plan(uuid,boolean),
 public.save_team_shift(uuid,bigint,uuid,uuid,timestamp without time zone,timestamp without time zone,integer,text,text),
 public.delete_team_shift(uuid,bigint,uuid),public.publish_team_plan(uuid,bigint) from public,anon,authenticated;
grant execute on function public.read_team_plan(uuid,boolean),
 public.save_team_shift(uuid,bigint,uuid,uuid,timestamp without time zone,timestamp without time zone,integer,text,text),
 public.delete_team_shift(uuid,bigint,uuid),public.publish_team_plan(uuid,bigint) to authenticated;
