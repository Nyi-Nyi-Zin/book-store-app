# Production Deployment Runbook

## 1. Required services

Run the API on an always-on HTTPS-capable host and provision a MySQL-compatible database, an S3-compatible private object bucket, an OIDC identity provider, Apple App Store Server API credentials, and Google Play Developer API credentials. The included `backend/Dockerfile` installs Node.js, Python, BeautifulSoup, WeasyPrint, and Burmese-capable fonts so the Admin EPUB-to-PDF worker can run in the same container.

## 2. Secrets and configuration

Create `backend/.env.production` from `.env.example` without committing it. Set `NODE_ENV=production`, `DEMO_MODE=false`, `AUTH_PROVIDER=oidc`, `OIDC_ISSUER_URL`, `OIDC_AUDIENCE`, `CORS_ORIGINS`, a strong `JWT_SECRET`, `DATABASE_URL`, `DATABASE_REQUIRED=true`, `STORAGE_PROVIDER=s3`, the private storage credentials, `BILLING_VERIFY_MODE=production`, Apple credentials, Google Play service-account JSON, legal/support URLs, and webhook verification settings. Keep the object bucket private and do not expose service-account keys to Flutter.

## 3. Database migration

Apply the schema to the empty database before starting the API. From `backend/`, run `DATABASE_URL='mysql://...' pnpm run db:migrate`; the script reads `src/schema.sql` and applies it through the MySQL protocol, which is also the TiDB connection protocol. The schema includes users, books, bilingual translations, conversion jobs, entitlements, reading progress, bookmarks, notification preferences, and audit logs. In a staging database, exercise the full upload, conversion, publish, Premium verification, reader, and account-deletion workflows before production.

## 4. Container startup

For the included Compose template, create a root `.env` containing only `MYSQL_PASSWORD` and `MYSQL_ROOT_PASSWORD`, create `backend/.env.production`, apply the schema, and run:

```bash
docker compose -f docker-compose.production.yml up -d --build
curl -fsS https://api.example.com/api/ready
```

The readiness endpoint must return HTTP 200 with both database and storage checks true. Put the API behind TLS and a reverse proxy or managed HTTPS load balancer. Restrict database access to the API network and restrict object storage to the application service account.

## 5. Store and webhook setup

Create the monthly and yearly Premium products in App Store Connect and Google Play Console using the exact product IDs configured in the API. Register the iOS and Android redirect URIs for OIDC. Configure Apple App Store Server Notifications V2 to call `/api/webhooks/apple` and Google Real-time Developer Notifications/Pub/Sub to call `/api/webhooks/google`. Verify sandbox renewals, expiry, refund/revocation, restore, and duplicate notification behavior before launch.

## 6. Backups and operations

Back up MySQL on a schedule, retain encrypted copies, and perform a restoration drill. Enable container restart policies, centralize structured API logs, monitor `/api/health` and `/api/ready`, alert on 5xx responses, conversion failures, storage failures, entitlement verification failures, and database connectivity loss. Roll back by deploying the previous Git commit and keeping the database migration backward-compatible.

## 7. Release acceptance

The release is not production-approved until the following conditions are true: no demo auth or demo billing path is enabled; database and storage checks are healthy; real OIDC login works on Android and iOS; Premium purchase and restore work in both stores; a non-Premium user cannot download protected PDFs; an Admin can upload EPUB/PDF, observe conversion, and publish; account deletion requests are processed; Privacy, Terms, Support, and copyright URLs are real; Android is signed with the production upload key; and iOS is signed and tested through TestFlight.
