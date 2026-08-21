# Production Audit Checkpoint

## Current release-candidate capabilities

The repository currently contains a Flutter Android/iOS client with Myanmar/English localization, light/dark themes, catalog and preview gating, role-aware demo session flow, Premium product and restore boundaries, protected PDF download and native PDF rendering, progress and bookmark synchronization, EPUB-to-PDF conversion, Admin upload/publish/audit flows, account settings, subscription status, support/legal placeholders, and Android APK/AAB artifacts.

The backend has explicit production fail-closed checks for demo authentication, weak JWT secrets, local-only storage, and missing required database configuration. It also has an optional MySQL adapter, but the adapter is currently best-effort dual-write only: runtime reads still use in-memory maps, failed database writes do not fail the request, and object storage is not yet implemented.

## Remaining production blockers

| Area | Current state | Production requirement |
|---|---|---|
| Authentication | Demo JWT flow and provider handoff endpoints | Configure and integrate a real auth provider, including sign-up, password reset, email verification, and server-side user lookup |
| Database | Optional MySQL write adapter with in-memory read fallback | Provision MySQL/TiDB, run migrations, implement read-through queries, and make persistence mandatory in production |
| File storage | Local multer paths and local PDF delivery | Use protected S3-compatible storage, store object keys rather than filesystem paths, and generate short-lived authorized downloads |
| Premium | Mobile purchase boundary and demo verifier | Implement Apple App Store Server API/Notifications V2 and Google Play SubscriptionPurchaseV2/RTDN verification with idempotency and reconciliation |
| Secrets | Environment placeholders | Add deployment secret manager values; never commit credentials |
| Operations | Local logs and health endpoint | Add structured logs, error reporting, backups, alerts, and rate limiting |
| Store release | Android build artifacts and iOS workflow | Use production signing keys, App Store/Play Console products, legal URLs, and real-device/TestFlight QA |
| Content | Sample books and conversion fixture | Upload licensed EPUB/PDF content, verify Myanmar font rendering, and complete copyright/takedown policy |

## Execution decision

Continue implementing code-level hardening, adapters, schemas, migrations, validation, and deployment documentation without inventing credentials. Pause only at the point where a real external provider account, private key, production database, storage bucket, or signed store credential is required. Those inputs must be supplied by the owner through a secure deployment configuration rather than placed in source control.
