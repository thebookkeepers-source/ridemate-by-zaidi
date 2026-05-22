# Upgrade 02 — Commute Modules

## What was added
- Daily/weekday/custom recurring rides
- Morning/evening/return trip type
- Monthly seat booking price fields
- Saved routes and route notifications foundation
- Popular Wah Cantt, Islamabad and Rawalpindi route presets
- Public pickup/drop point catalog
- Extra trust fields: phone verified, identity verified, completed rides, cancellations
- Admin dashboard KPIs updated for saved routes and paid bookings

## How to update an already deployed project

1. Upload the updated files to GitHub, replacing the old ones.
2. In Supabase SQL Editor, run:

```text
supabase/upgrade_02_commute_modules.sql
```

3. In Netlify, deploy with:

```text
Deploys → Trigger deploy → Deploy project without cache
```

## Important
Do not upload `package-lock.json`. This package intentionally excludes it because Netlify previously had npm install issues with the generated lock file.
