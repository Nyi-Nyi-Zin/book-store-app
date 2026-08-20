# Production Configuration Contract

The backend now fails closed for production when demo authentication or local-only storage is selected. Development can use the in-memory and local-disk fallback only when `NODE_ENV` is not `production` and `DEMO_MODE=true` is explicitly set.

| Variable | Development | Production requirement |
|---|---|---|
| `AUTH_PROVIDER` | `demo` | A real provider such as `manus-oauth`; demo auth is rejected |
| `DATABASE_URL` | Optional fallback | Required when `DATABASE_REQUIRED=true` |
| `DATABASE_REQUIRED` | `false` | Set `true` after MySQL/TiDB is provisioned |
| `STORAGE_PROVIDER` | `local` | Configure protected object storage; local storage is rejected by default |
| `ALLOW_LOCAL_STORAGE` | Not needed | Keep `false` for production |
| `BILLING_VERIFY_MODE` | `demo` with `DEMO_MODE=true` | Provider-backed Apple/Google receipt verification |
| `DEMO_MODE` | `true` only for local testing | `false` |
| `JWT_SECRET` | Local fallback permitted | At least 32 characters and stored as a deployment secret |
| `CORS_ORIGINS` | Optional | Explicitly list trusted app/web origins |

The new `backend/src/db.ts` adapter provides safe dual-write hooks for users, books, entitlements, reading progress, bookmarks, and audit logs. If no database is configured, local fallback behavior remains available for development. The adapter intentionally logs and degrades to local state rather than silently presenting persistence as complete.

The protected PDF reader downloads a file only after the backend access check succeeds, caches it under the app documents directory, and renders it with the Android/iOS native PDF viewer. A cached file may be read offline by the same installed app, while all new server access remains entitlement-protected.
