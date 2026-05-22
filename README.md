# RideMate Market Ready Public App

This is a production-oriented public carpool web app package for Netlify + Supabase.
It includes passenger app, driver app, admin portal, Supabase database schema, RLS policies, booking transaction functions, realtime updates, and PWA install support.

## Included modules

### Public user app
- Email/password signup and login
- Passenger/Driver role selection at signup
- Passenger ride search
- Gender/family-safe ride filtering
- Ride details with driver gender and vehicle plate visibility
- Seat booking request
- Passenger bookings list
- Accepted booking contact reveal only after acceptance
- Safety center and report form
- Profile update

### Driver app
- Vehicle add/manage
- Ride post
- Passenger rule: Mixed / Male only / Female only / Family only
- Booking request inbox
- Accept/reject booking
- Seat limit protected by backend transaction
- Close ride

### Admin portal
- Admin dashboard KPIs
- Users list
- Rides list
- Reports list
- Mark report resolved
- Admin role is not available from public signup; assign it manually from SQL

### Backend/Security
- Supabase Auth
- PostgreSQL tables
- Row Level Security on all tables
- Security-definer RPC functions
- Concurrent seat protection using row locks
- Public/private profile separation
- Phone number hidden from normal queries
- Realtime updates

## Step 1 — Create Supabase project

1. Go to Supabase and create a new project.
2. Open **SQL Editor**.
3. Open `supabase/schema.sql` from this folder.
4. Copy the whole file and run it in SQL Editor.

## Step 2 — Configure Auth

Supabase Dashboard → Authentication → Providers:
- Enable Email provider.
- For fastest testing, disable email confirmation.
- For public launch, enable email confirmation.

Optional later:
- Add phone OTP provider.
- Add Google login.

## Step 3 — Create admin user

1. Signup in the app with your own email.
2. In Supabase SQL Editor, run:

```sql
update public.profiles
set role='admin'
where id = (select id from auth.users where email='YOUR_EMAIL@example.com');
```

3. Logout/login again.

## Step 4 — Environment variables

Create `.env` locally or set these variables in Netlify:

```env
VITE_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY
VITE_APP_NAME=RideMate
VITE_SUPPORT_PHONE=03000000000
VITE_ENABLE_DEMO_MODE=false
```

Never add Supabase service-role key to the frontend.

## Step 5 — Run locally

```bash
npm install
npm run dev
```

## Step 6 — Deploy to Netlify

Recommended:
1. Upload this folder to GitHub.
2. Netlify → Add new site → Import from Git.
3. Build command: `npm run build`
4. Publish directory: `dist`
5. Add environment variables in Netlify Site settings → Environment variables.
6. Deploy.

Manual deploy is possible, but Git deploy is better because Netlify injects environment variables during build.

## Step 7 — Final public testing

Use `docs/TESTING-CHECKLIST.md` before sharing the link publicly.

## Production notes

This package is public-deployable as a web app/PWA. For App Store / Play Store native release, wrap the deployed web app using Capacitor or build native apps separately.

Paid third-party modules are intentionally left as variables/integration points:
- SMS OTP needs provider setup in Supabase.
- Live maps need Google Maps/Mapbox account and billing.
- Payments need Easypaisa/JazzCash/Stripe/manual bank integration.

Do not skip legal/safety policies for ride-sharing in your target area.


## Upgrade 02 added

This version includes market-focused commute modules: recurring rides, AM/PM trips, monthly seat fields, saved routes, local Wah Cantt/Islamabad/Rawalpindi route presets, pickup point catalog, and improved admin KPIs.

For an existing deployed Supabase project, run `supabase/upgrade_02_commute_modules.sql` once before redeploying the updated frontend.


## Branding assets added

- `public/branding/logo-horizontal.png` – main RideMate logo
- `public/branding/favicon-32.png` – browser favicon
- `public/branding/apple-touch-icon.png` – mobile bookmark icon
- `public/icons/icon-192.png` and `public/icons/icon-512.png` – updated PWA icons

These are already wired into the app header, auth screen, favicon, and PWA manifest.
