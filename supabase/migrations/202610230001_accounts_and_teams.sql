-- All tenant mutations are explicit, authenticated, transactional RPCs.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 100),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);
create table public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner','manager','employee')),
  primary key (team_id,user_id)
);
create index team_members_user_idx on public.team_members(user_id,team_id);
create unique index team_single_owner_idx on public.team_members(team_id) where role = 'owner';

create function private.create_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id) values(new.id);
  return new;
end $$;
revoke all on function private.create_profile() from public;
create trigger create_user_profile after insert on auth.users
for each row execute function private.create_profile();
-- Support accounts that predate the migration.
insert into public.profiles(id) select id from auth.users on conflict do nothing;

create function private.is_team_member(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.team_members m
    where m.team_id = target and m.user_id = (select auth.uid()));
$$;
revoke all on function private.is_team_member(uuid) from public;
grant execute on function private.is_team_member(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
revoke all on public.profiles,public.teams,public.team_members from public,anon,authenticated;
grant select on public.profiles,public.teams,public.team_members to authenticated;
create policy own_profile on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy member_teams on public.teams for select to authenticated using (private.is_team_member(id));
create policy member_memberships on public.team_members for select to authenticated using (private.is_team_member(team_id));

create function public.create_team(team_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid(); result uuid;
begin
  if caller is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if team_name is null or length(btrim(team_name)) not between 1 and 100 then
    raise exception 'Invalid team name' using errcode = '22023';
  end if;
  insert into public.teams(name,created_by) values(btrim(team_name),caller) returning id into result;
  insert into public.team_members(team_id,user_id,role) values(result,caller,'owner');
  return result;
end $$;
create function public.rename_team(target_team uuid, team_name text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.team_members
    where team_id = target_team and user_id = auth.uid() and role in ('owner','manager')) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if team_name is null or length(btrim(team_name)) not between 1 and 100 then
    raise exception 'Invalid team name' using errcode = '22023';
  end if;
  update public.teams set name = btrim(team_name) where id = target_team;
end $$;
revoke all on function public.create_team(text),public.rename_team(uuid,text) from public,anon;
grant execute on function public.create_team(text),public.rename_team(uuid,text) to authenticated;
