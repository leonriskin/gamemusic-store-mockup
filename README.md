# Riskin Tracks — Game Music Store Mockup

Single-page mockup for an indie game music store: browse tracks, preview demos, cart/checkout, license PDFs, and admin uploads.

## Run locally

**Static site only** (browse, audio, admin — no contact form email):

```powershell
.\start-server.ps1
# or: npm run dev:static
```

Open **http://localhost:8765/** (do not open `index.html` directly as a file).

**Contact form + Netlify Functions** (Resend email, PayPal checkout):

```powershell
copy .env.example .env   # first time only — fill RESEND_API_KEY, PAYPAL_* for checkout
npm install
npm run dev
```

Open **http://localhost:8888/** — contact form needs `RESEND_API_KEY`; PayPal checkout needs `PAYPAL_CLIENT_ID` + `PAYPAL_CLIENT_SECRET` (sandbox). Without PayPal credentials, use **Card (mock)** at checkout.

## Project layout

| Path | Purpose |
|------|---------|
| `index.html` | Store UI, cart, checkout, admin, license PDF |
| `netlify/functions/` | Serverless: contact, waitlist, PayPal/Stripe checkout |
| `start-server.ps1` | Static file server on port 8765 |
| `tracks/catalog.json` | Published track catalog |
| `tracks/<slug>/` | Demo MP3, loop ZIP, pack ZIP, cover art |
| `assets/` | Bundled dependencies (e.g. jsPDF) |
| `scripts/` | Import/sync helpers |

## Mockup notes

- **PayPal** is the primary checkout path (sandbox by default). Card checkout remains a local mock for testing without credentials.
- Purchases persist in browser `localStorage`.
- **Admin → User monitoring → Clear all mock purchases** resets test orders.

## PayPal checkout

