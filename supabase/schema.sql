-- DevLearn: personal learning plus organization workspaces for any company,
-- business domain, and department. Safe to re-run on an existing project.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 120),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 100),
  created_at timestamptz not null default now(),
  unique (organization_id, name),
  unique (organization_id, id)
);

create table if not exists public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  department_id uuid,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  primary key (organization_id, user_id),
  foreign key (organization_id, department_id) references public.departments(organization_id, id) on delete set null (department_id)
);
create index if not exists organization_members_by_user on public.organization_members(user_id, joined_at desc);

create table if not exists public.organization_invites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  department_id uuid,
  invite_code text not null unique,
  email_domain text,
  invited_email text,
  expires_at timestamptz not null default (now() + interval '14 days'),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  foreign key (organization_id, department_id) references public.departments(organization_id, id) on delete cascade
);
alter table public.organization_invites add column if not exists invited_email text;

create table if not exists public.organization_join_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  requested_email text not null default '',
  department_id uuid,
  invite_id uuid references public.organization_invites(id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references auth.users(id) on delete set null,
  unique (organization_id, user_id),
  foreign key (organization_id, department_id) references public.departments(organization_id, id) on delete set null (department_id)
);
create index if not exists organization_join_requests_pending on public.organization_join_requests(organization_id, requested_at) where status = 'pending';

create table if not exists public.learning_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete cascade,
  department_id uuid,
  visibility text not null default 'private' check (visibility in ('private', 'workspace')),
  title text not null check (char_length(title) between 1 and 180),
  description text not null default '',
  tag text not null default 'Other',
  icon text not null default '✎',
  tone text not null default '',
  saved boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, department_id) references public.departments(organization_id, id) on delete set null (department_id)
);
alter table public.learning_notes add column if not exists organization_id uuid references public.organizations(id) on delete cascade;
alter table public.learning_notes add column if not exists department_id uuid;
alter table public.learning_notes add column if not exists visibility text not null default 'private' check (visibility in ('private', 'workspace'));
create index if not exists learning_notes_owner_updated on public.learning_notes(user_id, updated_at desc);
create index if not exists learning_notes_org_updated on public.learning_notes(organization_id, updated_at desc) where organization_id is not null;

alter table public.organizations enable row level security;
alter table public.departments enable row level security;
alter table public.organization_members enable row level security;
alter table public.organization_invites enable row level security;
alter table public.organization_join_requests enable row level security;
alter table public.learning_notes enable row level security;

-- SECURITY DEFINER helpers prevent recursive policy checks on memberships.
create or replace function public.is_workspace_member(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.organization_members where organization_id = p_organization_id and user_id = auth.uid());
$$;
create or replace function public.is_workspace_admin(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.organization_members where organization_id = p_organization_id and user_id = auth.uid() and role in ('owner', 'admin'));
$$;
revoke all on function public.is_workspace_member(uuid) from public;
revoke all on function public.is_workspace_admin(uuid) from public;
grant execute on function public.is_workspace_member(uuid) to authenticated;
grant execute on function public.is_workspace_admin(uuid) to authenticated;

drop policy if exists "Members can read their organizations" on public.organizations;
create policy "Members can read their organizations" on public.organizations for select to authenticated
using (public.is_workspace_member(id));

drop policy if exists "Members can read departments" on public.departments;
create policy "Members can read departments" on public.departments for select to authenticated
using (public.is_workspace_member(organization_id));

drop policy if exists "Members can read membership list" on public.organization_members;
create policy "Members can read membership list" on public.organization_members for select to authenticated
using (user_id = (select auth.uid()) or public.is_workspace_member(organization_id));

drop policy if exists "Users and admins can read join requests" on public.organization_join_requests;
create policy "Users and admins can read join requests" on public.organization_join_requests for select to authenticated
using (user_id = (select auth.uid()) or public.is_workspace_admin(organization_id));

