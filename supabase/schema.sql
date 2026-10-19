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

-- Shared team project boards. Personal workspaces keep the learning companion;
-- organization workspaces use boards, ordered lists, and assignable task cards.
create table if not exists public.team_boards (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 100),
  description text not null default '',
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id)
);
create table if not exists public.team_board_lists (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  board_id uuid not null,
  name text not null check (char_length(trim(name)) between 1 and 80),
  position numeric not null default 0,
  created_at timestamptz not null default now(),
  unique (organization_id, board_id, id),
  foreign key (organization_id, board_id) references public.team_boards(organization_id, id) on delete cascade
);
create table if not exists public.team_board_cards (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  board_id uuid not null,
  list_id uuid not null,
  title text not null check (char_length(trim(title)) between 1 and 180),
  description text not null default '',
  assignee_id uuid references auth.users(id) on delete set null,
  due_date date,
  position numeric not null default 0,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, board_id) references public.team_boards(organization_id, id) on delete cascade,
  foreign key (organization_id, board_id, list_id) references public.team_board_lists(organization_id, board_id, id) on delete cascade
);
create index if not exists team_boards_by_org on public.team_boards(organization_id, updated_at desc);
create index if not exists team_board_lists_order on public.team_board_lists(board_id, position);
create index if not exists team_board_cards_order on public.team_board_cards(list_id, position);
create index if not exists team_board_cards_assignee on public.team_board_cards(organization_id, assignee_id) where assignee_id is not null;

alter table public.team_boards enable row level security;
alter table public.team_board_lists enable row level security;
alter table public.team_board_cards enable row level security;
drop policy if exists "Workspace members manage team boards" on public.team_boards;
create policy "Workspace members manage team boards" on public.team_boards for all to authenticated
using (public.is_workspace_member(organization_id)) with check (public.is_workspace_member(organization_id));
drop policy if exists "Workspace members manage board lists" on public.team_board_lists;
create policy "Workspace members manage board lists" on public.team_board_lists for all to authenticated
using (public.is_workspace_member(organization_id)) with check (public.is_workspace_member(organization_id));
drop policy if exists "Workspace members manage board cards" on public.team_board_cards;
create policy "Workspace members manage board cards" on public.team_board_cards for all to authenticated
using (public.is_workspace_member(organization_id)) with check (
  public.is_workspace_member(organization_id) and
  (assignee_id is null or exists (select 1 from public.organization_members m where m.organization_id = team_board_cards.organization_id and m.user_id = team_board_cards.assignee_id))
);
grant select, insert, update, delete on public.team_boards, public.team_board_lists, public.team_board_cards to authenticated;

create or replace function public.list_workspace_members(p_organization_id uuid)
returns table(user_id uuid, email text, role text, department_id uuid)
language plpgsql stable security definer set search_path = public, auth, pg_temp as $$
begin
  if not public.is_workspace_member(p_organization_id) then raise exception 'Workspace membership is required.'; end if;
  return query
    select m.user_id, u.email::text, m.role, m.department_id
    from public.organization_members m join auth.users u on u.id = m.user_id
    where m.organization_id = p_organization_id order by m.joined_at;
end;
$$;
revoke all on function public.list_workspace_members(uuid) from public;
grant execute on function public.list_workspace_members(uuid) to authenticated;

create or replace function public.create_team_board(p_organization_id uuid, p_name text, p_description text default '')
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_board_id uuid;
begin
  if auth.uid() is null or not public.is_workspace_member(p_organization_id) then raise exception 'Workspace membership is required.'; end if;
  if char_length(trim(coalesce(p_name, ''))) < 1 or char_length(trim(p_name)) > 100 then raise exception 'Board name must be between 1 and 100 characters.'; end if;
  insert into public.team_boards(organization_id, name, description, created_by)
    values(p_organization_id, trim(p_name), coalesce(p_description, ''), auth.uid()) returning id into v_board_id;
  insert into public.team_board_lists(organization_id, board_id, name, position) values
    (p_organization_id, v_board_id, 'To do', 0),
    (p_organization_id, v_board_id, 'In progress', 1),
    (p_organization_id, v_board_id, 'Done', 2);
  return v_board_id;
end;
$$;
revoke all on function public.create_team_board(uuid, text, text) from public;
grant execute on function public.create_team_board(uuid, text, text) to authenticated;

create or replace function public.move_team_board_card(p_card_id uuid, p_target_list_id uuid, p_position integer)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_card public.team_board_cards%rowtype;
  v_target_count integer;
