-- RideMate upgrade 02: commute, saved routes, recurring/monthly seats, route catalog
-- Safe to run on an existing RideMate database after schema.sql.

alter table public.rides add column if not exists route_code text;
alter table public.rides add column if not exists route_name text;
alter table public.rides add column if not exists trip_type text not null default 'one_way' check (trip_type in ('one_way','return','morning','evening'));
alter table public.rides add column if not exists recurrence_type text not null default 'once' check (recurrence_type in ('once','daily','weekdays','custom'));
alter table public.rides add column if not exists recurrence_days text;
alter table public.rides add column if not exists return_time text;
alter table public.rides add column if not exists allow_monthly_booking boolean not null default false;
alter table public.rides add column if not exists monthly_price numeric(10,2) check (monthly_price is null or monthly_price >= 0);
alter table public.rides add column if not exists pickup_visibility text not null default 'public_point';

alter table public.bookings add column if not exists booking_type text not null default 'single' check (booking_type in ('single','monthly'));
alter table public.bookings add column if not exists payment_method text;
alter table public.bookings add column if not exists payment_reference text;

alter table public.profiles add column if not exists phone_verified boolean not null default false;
alter table public.profiles add column if not exists identity_verified boolean not null default false;
alter table public.profiles add column if not exists completed_rides int not null default 0;
alter table public.profiles add column if not exists cancellation_count int not null default 0;

create table if not exists public.saved_routes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  from_city text not null,
  to_city text not null,
  pickup_area text,
  dropoff_area text,
  trip_type text default 'daily',
  preferred_time text,
  notify_enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.route_catalog (
  code text primary key,
  name text not null,
  from_city text not null,
  to_city text not null,
  pickup_area text,
  dropoff_area text,
  via text,
  distance_label text,
  time_label text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.pickup_points (
  id uuid primary key default gen_random_uuid(),
  city text not null,
  area text not null,
  point_name text not null,
  point_type text default 'public',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(city, point_name)
);

create table if not exists public.search_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  from_city text,
  to_city text,
  results_count int default 0,
  created_at timestamptz not null default now()
);

alter table public.saved_routes enable row level security;
alter table public.route_catalog enable row level security;
alter table public.pickup_points enable row level security;
alter table public.search_logs enable row level security;