drop policy if exists "Users can read their notes" on public.learning_notes;
drop policy if exists "Users can create their notes" on public.learning_notes;
drop policy if exists "Users can update their notes" on public.learning_notes;
drop policy if exists "Users can delete their notes" on public.learning_notes;
drop policy if exists "Authors and workspace members can read notes" on public.learning_notes;
create policy "Authors and workspace members can read notes" on public.learning_notes for select to authenticated
using (user_id = (select auth.uid()) or (organization_id is not null and visibility = 'workspace' and public.is_workspace_member(organization_id)));
drop policy if exists "Users can create personal or member notes" on public.learning_notes;
create policy "Users can create personal or member notes" on public.learning_notes for insert to authenticated
with check (user_id = (select auth.uid()) and (organization_id is null or public.is_workspace_member(organization_id)));
drop policy if exists "Authors and workspace admins can update notes" on public.learning_notes;
create policy "Authors and workspace admins can update notes" on public.learning_notes for update to authenticated
using (user_id = (select auth.uid()) or public.is_workspace_admin(organization_id)) with check (user_id = (select auth.uid()) or public.is_workspace_admin(organization_id));
drop policy if exists "Authors and workspace admins can delete notes" on public.learning_notes;
create policy "Authors and workspace admins can delete notes" on public.learning_notes for delete to authenticated
using (user_id = (select auth.uid()) or public.is_workspace_admin(organization_id));

grant select on public.organizations, public.departments, public.organization_members to authenticated;
grant select on public.organization_invites to authenticated;
grant select on public.organization_join_requests to authenticated;
grant select, insert, update, delete on public.learning_notes to authenticated;

