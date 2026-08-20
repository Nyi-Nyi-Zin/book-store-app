# Production Flow Checkpoint

## Current state

The Flutter app has a polished demo shell with Myanmar/English copy, theme switching, local catalog data, preview reader, demo Premium unlock, demo reader/admin roles, local reading progress, and local simulated conversion jobs. The typed API client and purchase service exist as integration boundaries, but the main UI does not yet use them for authentication, catalog loading, Premium entitlement, book access, or admin upload.

The backend currently exposes demo JWT authentication, public catalog routes, protected access decisions, demo entitlement activation, a store-verification boundary, local progress routes, admin book creation/upload, conversion jobs, and local file delivery. It uses in-memory state for the local fallback, while MySQL/Drizzle schema and SQL provisioning files exist but are not wired into all runtime queries.

## Highest-priority production gaps

1. Replace demo login buttons with real sign-in and session restoration.
2. Add a single API-backed AppState repository layer and connect catalog, user session, entitlement, progress, and admin job screens.
3. Add real Premium purchase/restore callbacks that send verified purchase data to the backend.
4. Add protected PDF download/reader loading, preview fallback, bookmark/note persistence, and offline-safe error states.
5. Add admin book metadata CRUD, publish/unpublish, conversion retry, job detail, and audit logging.
6. Wire persistent MySQL/TiDB and protected object storage, then remove or disable demo-only routes in production.
7. Add loading, retry, offline, empty, expired-Premium, unauthorized, and upload-failure states.

## Low-risk assumptions

The first complete production-flow pass keeps the existing responsive Material 3 visual language, uses the current two-language Myanmar/English model, preserves the current three sample books as local fallback data, and uses REST endpoints already present in `backend/src/server.ts`. Real OAuth provider choice, store credentials, database credentials, object-storage credentials, and licensed content remain deployment-time configuration.
