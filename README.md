# Kevin & Group - Live Loan Dashboard

Single-file static web app (`index.html`) showing a live view of loan/property data across Kevin's entities (Personal, TinTin SuSu SMSF, Sunny Day Carers, Sunrise Disability Accommodation, Edge500, Blue Sky). No build step - it's plain HTML/CSS/JS loading Chart.js and supabase-js from CDN.

## How it's wired up

- **Data source of truth**: Supabase project `odoo` (project ref `yrvyavcunqpjnxrsqbnh`).
- **Odoo -> Supabase sync**: a Supabase Edge Function (`odoo-sync`) pulls journal entries from Odoo's JSON-RPC API for a known set of loan accounts and inserts them into `loan_transactions`. It runs automatically every day at 20:00 via a `pg_cron` job (`odoo-sync-daily`). Nothing manual needed for data to stay current.
- **Auth**: Supabase Auth, email + password. Row Level Security restricts all reads to `authenticated` users only. 5 accounts exist (Kevin, finance, accounts, and two accountants at ansaccounting.net.au).
- **App -> data**: the page calls `supabase.rpc('get_dashboard_data')`, a single Postgres function (see `schema.sql`) that returns one JSON blob with everything the page needs: linked loan accounts, monthly transaction aggregates, properties still awaiting Odoo access, and properties with no loan facility at all.
- **Hosting**: deployed as a static file on Netlify (site: `kevin-group-loan-dashboard`), NOT on Supabase. Supabase's own domain (`*.supabase.co`) forces `Content-Type: text/plain` and a locked-down CSP on everything it serves (Edge Functions and Storage alike) - confirmed by inspecting raw response headers - so it can never render an HTML page. Any future hosting choice must serve real `text/html`.

## Files in this repo

- `index.html` - the entire app (login screen + dashboard). This is the only file Netlify needs to deploy.
- `schema.sql` - read-only reference dump of the actual Supabase table columns and the `get_dashboard_data()` function definition, pulled directly from the live database. Not meant to be run - just context for understanding the data shape `index.html` consumes.

## Fiscal year

The Year/Month filter in the dashboard uses an Australian financial year (July-June), not calendar year. "FY 2024-25" = July 2024 through June 2025.

## Known constraints / things not to "fix"

- The Supabase anon key embedded in `index.html` is meant to be public (RLS + Auth do the real access control) - don't treat it as a secret needing removal.
- 10 properties are still listed under "Properties Awaiting Odoo Access" pending Vibhu granting access to those loan accounts in Odoo. Once granted, their Odoo account IDs need to be added to the `odoo-sync` Edge Function and to `loans.odoo_account_id` for them to start flowing through automatically.
- 2 properties ('7 Shiraz Av, Dapto' and '24 Flamingo Drive Cameron Park') have no loan facility at all by design (land held outright / paid from another account) - they are intentionally excluded from KPIs and charts, shown in a separate table.