begin
  select * into v_card from public.team_board_cards where id = p_card_id for update;
  if not found then raise exception 'Card not found.'; end if;
  if not public.is_workspace_member(v_card.organization_id) then raise exception 'Workspace membership is required.'; end if;
  perform 1 from public.team_board_lists where id = v_card.list_id for update;
  perform 1 from public.team_board_lists where id = p_target_list_id and board_id = v_card.board_id and organization_id = v_card.organization_id for update;
  if not found then raise exception 'Choose a list on this board.'; end if;
  if p_position is null then raise exception 'Choose a card position.'; end if;
  select count(*) into v_target_count from public.team_board_cards
    where list_id = p_target_list_id and (p_target_list_id <> v_card.list_id or id <> v_card.id);
  if p_position < 0 or p_position > v_target_count then raise exception 'The requested card position is invalid.'; end if;
  if v_card.list_id = p_target_list_id then
    if p_position < v_card.position then
      update public.team_board_cards set position = position + 1
        where list_id = v_card.list_id and id <> v_card.id and position >= p_position and position < v_card.position;
    elsif p_position > v_card.position then
      update public.team_board_cards set position = position - 1
        where list_id = v_card.list_id and id <> v_card.id and position > v_card.position and position <= p_position;
    end if;
  else
    update public.team_board_cards set position = position - 1
      where list_id = v_card.list_id and position > v_card.position;
    update public.team_board_cards set position = position + 1
      where list_id = p_target_list_id and position >= p_position;
  end if;
  update public.team_board_cards set list_id = p_target_list_id, position = p_position, updated_at = now() where id = v_card.id;
  return v_card.id;
end;
$$;
revoke all on function public.move_team_board_card(uuid, uuid, integer) from public;
grant execute on function public.move_team_board_card(uuid, uuid, integer) to authenticated;

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
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_invite public.organization_invites%rowtype;
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_email_verified boolean;
  v_status text;
begin
  if auth.uid() is null then raise exception 'Sign in to join a workspace.'; end if;
  select * into v_invite from public.organization_invites where invite_code = trim(p_code) and expires_at > now();
  if not found then raise exception 'That invitation is invalid or expired.'; end if;
  if v_invite.email_domain is not null and split_part(v_email, '@', 2) <> v_invite.email_domain then raise exception 'This invitation is limited to a different email domain.'; end if;
  if v_invite.invited_email is not null then
    if v_email <> v_invite.invited_email then raise exception 'Sign in with the email address this invitation was sent to.'; end if;
    select email_confirmed_at is not null into v_email_verified from auth.users where id = auth.uid() and lower(email) = v_invite.invited_email;
    if not coalesce(v_email_verified, false) then raise exception 'Confirm the invited email address before accepting this invitation.'; end if;
    insert into public.organization_members(organization_id, user_id, department_id, role)
    values (v_invite.organization_id, auth.uid(), v_invite.department_id, 'member')
    on conflict (organization_id, user_id) do nothing;
    update public.organization_join_requests
      set status = 'approved', decided_at = now(), decided_by = null
      where organization_id = v_invite.organization_id and user_id = auth.uid() and status = 'pending';
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


-- Owner-only change history for all team workspace administration and tracker data.
create table if not exists public.organization_audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_id uuid,
  actor_email text,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  entity_type text not null,
  entity_id text,
  before_data jsonb,
  after_data jsonb,
  occurred_at timestamptz not null default now()
);
create index if not exists organization_audit_logs_recent on public.organization_audit_logs(organization_id, occurred_at desc, id desc);
alter table public.organization_audit_logs enable row level security;
drop policy if exists "Workspace owners read audit logs" on public.organization_audit_logs;
create policy "Workspace owners read audit logs" on public.organization_audit_logs
  for select to authenticated using (
    exists (select 1 from public.organization_members m
      where m.organization_id = organization_audit_logs.organization_id
        and m.user_id = auth.uid() and m.role = 'owner')
  );
revoke all on public.organization_audit_logs from public, anon, authenticated;
grant select on public.organization_audit_logs to authenticated;

create or replace function public.capture_organization_audit()
returns trigger language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  v_row jsonb;
  v_old jsonb;
  v_new jsonb;
  v_org_id uuid;
  v_entity_id text;
  v_actor_email text;
