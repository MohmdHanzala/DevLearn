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
