# Database and Storage Deployment Contract

## Database

Provision a MySQL-compatible database such as MySQL 8 or TiDB, apply `backend/src/schema.sql` before starting the API, and set `DATABASE_URL` and `DATABASE_REQUIRED=true`. The backend now has read-side queries for users, published books, entitlements, reading progress, and bookmarks, in addition to persistence writes. When the database is required, a missing or unhealthy persistent source returns a service error instead of silently serving an in-memory catalog.

The database user should have only the permissions required by the schema and application queries. Run schema changes through reviewed migration files in a staging environment before production. Back up the database on a schedule and test restoration before launch.

## Object storage

Use an S3-compatible bucket for EPUB, converted PDF, cover, and preview assets. Configure the following environment values without committing secrets:

```text
STORAGE_PROVIDER=s3
STORAGE_BUCKET=book-app-production
STORAGE_REGION=auto
STORAGE_ENDPOINT=
STORAGE_ACCESS_KEY_ID=
STORAGE_SECRET_ACCESS_KEY=
STORAGE_FORCE_PATH_STYLE=false
ALLOW_LOCAL_STORAGE=false
```

The Admin upload flow stores provider object keys. For S3-compatible storage it uploads the local temporary file and returns a short-lived signed URL only after the authenticated user passes the Premium/Admin access check. Local filesystem delivery remains available only for explicit local development.

## Deployment checks

Before enabling production traffic, verify database connectivity through `/api/health`, upload a licensed PDF and EPUB fixture through the Admin flow, confirm that conversion completes, publish the book, and download it through a Premium account. Confirm that a non-Premium account receives `403`, an expired entitlement cannot obtain a signed URL, and the object bucket denies public access.
