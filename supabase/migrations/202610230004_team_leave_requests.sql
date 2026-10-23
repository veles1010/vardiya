-- Full-day leave uses inclusive Europe/Istanbul civil dates, like the civil shift timestamps.
create table public.team_leave_requests (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id),
  user_id uuid not null references public.profiles(id),
  starts_on date not null,
  ends_on date not null,
  description text not null default '' check(length(description)<=500),
  status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
  revision bigint not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  decided_by uuid references public.profiles(id),
  decided_at timestamptz,
  decision_reason text not null default '' check(length(decision_reason)<=500),
  check(isfinite(starts_on) and isfinite(ends_on) and ends_on>=starts_on and starts_on>=date '0001-01-01' and ends_on<date '9999-12-31'),
  exclude using gist(team_id extensions.gist_uuid_ops with =,user_id extensions.gist_uuid_ops with =,
    daterange(starts_on,ends_on,'[]') with &&) where(status in ('pending','approved'))
);
create table public.team_leave_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.team_leave_requests(id),
  actor_id uuid not null references public.profiles(id),
  status text not null check(status in ('pending','approved','rejected','cancelled')),
  reason text not null default '',
  occurred_at timestamptz not null default clock_timestamp()
);
alter table public.team_leave_requests enable row level security;
alter table public.team_leave_events enable row level security;
revoke all on public.team_leave_requests,public.team_leave_events from public,anon,authenticated;

create function private.lock_leave_plan(target uuid, expected bigint) returns bigint
language plpgsql security definer set search_path='' as $$
declare v bigint;
begin
  if not private.is_team_member(target) then raise exception 'Not authorized' using errcode='42501'; end if;
  insert into public.team_plans(team_id) values(target) on conflict do nothing;
  select version into v from public.team_plans where team_id=target for update;
  if expected is null or expected<>v then raise exception 'Plan changed; refresh before retrying' using errcode='40001'; end if;
  return v;
end $$;

create function private.leave_shift_conflicts(target uuid, person uuid, first_day date, last_day date) returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(to_jsonb(s) order by s.starts_at,s.source),'[]'::jsonb) from (
    select id,starts_at,ends_at,label,'draft'::text as source from public.team_shift_drafts
      where team_id=target and user_id=person and starts_at<(last_day+1)::timestamp and ends_at>first_day::timestamp
    union all
    select id,starts_at,ends_at,label,'published'::text from public.team_shift_published
      where team_id=target and user_id=person and starts_at<(last_day+1)::timestamp and ends_at>first_day::timestamp
  ) s;
$$;

