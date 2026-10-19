-- Additive migration: shared Trello-style team boards.
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
  (assignee_id is null or exists (
    select 1 from public.organization_members m
    where m.organization_id = team_board_cards.organization_id and m.user_id = team_board_cards.assignee_id
  ))
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

notify pgrst, 'reload schema';
