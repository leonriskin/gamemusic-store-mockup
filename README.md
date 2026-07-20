# Riskin Tracks — Game Music Store Mockup

Single-page mockup for an indie game music store: browse tracks, preview demos, cart/checkout, license PDFs, and admin uploads.

## Run locally

```powershell
.\start-server.ps1
```

Open **http://localhost:8765/** (do not open `index.html` directly as a file).

## Project layout

| Path | Purpose |
|------|---------|
| `index.html` | Store UI, cart, checkout, admin, license PDF |
| `start-server.ps1` | Static file server on port 8765 |
| `tracks/catalog.json` | Published track catalog |
| `tracks/<slug>/` | Demo MP3, loop ZIP, pack ZIP, cover art |
| `assets/` | Bundled dependencies (e.g. jsPDF) |
| `scripts/` | Import/sync helpers |

## Mockup notes

- Checkout is simulated (no real Stripe/PayPal).
- Purchases persist in browser `localStorage`.
- **Admin → User monitoring → Clear all mock purchases** resets test orders.