create or replace function public.create_workspace(p_name text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_org_id uuid;
  v_department_id uuid;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Sign in to create a workspace.'; end if;
  if char_length(trim(coalesce(p_name, ''))) < 2 or char_length(trim(p_name)) > 120 then raise exception 'Workspace name must be between 2 and 120 characters.'; end if;
  insert into public.organizations(name, created_by) values (trim(p_name), v_user_id) returning id into v_org_id;
  insert into public.departments(organization_id, name) values (v_org_id, 'General') returning id into v_department_id;
  insert into public.organization_members(organization_id, user_id, department_id, role) values (v_org_id, v_user_id, v_department_id, 'owner');
  return v_org_id;
end;
$$;

create or replace function public.create_workspace_department(p_organization_id uuid, p_name text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_department_id uuid;
begin
  if not exists (select 1 from public.organization_members where organization_id = p_organization_id and user_id = auth.uid() and role in ('owner', 'admin')) then raise exception 'Workspace admin access is required.'; end if;
  insert into public.departments(organization_id, name) values (p_organization_id, trim(p_name)) returning id into v_department_id;
  return v_department_id;
end;
$$;

drop function if exists public.create_workspace_invite(uuid, uuid, text);
create or replace function public.create_workspace_invite(p_organization_id uuid, p_department_id uuid default null, p_email_domain text default null, p_invited_email text default null)
returns text language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_code text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if not exists (select 1 from public.organization_members where organization_id = p_organization_id and user_id = auth.uid() and role in ('owner', 'admin')) then raise exception 'Workspace admin access is required.'; end if;
  if nullif(trim(p_invited_email), '') is not null and position('@' in trim(p_invited_email)) < 2 then raise exception 'Enter a valid invitation email address.'; end if;
  if nullif(trim(p_invited_email), '') is not null and nullif(trim(p_email_domain), '') is not null and split_part(lower(trim(p_invited_email)), '@', 2) <> lower(trim(p_email_domain)) then raise exception 'The invited email must match the domain restriction.'; end if;
  if p_department_id is not null and not exists (select 1 from public.departments where id = p_department_id and organization_id = p_organization_id) then raise exception 'Choose a department in this workspace.'; end if;
  insert into public.organization_invites(organization_id, department_id, invite_code, email_domain, invited_email, created_by)
  values (p_organization_id, p_department_id, v_code, nullif(lower(trim(p_email_domain)), ''), nullif(lower(trim(p_invited_email)), ''), auth.uid());
  return v_code;
end;
$$;

drop function if exists public.join_workspace(text);
create or replace function public.join_workspace(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_invite public.organization_invites%rowtype; v_email text := lower(coalesce(auth.jwt() ->> 'email', '')); v_status text;
begin
  if auth.uid() is null then raise exception 'Sign in to join a workspace.'; end if;
  select * into v_invite from public.organization_invites where invite_code = trim(p_code) and expires_at > now();
  if not found then raise exception 'That invitation is invalid or expired.'; end if;
  if v_invite.email_domain is not null and split_part(v_email, '@', 2) <> v_invite.email_domain then raise exception 'This invitation is limited to a different email domain.'; end if;
  if v_invite.invited_email is not null and v_email <> v_invite.invited_email then raise exception 'This invitation was sent to a different email address.'; end if;
  if exists (select 1 from public.organization_members where organization_id = v_invite.organization_id and user_id = auth.uid()) then
    return jsonb_build_object('organization_id', v_invite.organization_id, 'status', 'joined');
  end if;
  insert into public.organization_join_requests(organization_id, user_id, requested_email, department_id, invite_id)
  values (v_invite.organization_id, auth.uid(), v_email, v_invite.department_id, v_invite.id)
  on conflict (organization_id, user_id) do update set
    requested_email = excluded.requested_email, department_id = excluded.department_id, invite_id = excluded.invite_id,
    status = case when public.organization_join_requests.status = 'approved' then 'approved' else 'pending' end,
    requested_at = case when public.organization_join_requests.status = 'rejected' then now() else public.organization_join_requests.requested_at end,
    decided_at = case when public.organization_join_requests.status = 'rejected' then null else public.organization_join_requests.decided_at end,
    decided_by = case when public.organization_join_requests.status = 'rejected' then null else public.organization_join_requests.decided_by end
  returning status into v_status;
  return jsonb_build_object('organization_id', v_invite.organization_id, 'status', v_status);
end;
$$;

create or replace function public.review_workspace_join_request(p_request_id uuid, p_decision text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_request public.organization_join_requests%rowtype;
begin
  if p_decision is null or p_decision not in ('approved', 'rejected') then raise exception 'Choose approve or reject.'; end if;
  select * into v_request from public.organization_join_requests where id = p_request_id for update;
  if not found then raise exception 'Join request not found.'; end if;
  if not public.is_workspace_admin(v_request.organization_id) then raise exception 'Workspace admin access is required.'; end if;
  if v_request.status <> 'pending' then raise exception 'This request has already been reviewed.'; end if;
  update public.organization_join_requests set status = p_decision, decided_at = now(), decided_by = auth.uid() where id = p_request_id;
  if p_decision = 'approved' then
    insert into public.organization_members(organization_id, user_id, department_id, role)
    values (v_request.organization_id, v_request.user_id, v_request.department_id, 'member')
    on conflict (organization_id, user_id) do nothing;
  end if;
  return v_request.organization_id;
end;
$$;

revoke all on function public.create_workspace(text) from public;
revoke all on function public.create_workspace_department(uuid, text) from public;
revoke all on function public.create_workspace_invite(uuid, uuid, text, text) from public;
revoke all on function public.join_workspace(text) from public;
revoke all on function public.review_workspace_join_request(uuid, text) from public;
grant execute on function public.create_workspace(text) to authenticated;
grant execute on function public.create_workspace_department(uuid, text) to authenticated;
grant execute on function public.create_workspace_invite(uuid, uuid, text, text) to authenticated;
grant execute on function public.join_workspace(text) to authenticated;
grant execute on function public.review_workspace_join_request(uuid, text) to authenticated;

-- Refresh PostgREST's RPC and relationship cache after applying this migration.
notify pgrst, 'reload schema';
