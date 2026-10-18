-- DevLearn per-user learning notes. Run in the Supabase SQL Editor.
create table if not exists public.learning_notes (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 title text not null check (char_length(title) between 1 and 180), description text not null default '', tag text not null default 'Other', icon text not null default '✎', tone text not null default '', saved boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.learning_notes enable row level security;
drop policy if exists "Users can manage their notes" on public.learning_notes;
create policy "Users can manage their notes" on public.learning_notes for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
grant select, insert, update, delete on public.learning_notes to authenticated;
