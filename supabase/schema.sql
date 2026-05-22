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
