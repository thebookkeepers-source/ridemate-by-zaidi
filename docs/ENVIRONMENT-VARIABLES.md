# Environment Variables

Required:

- `VITE_SUPABASE_URL` — Supabase project URL.
- `VITE_SUPABASE_PUBLISHABLE_KEY` — Supabase publishable/anon key.
- `VITE_APP_NAME` — App display name.
- `VITE_SUPPORT_PHONE` — Support phone number shown in Safety Center.

Optional:

- `VITE_ENABLE_DEMO_MODE` — Keep false for public deployment.
- `VITE_GOOGLE_MAPS_KEY` — Add later when live map UI is implemented.
- `VITE_PAYMENT_PROVIDER` — Add later when payment provider is implemented.

Security:

Do not use `SUPABASE_SERVICE_ROLE_KEY` in frontend or Netlify build variables for this static app.