create function public.read_team_leaves(target_team uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.is_team_member(target_team) then raise exception 'Not authorized' using errcode='42501'; end if;
  select jsonb_build_object('version',coalesce(p.version,0),'requests',coalesce((
    select jsonb_agg(to_jsonb(r) || jsonb_build_object(
      'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.occurred_at,e.id) from public.team_leave_events e where e.request_id=r.id),'[]'::jsonb),
      'conflicts',case when private.can_manage_team(target_team) and r.status='pending'
        then private.leave_shift_conflicts(r.team_id,r.user_id,r.starts_on,r.ends_on) else '[]'::jsonb end
    ) order by r.created_at desc,r.id) from public.team_leave_requests r where r.team_id=target_team
      and (r.user_id=auth.uid() or private.can_manage_team(target_team))
  ),'[]'::jsonb)) into result from (select target_team as id) t left join public.team_plans p on p.team_id=t.id;
  return result;
end $$;

create function public.create_team_leave(target_team uuid, expected_version bigint, first_day date, last_day date, explanation text default '') returns uuid
language plpgsql security definer set search_path='' as $$
declare v bigint; result uuid;
begin
  if not exists(select 1 from public.team_members where team_id=target_team and user_id=auth.uid() and role='employee') then
    raise exception 'Only employee can request own leave' using errcode='42501';
  end if;
  v:=private.lock_leave_plan(target_team,expected_version);
  if first_day is null or last_day is null or not isfinite(first_day) or not isfinite(last_day) or last_day<first_day
    or first_day<date '0001-01-01' or last_day>=date '9999-12-31' or explanation is null or length(explanation)>500 then
    raise exception 'Invalid leave dates or description' using errcode='22023';
  end if;
  if exists(select 1 from public.team_leave_requests where team_id=target_team and user_id=auth.uid()
    and status in ('pending','approved') and daterange(starts_on,ends_on,'[]') && daterange(first_day,last_day,'[]')) then
    raise exception 'Overlapping active leave' using errcode='P1003';
  end if;
  insert into public.team_leave_requests(team_id,user_id,starts_on,ends_on,description)
    values(target_team,auth.uid(),first_day,last_day,btrim(explanation)) returning id into result;
  insert into public.team_leave_events(request_id,actor_id,status) values(result,auth.uid(),'pending');
  update public.team_plans set version=v+1 where team_id=target_team;
  return result;
end $$;

create function public.act_on_team_leave(target_team uuid, expected_version bigint, target_request uuid,
  expected_revision bigint, action text, reason text default '') returns void
language plpgsql security definer set search_path='' as $$
declare v bigint; r public.team_leave_requests; next_status text;
begin
  -- Always team first, request second: same lock order as shift mutations/publication.
  v:=private.lock_leave_plan(target_team,expected_version);
  select * into r from public.team_leave_requests where team_id=target_team and id=target_request for update;
  if not found or (not private.can_manage_team(target_team) and r.user_id<>auth.uid()) then
    raise exception 'Not authorized' using errcode='42501';
  end if;
  if expected_revision is null or r.revision<>expected_revision then raise exception 'Request changed; refresh' using errcode='40001'; end if;
  if reason is null or length(reason)>500 then raise exception 'Invalid reason' using errcode='22023'; end if;
  if action='withdraw' then
    if r.user_id<>auth.uid() then raise exception 'Not authorized' using errcode='42501'; end if;
    if r.status<>'pending' then raise exception 'Request changed; refresh' using errcode='40001'; end if;
    next_status:='cancelled';
  elsif action in ('approve','reject','cancel') then
    if not private.can_manage_team(target_team) or r.user_id=auth.uid() then raise exception 'Not authorized' using errcode='42501'; end if;
    if (action in ('approve','reject') and r.status<>'pending') or (action='cancel' and r.status<>'approved') then
      raise exception 'Request changed; refresh' using errcode='40001';
    end if;
    if action in ('reject','cancel') and length(btrim(reason))=0 then raise exception 'Reason required' using errcode='22023'; end if;
    if action='approve' and jsonb_array_length(private.leave_shift_conflicts(target_team,r.user_id,r.starts_on,r.ends_on))>0 then
      raise exception 'Leave conflicts with draft or published shifts' using errcode='P1002';
    end if;
    next_status:=case action when 'approve' then 'approved' when 'reject' then 'rejected' else 'cancelled' end;
  else raise exception 'Invalid action' using errcode='22023'; end if;
  update public.team_leave_requests set status=next_status,revision=revision+1,decided_by=auth.uid(),
    decided_at=clock_timestamp(),decision_reason=btrim(reason) where id=r.id;
  insert into public.team_leave_events(request_id,actor_id,status,reason) values(r.id,auth.uid(),next_status,btrim(reason));
  update public.team_plans set version=v+1 where team_id=target_team;
end $$;

create function private.guard_approved_leave() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  -- Existing save/publish RPCs already hold this lock. Also protects internal writes.
  insert into public.team_plans(team_id) values(new.team_id) on conflict do nothing;
  perform 1 from public.team_plans where team_id=new.team_id for update;
  if exists(select 1 from public.team_leave_requests where team_id=new.team_id and user_id=new.user_id and status='approved'
    and new.starts_at<(ends_on+1)::timestamp and new.ends_at>starts_on::timestamp) then
    raise exception 'Shift overlaps approved leave' using errcode='P1001';
  end if;
  return new;
end $$;
create trigger draft_approved_leave_guard before insert or update on public.team_shift_drafts
  for each row execute function private.guard_approved_leave();
create trigger published_approved_leave_guard before insert or update on public.team_shift_published
  for each row execute function private.guard_approved_leave();
revoke all on function private.lock_leave_plan(uuid,bigint),private.leave_shift_conflicts(uuid,uuid,date,date),private.guard_approved_leave() from public,anon,authenticated;
revoke all on function public.read_team_leaves(uuid),public.create_team_leave(uuid,bigint,date,date,text),
  public.act_on_team_leave(uuid,bigint,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.read_team_leaves(uuid),public.create_team_leave(uuid,bigint,date,date,text),
  public.act_on_team_leave(uuid,bigint,uuid,bigint,text,text) to authenticated;

-- Approved leave is current state, never a pending request or a published shift. No descriptions exposed.
create or replace function public.read_team_plan(target_team uuid, draft boolean default false) returns jsonb
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
    'time_zone','Europe/Istanbul',
    'leaves',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'user_id',l.user_id,'starts_on',l.starts_on,'ends_on',l.ends_on) order by l.starts_on,l.id)
      from public.team_leave_requests l where l.team_id=target_team and l.status='approved'
        and (l.user_id=auth.uid() or private.can_manage_team(target_team))),'[]'::jsonb),'shifts',coalesce((
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
