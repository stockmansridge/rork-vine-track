-- Historical Growing Degree Days storage
-- Caches per-station daily GDD values pulled from Weather Underground.
-- Shared across all users / vineyards using the same station.

create table if not exists public.weather_daily_gdd (
    station_id text not null,
    date date not null,
    gdd numeric not null,
    temp_high numeric,
    temp_low numeric,
    base_temp numeric not null default 10,
    updated_at timestamptz not null default now(),
    primary key (station_id, date)
);

create index if not exists idx_weather_daily_gdd_station_date
    on public.weather_daily_gdd (station_id, date);

alter table public.weather_daily_gdd enable row level security;

drop policy if exists "weather_daily_gdd_select" on public.weather_daily_gdd;
create policy "weather_daily_gdd_select"
    on public.weather_daily_gdd for select
    to authenticated
    using (true);

drop policy if exists "weather_daily_gdd_insert" on public.weather_daily_gdd;
create policy "weather_daily_gdd_insert"
    on public.weather_daily_gdd for insert
    to authenticated
    with check (true);

drop policy if exists "weather_daily_gdd_update" on public.weather_daily_gdd;
create policy "weather_daily_gdd_update"
    on public.weather_daily_gdd for update
    to authenticated
    using (true);
