# Database and Storage Deployment Contract

## Database

Provision a MySQL-compatible database such as MySQL 8 or TiDB, apply `backend/src/schema.sql` before starting the API, and set `DATABASE_URL` and `DATABASE_REQUIRED=true`. The backend has read-side queries for users, published books, entitlements, reading progress, and bookmarks, in addition to persistence writes. When the database is required, a missing or unhealthy persistent source returns a service error instead of silently serving an in-memory catalog.

The database user should have only the permissions required by the schema and application queries. Run schema changes through reviewed migration files in a staging environment before production. Back up the database on a schedule and test restoration before launch.

## Cloudflare R2 object storage

Use a **private Cloudflare R2 bucket** for uploaded EPUB files, converted PDFs, book covers, and preview assets. R2 is accessed through its S3-compatible API by the existing backend storage adapter. Configure these values in the backend environment; never commit real credentials:

```text
STORAGE_PROVIDER=s3
STORAGE_BUCKET=book-app-production
STORAGE_REGION=auto
STORAGE_ENDPOINT=https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
STORAGE_ACCESS_KEY_ID=
STORAGE_SECRET_ACCESS_KEY=
STORAGE_FORCE_PATH_STYLE=false
ALLOW_LOCAL_STORAGE=false
```

Create an R2 API token with access limited to this bucket and the permissions needed to read and write objects. Keep its access key and secret only in the backend deployment's secret manager/environment. Never put R2 credentials in Flutter, client-side config, or Git.

The Admin upload flow stores provider object keys. On a book request, the backend checks that the book is published and that the authenticated user has an active Premium entitlement or admin access before issuing a short-lived presigned download URL. Keep the bucket private and do not save permanent public URLs as book file references. The local filesystem remains available only for explicit local development.

R2's current Standard free tier includes 10 GB-month of storage, 1 million Class A requests and 10 million Class B requests per month. Internet egress is free; storage and request usage beyond the included allowance is billed. Check current R2 pricing and usage in Cloudflare before launch.

## Deployment checks

Before enabling production traffic, verify database connectivity through `/api/health`, upload a licensed PDF and EPUB fixture through the Admin flow, confirm that conversion completes, publish the book, and download it through a Premium account. Confirm that a non-Premium account receives `403`, an expired entitlement cannot obtain a signed URL, and the R2 bucket denies public access.
