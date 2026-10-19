-- Apply this in the Supabase SQL Editor to enable the 20-request daily cap.
-- The function counts requests in UTC and enforces the limit atomically per user.
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
