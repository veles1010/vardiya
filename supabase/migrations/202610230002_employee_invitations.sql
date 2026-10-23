create extension if not exists pgcrypto with schema extensions;

create table public.team_invitations (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  target_email text not null check (target_email = lower(btrim(target_email)) and length(target_email) between 3 and 254),
  code_hash bytea not null unique check (octet_length(code_hash) = 32),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default (clock_timestamp() + interval '7 days'),
  cancelled_at timestamptz,
  accepted_at timestamptz,
  accepted_by uuid references public.profiles(id),
  check ((accepted_at is null) = (accepted_by is null)),
  check (accepted_at is null or cancelled_at is null)
);
create index team_invitations_team_idx on public.team_invitations(team_id);
alter table public.team_invitations enable row level security;
-- Neither hashes nor raw invitation rows are exposed. Only scoped RPC results.
revoke all on public.team_invitations from public,anon,authenticated;

create function private.can_manage_team(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.team_members
    where team_id = target and user_id = auth.uid() and role in ('owner','manager'));
$$;
create function private.verified_invitee_email() returns text
language plpgsql security definer set search_path = '' as $$
declare address text;
begin
  select lower(btrim(email)) into address from auth.users
    where id = auth.uid() and email_confirmed_at is not null and deleted_at is null;
  if address is null then raise exception 'Invitation unavailable' using errcode = '42501'; end if;
  return address;
end $$;
revoke all on function private.can_manage_team(uuid), private.verified_invitee_email() from public,anon,authenticated;

create function public.create_team_invitation(target_team uuid, invite_email text)
returns table(invitation_id uuid, code text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare raw_code text; address text; result public.team_invitations;
begin
  if not private.can_manage_team(target_team) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  address := lower(btrim(invite_email));
  if address is null or length(address) > 254 or address !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid email' using errcode = '22023';
  end if;
  raw_code := encode(extensions.gen_random_bytes(32),'hex');
  insert into public.team_invitations(team_id,target_email,code_hash,created_by)
    values(target_team,address,extensions.digest(raw_code,'sha256'),auth.uid()) returning * into result;
  return query select result.id,raw_code,result.expires_at;
end $$;

create function public.list_team_invitations(target_team uuid)
returns table(id uuid, target_email text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  if not private.can_manage_team(target_team) then raise exception 'Not authorized' using errcode = '42501'; end if;
  return query select i.id,i.target_email,i.expires_at from public.team_invitations i
    where i.team_id = target_team and i.cancelled_at is null and i.accepted_at is null
      and i.expires_at > clock_timestamp() order by i.created_at;
end $$;

create function public.cancel_team_invitation(target_invitation uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare invitation public.team_invitations;
begin
  select * into invitation from public.team_invitations where id = target_invitation for update;
  if not found or not private.can_manage_team(invitation.team_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if invitation.accepted_at is not null then raise exception 'Invitation unavailable' using errcode = '42501'; end if;
  update public.team_invitations set cancelled_at = coalesce(cancelled_at,clock_timestamp()) where id = invitation.id;
end $$;

create function public.preview_team_invitation(invite_code text)
returns table(team_id uuid, team_name text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare address text;
begin
  address := private.verified_invitee_email();
  return query select i.team_id,t.name,i.expires_at from public.team_invitations i
    join public.teams t on t.id=i.team_id
    where i.code_hash = extensions.digest(btrim(invite_code),'sha256') and i.target_email=address
      and i.accepted_at is null and i.cancelled_at is null and i.expires_at > clock_timestamp();
  if not found then raise exception 'Invitation unavailable' using errcode = '42501'; end if;
end $$;

create function public.accept_team_invitation(invite_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare address text; invitation public.team_invitations;
begin
  address := private.verified_invitee_email();
  select * into invitation from public.team_invitations
    where code_hash = extensions.digest(btrim(invite_code),'sha256') for update;
  if not found or invitation.target_email <> address or invitation.accepted_at is not null
    or invitation.cancelled_at is not null or invitation.expires_at <= clock_timestamp() then
    raise exception 'Invitation unavailable' using errcode = '42501';
  end if;
  insert into public.team_members(team_id,user_id,role) values(invitation.team_id,auth.uid(),'employee')
    on conflict (team_id,user_id) do nothing;
  update public.team_invitations set accepted_at = clock_timestamp(), accepted_by = auth.uid() where id=invitation.id;
  return invitation.team_id;
end $$;

create function public.list_team_members(target_team uuid)
returns table(user_id uuid, email text, role text)
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_team_member(target_team) then raise exception 'Not authorized' using errcode = '42501'; end if;
  return query select m.user_id,u.email::text,m.role from public.team_members m
    join auth.users u on u.id=m.user_id where m.team_id=target_team order by m.role,u.email;
end $$;

revoke all on function public.create_team_invitation(uuid,text),public.list_team_invitations(uuid),
 public.cancel_team_invitation(uuid),public.preview_team_invitation(text),
 public.accept_team_invitation(text),public.list_team_members(uuid) from public,anon;
grant execute on function public.create_team_invitation(uuid,text),public.list_team_invitations(uuid),
 public.cancel_team_invitation(uuid),public.preview_team_invitation(text),
 public.accept_team_invitation(text),public.list_team_members(uuid) to authenticated;
