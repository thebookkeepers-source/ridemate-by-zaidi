-- RideMate final public app schema
-- Run this entire file once in Supabase SQL Editor.

create extension if not exists pgcrypto;

create type public.user_role as enum ('passenger','driver','admin');
create type public.gender_type as enum ('male','female');
create type public.travel_mode_type as enum ('solo','family');
create type public.user_status as enum ('active','suspended');
create type public.ride_rule_type as enum ('mixed','male_only','female_only','family_only');
create type public.ride_status as enum ('open','closed','cancelled','completed');
create type public.booking_status as enum ('pending','accepted','rejected','cancelled','completed');
create type public.payment_status as enum ('unpaid','paid','refunded','not_required');
create type public.report_status as enum ('open','reviewing','resolved');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role public.user_role not null default 'passenger',
  gender public.gender_type not null,
  travel_mode public.travel_mode_type not null default 'solo',
  rating numeric(3,2) not null default 5.00 check (rating >= 0 and rating <= 5),
  status public.user_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.private_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  phone text not null,
  emergency_contact text,
  cnic_last4 text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  car_model text not null,
  plate_number text not null,
  color text,
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  unique(owner_id, plate_number)
);

create table public.rides (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id),
  from_city text not null,
  to_city text not null,
  pickup_area text not null,
  dropoff_area text not null,
  departure_at timestamptz not null,
  total_seats int not null check (total_seats between 1 and 6),
  price_per_seat numeric(10,2) not null check (price_per_seat >= 0),
  ride_rule public.ride_rule_type not null default 'mixed',
  status public.ride_status not null default 'open',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete cascade,
  passenger_id uuid not null references public.profiles(id) on delete cascade,
  seats_requested int not null default 1 check (seats_requested = 1),
  status public.booking_status not null default 'pending',
  payment_status public.payment_status not null default 'unpaid',
  note text,
  reject_reason text,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(ride_id, passenger_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid references public.profiles(id) on delete set null,
  ride_id uuid references public.rides(id) on delete set null,
  booking_id uuid references public.bookings(id) on delete set null,
  report_type text not null,
  details text not null,
  status public.report_status not null default 'open',
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index rides_search_idx on public.rides(status, departure_at, from_city, to_city);
create index bookings_ride_status_idx on public.bookings(ride_id, status);
create index bookings_passenger_idx on public.bookings(passenger_id, status);
create index reports_status_idx on public.reports(status, created_at desc);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;
create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();
create trigger private_profiles_touch before update on public.private_profiles for each row execute function public.touch_updated_at();
create trigger rides_touch before update on public.rides for each row execute function public.touch_updated_at();
create trigger bookings_touch before update on public.bookings for each row execute function public.touch_updated_at();
create trigger reports_touch before update on public.reports for each row execute function public.touch_updated_at();

create or replace function public.is_admin(p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles p where p.id = p_user and p.role = 'admin' and p.status='active')
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_role public.user_role;
  v_gender public.gender_type;
begin
  v_role := case when new.raw_user_meta_data->>'role' in ('passenger','driver') then (new.raw_user_meta_data->>'role')::public.user_role else 'passenger'::public.user_role end;
  v_gender := case when new.raw_user_meta_data->>'gender' in ('male','female') then (new.raw_user_meta_data->>'gender')::public.gender_type else 'male'::public.gender_type end;
  insert into public.profiles(id, full_name, role, gender)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)), v_role, v_gender)
  on conflict (id) do nothing;
  insert into public.private_profiles(user_id, phone)
  values (new.id, coalesce(new.raw_user_meta_data->>'phone',''))
  on conflict (user_id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.private_profiles enable row level security;
alter table public.vehicles enable row level security;
alter table public.rides enable row level security;
alter table public.bookings enable row level security;
alter table public.reports enable row level security;
alter table public.notifications enable row level security;

-- Profiles: users can see public profile basics, edit their own; admins manage all.
create policy "profiles_select_authenticated" on public.profiles for select to authenticated using (true);
create policy "profiles_update_own" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid() and role <> 'admin');
create policy "profiles_admin_all" on public.profiles for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Private contact data is private. Contacts are released only through get_booking_contact RPC.
create policy "private_select_own_or_admin" on public.private_profiles for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "private_update_own" on public.private_profiles for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "private_admin_all" on public.private_profiles for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "vehicles_select_authenticated" on public.vehicles for select to authenticated using (true);
create policy "vehicles_insert_driver" on public.vehicles for insert to authenticated with check (owner_id = auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='driver' and p.status='active'));
create policy "vehicles_update_owner" on public.vehicles for update to authenticated using (owner_id = auth.uid() or public.is_admin()) with check (owner_id = auth.uid() or public.is_admin());
create policy "vehicles_delete_owner" on public.vehicles for delete to authenticated using (owner_id = auth.uid() or public.is_admin());