do $$ begin
  create policy "saved_routes_own" on public.saved_routes for all to authenticated using (user_id = auth.uid() or public.is_admin()) with check (user_id = auth.uid() or public.is_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "route_catalog_read" on public.route_catalog for select to authenticated using (is_active = true or public.is_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "route_catalog_admin" on public.route_catalog for all to authenticated using (public.is_admin()) with check (public.is_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "pickup_points_read" on public.pickup_points for select to authenticated using (is_active = true or public.is_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "pickup_points_admin" on public.pickup_points for all to authenticated using (public.is_admin()) with check (public.is_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "search_logs_insert_own" on public.search_logs for insert to authenticated with check (user_id = auth.uid());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "search_logs_admin_read" on public.search_logs for select to authenticated using (public.is_admin());
exception when duplicate_object then null; end $$;

insert into public.route_catalog(code,name,from_city,to_city,pickup_area,dropoff_area,via,distance_label,time_label) values
('WAH-ISB-BLUE','Wah Cantt → Islamabad Blue Area','Wah Cantt','Islamabad','Wah Cantt Barrier 2 / GT Road','Blue Area / PIMS / F-8','GT Road → Taxila → Margalla Road/Golra → G-9/G-8 → Blue Area','36–60 km depending pickup','35–70 min'),
('WAH-ISB-G13','Wah Cantt → Islamabad G-13/G-11','Wah Cantt','Islamabad','Wah Model Town / Barrier 2','G-13 / G-11 / NUST side','GT Road → Taxila → Golra Mor → Srinagar/Margalla side','35–50 km','35–60 min'),
('WAH-ISB-I8','Wah Cantt → Islamabad I-8/I-9','Wah Cantt','Islamabad','Wah Cantt Gate/Barrier','I-8 / I-9 / Faizabad','GT Road → Rawalpindi/Islamabad link → IJP/Faizabad','45–60 km','50–85 min'),
('WAH-RWP-SADDAR','Wah Cantt → Rawalpindi Saddar','Wah Cantt','Rawalpindi','Wah Cantt Barrier 2 / Lala Rukh / Taxila','Saddar / MH / RA Bazar','GT Road → Taxila → Tarnol/Chungi → Rawalpindi Saddar','35–45 km','35–65 min'),
('WAH-RWP-FAIZABAD','Wah Cantt → Rawalpindi/Faizabad','Wah Cantt','Rawalpindi','Wah Model Town / New City / Taxila','Faizabad / Murree Road / Shamsabad','GT Road → IJP Road/Faizabad corridor','45–60 km','50–90 min'),
('RWP-ISB-BLUE','Rawalpindi → Islamabad Blue Area','Rawalpindi','Islamabad','Saddar / Murree Road / Faizabad','Blue Area / G-8 / F-8','Murree Road/Faizabad → Islamabad Expressway/Zero Point → Blue Area','15–25 km','25–60 min'),
('RWP-ISB-I8','Rawalpindi → Islamabad I-8/I-9','Rawalpindi','Islamabad','Commercial Market / Saddar / Faizabad','I-8 / I-9 / I-10','Murree Road/Faizabad → IJP/I-8 corridor','10–20 km','20–45 min'),
('ISB-WAH-EVENING','Islamabad → Wah Cantt Evening Return','Islamabad','Wah Cantt','Blue Area / F-8 / G-9 / G-13','Wah Cantt Barrier 2 / Wah Model Town','Islamabad sectors → Golra/Margalla Road or GT Road → Taxila → Wah','36–60 km','45–90 min'),
('RWP-WAH-EVENING','Rawalpindi → Wah Cantt Evening Return','Rawalpindi','Wah Cantt','Saddar / RA Bazar / Faizabad','Wah Cantt / Taxila / New City','Rawalpindi → GT Road → Taxila → Wah Cantt','35–60 km','45–90 min')
on conflict (code) do update set name=excluded.name, pickup_area=excluded.pickup_area, dropoff_area=excluded.dropoff_area, via=excluded.via, distance_label=excluded.distance_label, time_label=excluded.time_label;

insert into public.pickup_points(city,area,point_name) values
('Wah Cantt','GT Road','Wah Cantt Barrier 2'),
('Wah Cantt','GT Road','Wah Cantt Gate Number 1'),
('Wah Cantt','Wah Model Town','Wah Model Town Phase 1 Gate'),
('Wah Cantt','Lala Rukh','Basti Lala Rukh Stop'),
('Taxila','GT Road','Taxila Chowk'),
('Islamabad','Blue Area','Blue Area / PIMS side'),
('Islamabad','F-8','F-8 Markaz'),
('Islamabad','G-9','G-9 Markaz'),
('Islamabad','G-13','G-13 Markaz'),
('Islamabad','I-8','I-8 Markaz'),
('Islamabad','Faizabad','Faizabad Interchange'),
('Rawalpindi','Saddar','Saddar / MH'),
('Rawalpindi','RA Bazar','RA Bazar'),
('Rawalpindi','Commercial Market','Commercial Market'),
('Rawalpindi','Murree Road','Shamsabad')
on conflict (city, point_name) do nothing;

create or replace view public.rides_public as
select r.*, p.full_name as driver_name, p.gender as driver_gender, p.rating as driver_rating, p.phone_verified, p.identity_verified, p.completed_rides, p.cancellation_count,
       v.car_model, v.plate_number, v.color, v.is_verified as vehicle_verified,
       greatest(r.total_seats - coalesce((select sum(b.seats_requested) from public.bookings b where b.ride_id = r.id and b.status = 'accepted'),0),0) as seats_left
from public.rides r
join public.profiles p on p.id = r.driver_id
join public.vehicles v on v.id = r.vehicle_id;

create or replace view public.bookings_public as
select b.*, r.driver_id, r.from_city, r.to_city, r.pickup_area, r.dropoff_area, r.departure_at, r.ride_rule, r.route_name, r.trip_type, r.recurrence_type, r.allow_monthly_booking, r.monthly_price,
       dp.full_name as driver_name, dp.gender as driver_gender,
       pp.full_name as passenger_name, pp.gender as passenger_gender, pp.travel_mode
from public.bookings b
join public.rides r on r.id = b.ride_id
join public.profiles dp on dp.id = r.driver_id
join public.profiles pp on pp.id = b.passenger_id;

create or replace function public.create_ride(
  p_vehicle_id uuid, p_from_city text, p_to_city text, p_pickup_area text, p_dropoff_area text,
  p_departure_at timestamptz, p_total_seats int, p_price_per_seat numeric, p_ride_rule public.ride_rule_type, p_notes text default null,
  p_route_code text default null, p_route_name text default null, p_trip_type text default 'one_way', p_recurrence_type text default 'once',
  p_recurrence_days text default null, p_return_time text default null, p_allow_monthly_booking boolean default false, p_monthly_price numeric default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_driver uuid := auth.uid();
begin
  if not exists(select 1 from public.profiles where id=v_driver and role='driver' and status='active') then raise exception 'Only active drivers can post rides'; end if;
  if not exists(select 1 from public.vehicles where id=p_vehicle_id and owner_id=v_driver) then raise exception 'Vehicle not found'; end if;
  if p_departure_at <= now() then raise exception 'Departure time must be in future'; end if;
  insert into public.rides(driver_id, vehicle_id, from_city, to_city, pickup_area, dropoff_area, departure_at, total_seats, price_per_seat, ride_rule, notes, route_code, route_name, trip_type, recurrence_type, recurrence_days, return_time, allow_monthly_booking, monthly_price)
  values(v_driver, p_vehicle_id, trim(p_from_city), trim(p_to_city), trim(p_pickup_area), trim(p_dropoff_area), p_departure_at, p_total_seats, p_price_per_seat, p_ride_rule, p_notes, p_route_code, p_route_name, p_trip_type, p_recurrence_type, p_recurrence_days, p_return_time, p_allow_monthly_booking, p_monthly_price)
  returning id into v_id;
  return v_id;
end; $$;

create or replace function public.admin_dashboard()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.is_admin() then jsonb_build_object(
    'total_users',(select count(*) from public.profiles),
    'drivers',(select count(*) from public.profiles where role='driver'),
    'passengers',(select count(*) from public.profiles where role='passenger'),
    'open_rides',(select count(*) from public.rides where status='open'),
    'pending_bookings',(select count(*) from public.bookings where status='pending'),
    'paid_bookings',(select count(*) from public.bookings where payment_status='paid'),
    'saved_routes',(select count(*) from public.saved_routes),
    'open_reports',(select count(*) from public.reports where status='open')
  ) else '{}'::jsonb end
$$;
