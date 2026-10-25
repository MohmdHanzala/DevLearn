-- Record a single, human-readable audit event for each dragged card. Neighbor
-- cards whose positions shift are not logged as separate user actions.
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

  perform set_config('onward.audit_move_card_id', v_card.id::text, true);
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

create or replace function public.capture_organization_audit()
returns trigger language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  v_row jsonb;
  v_old jsonb;
  v_new jsonb;
  v_org_id uuid;
  v_entity_id text;
  v_actor_email text;
  v_move_card_id text;
  v_from_list_name text;
  v_to_list_name text;
begin
  if tg_op <> 'INSERT' then v_old := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_new := to_jsonb(new); end if;
  if tg_table_name = 'team_board_cards' and tg_op = 'UPDATE' then
    v_move_card_id := nullif(current_setting('onward.audit_move_card_id', true), '');
    if v_move_card_id is not null and old.id::text <> v_move_card_id
      and old.list_id is not distinct from new.list_id
      and old.position is distinct from new.position then
      return new;
    end if;
    select name into v_from_list_name from public.team_board_lists where id = old.list_id;
    select name into v_to_list_name from public.team_board_lists where id = new.list_id;
    v_old := v_old || jsonb_build_object('_list_name', coalesce(v_from_list_name, 'Removed list'));
    v_new := v_new || jsonb_build_object('_list_name', coalesce(v_to_list_name, 'Removed list'));
  end if;
  v_row := coalesce(v_new, v_old);
  if tg_table_name = 'organizations' then v_org_id := (v_row->>'id')::uuid;
  else v_org_id := (v_row->>'organization_id')::uuid; end if;
  if v_org_id is null then if tg_op = 'DELETE' then return old; else return new; end if; end if;
  v_entity_id := coalesce(v_row->>'id', v_row->>'user_id', v_row->>'invite_id');
  select email::text into v_actor_email from auth.users where id = auth.uid();
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
notify pgrst, 'reload schema';