create policy "rides_select_authenticated" on public.rides for select to authenticated using (true);
create policy "rides_admin_all" on public.rides for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "bookings_select_involved" on public.bookings for select to authenticated using (
  passenger_id = auth.uid() or public.is_admin() or exists(select 1 from public.rides r where r.id = ride_id and r.driver_id = auth.uid())
);
create policy "bookings_admin_all" on public.bookings for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "reports_insert_own" on public.reports for insert to authenticated with check (reporter_id = auth.uid());
create policy "reports_select_own_or_admin" on public.reports for select to authenticated using (reporter_id = auth.uid() or public.is_admin());
create policy "reports_update_admin" on public.reports for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "notifications_own" on public.notifications for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "notifications_update_own" on public.notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace view public.rides_public as
select r.*, p.full_name as driver_name, p.gender as driver_gender, p.rating as driver_rating,
       v.car_model, v.plate_number, v.color,
       greatest(r.total_seats - coalesce((select sum(b.seats_requested) from public.bookings b where b.ride_id = r.id and b.status = 'accepted'),0),0) as seats_left
from public.rides r
join public.profiles p on p.id = r.driver_id
join public.vehicles v on v.id = r.vehicle_id;

create or replace view public.bookings_public as
select b.*, r.driver_id, r.from_city, r.to_city, r.pickup_area, r.dropoff_area, r.departure_at, r.ride_rule,
       dp.full_name as driver_name, dp.gender as driver_gender,
       pp.full_name as passenger_name, pp.gender as passenger_gender, pp.travel_mode
from public.bookings b
join public.rides r on r.id = b.ride_id
join public.profiles dp on dp.id = r.driver_id
join public.profiles pp on pp.id = b.passenger_id;

create or replace view public.reports_public as
select rep.*, p.full_name as reporter_name, rp.full_name as reported_user_name
from public.reports rep
join public.profiles p on p.id = rep.reporter_id
left join public.profiles rp on rp.id = rep.reported_user_id;