Checkout uses [PayPal Smart Payment Buttons](https://developer.paypal.com/docs/checkout/) with server-side order creation and capture via Netlify Functions.

| Variable | Purpose |
|----------|---------|
| `PAYPAL_CLIENT_ID` | REST app Client ID (safe to expose to the browser via `paypal-config`) |
| `PAYPAL_CLIENT_SECRET` | REST app secret — **Netlify/server only**, never in frontend code |
| `PAYPAL_MODE` | `sandbox` (default) or `live` |

**PayPal Developer Dashboard setup**

1. Sign in at [developer.paypal.com](https://developer.paypal.com/).
2. **Apps & Credentials** → create a **REST API app** (Business account recommended for live sales).
3. Copy **Sandbox** Client ID and Secret for testing.
4. Add them to `.env` locally and Netlify environment variables for production deploys.
5. For live sales later: switch the app to **Live** credentials and set `PAYPAL_MODE=live`.

**Local dev**

```powershell
copy .env.example .env   # add PAYPAL_* vars
npm run dev              # http://localhost:8888 — required for PayPal functions
```

Without PayPal credentials, checkout shows a setup notice; use **Card** (mock until Stripe keys are set) to test the download flow.

**Sandbox test**

1. Use PayPal sandbox **Personal** and **Business** test accounts from Developer Dashboard → **Testing Tools → Sandbox accounts**.
2. Add a track to cart → checkout → fill licensee name and email → click the PayPal button.
3. Log in with a sandbox buyer account and approve payment.
4. On success you should land on the download page with `downloadPurchaseZip` and license PDF available.

**Netlify deploy:** Site settings → Environment variables → add `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET`, and `PAYPAL_MODE=sandbox`.

## Stripe card checkout

Checkout **Card** tab uses [Stripe Payment Element](https://docs.stripe.com/payments/payment-element) with a PaymentIntent created on the server.

| Variable | Purpose |
|----------|---------|
| `STRIPE_PUBLISHABLE_KEY` | `pk_test_…` or `pk_live_…` — exposed via `stripe-config` |
| `STRIPE_SECRET_KEY` | `sk_test_…` or `sk_live_…` — **Netlify/server only** |

1. Stripe Dashboard → **Developers → API keys** (start in **Test mode**).
2. Add both keys to local `.env` and to Netlify environment variables.
3. `npm run dev` → http://localhost:8888 → Card tab → test card `4242 4242 4242 4242`, any future expiry, any CVC.
4. On success: same download / license flow as PayPal.

**Still TODO:** PayPal/Stripe webhooks, live-mode cutover, server-side purchase persistence / email receipts.

## Contact form (Resend)

The contact form posts to `/.netlify/functions/contact`, which sends mail via [Resend](https://resend.com).

| Variable | Purpose |
|----------|---------|
| `RESEND_API_KEY` | API key from Resend dashboard |
| `CONTACT_TO` | Inbox that receives submissions (default: `ionicsmusic2017@gmail.com`) |
| `RESEND_FROM` | Sender shown in email (default: `Riskin Tracks <onboarding@resend.dev>`) |

**Resend sender setup**

- **Testing:** `onboarding@resend.dev` works immediately but only delivers to the email you used to sign up for Resend.
- **Production:** Add and verify **riskintracks.com** in Resend → Domains, then set e.g. `RESEND_FROM=Riskin Tracks <contact@riskintracks.com>` in Netlify environment variables.

**Netlify deploy:** Site settings → Environment variables → add `RESEND_API_KEY`, `CONTACT_TO`, and (after domain verification) `RESEND_FROM`.

## Waitlist + newsletter (local)

Under-construction page collects emails and sends a Founders welcome via Resend.

| Variable | Purpose |
|----------|---------|
| `RESEND_API_KEY` | Same key as contact form |
| `WAITLIST_FROM` | Optional sender override (falls back to `RESEND_FROM`) |
| `CONTACT_TO` | Optional BCC so you see new signups |
| `WAITLIST_AUDIENCE_ID` | Optional Resend Audience / Segment id |
| `WAITLIST_DISCOUNT_CODE` | Code named in welcome email (default `FOUNDERS25`) |

**Preview locally (no production deploy):**

```bash
npm run dev
```

- Construction + form: http://localhost:8888/under-construction.html  
- Process storyboard: http://localhost:8888/waitlist-mockup.html  
- Function: `POST /.netlify/functions/waitlist`
- Admin → Newsletter: http://localhost:8888/ → Admin → Newsletter (compose / preview / schedule / send / history)

**Newsletter admin (local):**

1. `npm run dev` → open Admin → Newsletter.
2. Check one or more sections (Announcement, New tracks, Discount). Preview uses the same HTML builder as send (order: announcement → tracks → discount).
3. **Refresh** rebuilds the preview from the server; **Expand** / **Back** toggle full-preview vs compose.
4. **Send to all waitlist subscribers** broadcasts via Resend to everyone in `WAITLIST_AUDIENCE_ID`. Optional test email sends only to that address.
5. **Schedule**: pick a local date/time (timezone shown under the field) → Schedule. Queue is stored in `data/newsletter-schedule.json` (+ localStorage). While the Newsletter page is open, a ~20s poll fires due jobs through `newsletter-send`.

**Production note:** the local poll only runs while Admin Newsletter is open. Reliable offline delivery needs a Netlify scheduled function / external cron that reads the schedule queue and POSTs to `newsletter-send` (with `ADMIN_NEWSLETTER_SECRET`). Not wired by default.

Copy waitlist vars from `.env.example` into `.env`, then restart `npm run dev`. Without `WAITLIST_AUDIENCE_ID`, welcome email still sends; list storage is best-effort. Newsletter broadcast send needs `WAITLIST_AUDIENCE_ID`; preview + single `testEmail` work without it. Newsletter APIs only run under Netlify Dev (`NETLIFY_DEV=true`) or with `ADMIN_NEWSLETTER_SECRET` + `X-Admin-Newsletter-Secret`.
