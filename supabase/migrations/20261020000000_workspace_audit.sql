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