create or replace function public.ensure_passenger_allowed(p_ride_id uuid, p_passenger_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  rr public.ride_rule_type; pg public.gender_type; tm public.travel_mode_type; p_role public.user_role; p_status public.user_status;
begin
  select ride_rule into rr from public.rides where id=p_ride_id;
  select role, gender, travel_mode, status into p_role, pg, tm, p_status from public.profiles where id=p_passenger_id;
  if p_role <> 'passenger' then raise exception 'Only passenger accounts can book rides'; end if;
  if p_status <> 'active' then raise exception 'Your account is not active'; end if;
  if rr = 'male_only' and pg <> 'male' then raise exception 'This ride allows male passengers only'; end if;
  if rr = 'female_only' and pg <> 'female' then raise exception 'This ride allows female passengers only'; end if;
  if rr = 'family_only' and tm <> 'family' then raise exception 'This ride is for family profiles only'; end if;
end; $$;

create or replace function public.create_ride(
  p_vehicle_id uuid, p_from_city text, p_to_city text, p_pickup_area text, p_dropoff_area text,
  p_departure_at timestamptz, p_total_seats int, p_price_per_seat numeric, p_ride_rule public.ride_rule_type, p_notes text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_driver uuid := auth.uid();
begin
  if not exists(select 1 from public.profiles where id=v_driver and role='driver' and status='active') then raise exception 'Only active drivers can post rides'; end if;
  if not exists(select 1 from public.vehicles where id=p_vehicle_id and owner_id=v_driver) then raise exception 'Vehicle not found'; end if;
  if p_departure_at <= now() then raise exception 'Departure time must be in future'; end if;
  insert into public.rides(driver_id, vehicle_id, from_city, to_city, pickup_area, dropoff_area, departure_at, total_seats, price_per_seat, ride_rule, notes)
  values(v_driver, p_vehicle_id, trim(p_from_city), trim(p_to_city), trim(p_pickup_area), trim(p_dropoff_area), p_departure_at, p_total_seats, p_price_per_seat, p_ride_rule, p_notes)
  returning id into v_id;
  return v_id;
end; $$;

create or replace function public.create_booking_request(p_ride_id uuid, p_seats_requested int default 1, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_booking uuid; v_ride public.rides%rowtype; v_left int;
begin
  select * into v_ride from public.rides where id=p_ride_id;
  if not found then raise exception 'Ride not found'; end if;
  if v_ride.status <> 'open' or v_ride.departure_at <= now() then raise exception 'Ride is not available'; end if;
  if v_ride.driver_id = auth.uid() then raise exception 'You cannot book your own ride'; end if;
  perform public.ensure_passenger_allowed(p_ride_id, auth.uid());
  select v_ride.total_seats - coalesce(sum(seats_requested),0) into v_left from public.bookings where ride_id=p_ride_id and status='accepted';
  if coalesce(v_left,0) < 1 then raise exception 'No seats available'; end if;
  insert into public.bookings(ride_id, passenger_id, seats_requested, note)
  values(p_ride_id, auth.uid(), 1, p_note)
  returning id into v_booking;
  insert into public.notifications(user_id,title,body) values(v_ride.driver_id,'New booking request','A passenger requested a seat.');
  return v_booking;
exception when unique_violation then
  raise exception 'You already have a booking request for this ride';
end; $$;

create or replace function public.accept_booking_request(p_booking_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_booking public.bookings%rowtype; v_ride public.rides%rowtype; v_left int;
begin
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  select * into v_ride from public.rides where id=v_booking.ride_id for update;
  if v_ride.driver_id <> auth.uid() and not public.is_admin() then raise exception 'Only ride driver can accept'; end if;
  if v_booking.status <> 'pending' then raise exception 'Booking is not pending'; end if;
  if v_ride.status <> 'open' then raise exception 'Ride is not open'; end if;
  perform public.ensure_passenger_allowed(v_booking.ride_id, v_booking.passenger_id);
  select v_ride.total_seats - coalesce(sum(seats_requested),0) into v_left from public.bookings where ride_id=v_ride.id and status='accepted';
  if coalesce(v_left,0) < v_booking.seats_requested then raise exception 'No seats available'; end if;
  update public.bookings set status='accepted' where id=p_booking_id;
  insert into public.notifications(user_id,title,body) values(v_booking.passenger_id,'Booking accepted','Your seat has been accepted.');
end; $$;

create or replace function public.reject_booking_request(p_booking_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_booking public.bookings%rowtype; v_driver uuid;
begin
  select * into v_booking from public.bookings where id=p_booking_id;
  if not found then raise exception 'Booking not found'; end if;
  select driver_id into v_driver from public.rides where id=v_booking.ride_id;
  if v_driver <> auth.uid() and not public.is_admin() then raise exception 'Only ride driver can reject'; end if;
  update public.bookings set status='rejected', reject_reason=p_reason where id=p_booking_id and status='pending';
end; $$;

create or replace function public.cancel_booking_request(p_booking_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.bookings set status='cancelled', cancel_reason=p_reason
  where id=p_booking_id and passenger_id=auth.uid() and status in ('pending','accepted');
  if not found then raise exception 'Booking cannot be cancelled'; end if;
end; $$;

create or replace function public.close_ride(p_ride_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.rides set status='closed' where id=p_ride_id and (driver_id=auth.uid() or public.is_admin()) and status='open';
  if not found then raise exception 'Ride cannot be closed'; end if;
end; $$;

create or replace function public.get_booking_contact(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v public.bookings_public%rowtype; target_user uuid; res jsonb;
begin
  select * into v from public.bookings_public where id=p_booking_id;
  if not found then raise exception 'Booking not found'; end if;
  if v.status <> 'accepted' then raise exception 'Contact is available only after acceptance'; end if;
  if auth.uid() = v.passenger_id then target_user := v.driver_id;
  elsif auth.uid() = v.driver_id then target_user := v.passenger_id;
  elsif public.is_admin() then target_user := v.passenger_id;
  else raise exception 'Not allowed'; end if;
  select jsonb_build_object('full_name', p.full_name, 'phone', pp.phone, 'emergency_contact', pp.emergency_contact)
  into res from public.profiles p join public.private_profiles pp on pp.user_id=p.id where p.id=target_user;
  return res;
end; $$;

create or replace function public.admin_dashboard()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.is_admin() then jsonb_build_object(
    'total_users',(select count(*) from public.profiles),
    'drivers',(select count(*) from public.profiles where role='driver'),
    'passengers',(select count(*) from public.profiles where role='passenger'),
    'open_rides',(select count(*) from public.rides where status='open'),
    'pending_bookings',(select count(*) from public.bookings where status='pending'),
    'open_reports',(select count(*) from public.reports where status='open')
  ) else '{}'::jsonb end
$$;

-- Make your own account admin after signup/login by replacing the email below and running this line separately:
-- update public.profiles set role='admin' where id = (select id from auth.users where email='YOUR_EMAIL@example.com');

create or replace function public.mark_booking_paid(p_booking_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_driver uuid;
begin
  select r.driver_id into v_driver from public.bookings b join public.rides r on r.id=b.ride_id where b.id=p_booking_id;
  if v_driver <> auth.uid() and not public.is_admin() then raise exception 'Only ride driver can mark payment'; end if;
  update public.bookings set payment_status='paid' where id=p_booking_id and status='accepted';
  if not found then raise exception 'Only accepted bookings can be marked paid'; end if;
end; $$;

create or replace function public.admin_set_user_status(p_user_id uuid, p_status public.user_status)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  update public.profiles set status=p_status where id=p_user_id;
end; $$;

create or replace function public.admin_set_vehicle_verified(p_vehicle_id uuid, p_verified boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  update public.vehicles set is_verified=p_verified where id=p_vehicle_id;
end; $$;
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