begin
  if tg_op <> 'INSERT' then v_old := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_new := to_jsonb(new); end if;
  v_row := coalesce(v_new, v_old);
  if tg_table_name = 'organizations' then v_org_id := (v_row->>'id')::uuid;
  else v_org_id := (v_row->>'organization_id')::uuid; end if;
  if v_org_id is null then if tg_op = 'DELETE' then return old; else return new; end if; end if;
  v_entity_id := coalesce(v_row->>'id', v_row->>'user_id', v_row->>'invite_id');
  select email::text into v_actor_email from auth.users where id = auth.uid();
  -- Invitation bearer codes are never copied into the audit trail.
  if v_old is not null then v_old := v_old - 'invite_code'; end if;
  if v_new is not null then v_new := v_new - 'invite_code'; end if;
  insert into public.organization_audit_logs(
    organization_id, actor_id, actor_email, action, entity_type, entity_id, before_data, after_data
  ) values (
    v_org_id, auth.uid(), v_actor_email, tg_op, tg_table_name, v_entity_id, v_old, v_new
  );
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function public.capture_organization_audit() from public, anon, authenticated;

drop trigger if exists audit_organizations on public.organizations;
create trigger audit_organizations after insert or update or delete on public.organizations for each row execute function public.capture_organization_audit();
drop trigger if exists audit_departments on public.departments;
create trigger audit_departments after insert or update or delete on public.departments for each row execute function public.capture_organization_audit();
drop trigger if exists audit_organization_members on public.organization_members;
create trigger audit_organization_members after insert or update or delete on public.organization_members for each row execute function public.capture_organization_audit();
drop trigger if exists audit_organization_invites on public.organization_invites;
create trigger audit_organization_invites after insert or update or delete on public.organization_invites for each row execute function public.capture_organization_audit();
drop trigger if exists audit_join_requests on public.organization_join_requests;
create trigger audit_join_requests after insert or update or delete on public.organization_join_requests for each row execute function public.capture_organization_audit();
drop trigger if exists audit_team_boards on public.team_boards;
create trigger audit_team_boards after insert or update or delete on public.team_boards for each row execute function public.capture_organization_audit();
drop trigger if exists audit_team_board_lists on public.team_board_lists;
create trigger audit_team_board_lists after insert or update or delete on public.team_board_lists for each row execute function public.capture_organization_audit();
drop trigger if exists audit_team_board_cards on public.team_board_cards;
create trigger audit_team_board_cards after insert or update or delete on public.team_board_cards for each row execute function public.capture_organization_audit();
notify pgrst, 'reload schema';


drop trigger if exists audit_learning_notes on public.learning_notes;
create trigger audit_learning_notes after insert or update or delete on public.learning_notes for each row execute function public.capture_organization_audit();
notify pgrst, 'reload schema';

-- Private per-user calendar days used by the learning streak.
create table if not exists public.learning_activity_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_date date not null,
  created_at timestamptz not null default now(),
  primary key (user_id, activity_date)
);
alter table public.learning_activity_days enable row level security;
drop policy if exists "Users manage their own learning activity days" on public.learning_activity_days;
create policy "Users manage their own learning activity days" on public.learning_activity_days
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.learning_activity_days from public, anon, authenticated;
grant select, insert, update on public.learning_activity_days to authenticated;
notify pgrst, 'reload schema';

-- Atomic per-user Gemini request cap. The counter stores only the current UTC day
-- per account, so the table remains small and client code cannot raise the limit.
create table if not exists public.gemini_daily_usage (
  user_id uuid primary key references auth.users(id) on delete cascade,
  usage_date date not null,
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now()
);
alter table public.gemini_daily_usage enable row level security;
revoke all on public.gemini_daily_usage from public, anon, authenticated;

create or replace function public.consume_gemini_daily_quota()
returns table (allowed boolean, used integer, daily_limit integer, resets_at timestamptz)
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_today date := (now() at time zone 'UTC')::date;
  v_used integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  insert into public.gemini_daily_usage as usage (user_id, usage_date, request_count, updated_at)
  values (v_user_id, v_today, 1, now())
  on conflict (user_id) do update
    set usage_date = excluded.usage_date,
        request_count = case
          when usage.usage_date = excluded.usage_date then usage.request_count + 1
          else 1
        end,
        updated_at = now()
    where usage.usage_date <> excluded.usage_date or usage.request_count < 20
  returning request_count into v_used;

  if v_used is null then
    select usage.request_count into v_used
    from public.gemini_daily_usage as usage
    where usage.user_id = v_user_id;
  end if;

  return query select v_used <= 20, v_used, 20, ((v_today + 1)::timestamp at time zone 'UTC');
end;
$$;
revoke all on function public.consume_gemini_daily_quota() from public, anon;
grant execute on function public.consume_gemini_daily_quota() to authenticated;
notify pgrst, 'reload schema';

