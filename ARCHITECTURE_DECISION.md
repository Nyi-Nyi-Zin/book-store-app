# Production Architecture Decision

## What OIDC is for

OpenID Connect (OIDC) is an identity layer built on top of OAuth 2.0. It lets the Flutter app send the user through a trusted Identity Provider (IdP), receive signed tokens, and let the backend verify the user identity without storing the user's password. The standard is designed for web, native mobile, and JavaScript clients and uses standard claims such as `sub`, `email`, and `name`.[1]

In this application, OIDC handles **who the user is**. It does not decide whether the user can read a Premium book. The backend still performs authorization: it verifies the bearer token, maps the provider subject to an internal user, checks the user's role, checks the Premium entitlement, and then permits or denies the protected PDF download. The Flutter client uses AppAuth authorization-code flow with PKCE-ready configuration; the backend validates the issuer, audience, expiry, signature, and JWKS key set.

## Recommended production stack

| Layer | Recommendation | Reason |
|---|---|---|
| Authentication | Auth0 as the OIDC provider | Fits the generic OIDC discovery/JWKS verifier already implemented, supports native-app login and custom claims for the admin role, and avoids handling passwords in this API |
| Application database | TiDB Cloud Serverless or TiDB Cloud Dedicated | MySQL-compatible, so the existing MySQL driver, SQL schema, `ON DUPLICATE KEY UPDATE` writes, and persistence adapter can remain in place; TiDB documents compatibility with common MySQL 5.7/8.0 protocol and syntax.[2] |
| Book/file storage | Private S3-compatible bucket, preferably Cloudflare R2 or AWS S3 | Keeps EPUB/PDF bytes out of the database and supports short-lived signed download URLs |
| Backend | Node.js API container with Python WeasyPrint conversion runtime | Matches the existing TypeScript API and supports Burmese-capable EPUB-to-PDF conversion |
| Mobile | Flutter Android/iOS with AppAuth, secure storage, native PDF viewer, and in-app purchase | Preserves the current cross-platform implementation |

## Why not migrate to Supabase for this version

Supabase combines Postgres, Auth, REST APIs, and Storage in one platform and is a valid alternative.[3] However, the current Book App already has a MySQL/TiDB schema, MySQL connection adapter, SQL migrations, and S3-compatible storage boundary. Moving to Supabase would require a database dialect migration, PostgreSQL-specific authorization policies, a different storage integration, and a different authentication/session integration. That is a larger risk than configuring a standards-based OIDC provider and a MySQL-compatible production database.

## Production identity flow

The mobile app opens the Auth0 authorization endpoint using the registered Android/iOS redirect URI. Auth0 authenticates the user and returns an authorization-code result to the app. The app sends the resulting bearer access token to the Book App API. The API obtains discovery metadata and JWKS keys from the configured issuer, validates the token signature and claims, and uses the verified `sub` claim as the stable external identity. The API then resolves or creates the corresponding internal user record. The admin role must come from a verified namespaced claim configured by an Auth0 Action or equivalent server-side role mapping; it must never be accepted from an unverified client field.

## Production database flow

Create the MySQL-compatible database, apply `backend/src/schema.sql`, set `DATABASE_URL`, and set `DATABASE_REQUIRED=true`. The API reads published books, users, entitlements, progress, bookmarks, and notification preferences from the database. Writes use idempotent keys for entitlements and upserts for progress/preferences. The readiness endpoint must remain unhealthy until the required database is reachable.

## Decision

Use **Auth0 OIDC + TiDB Cloud + private S3-compatible storage** for the first production deployment. Keep all provider details in environment variables and keep the API's provider-neutral interfaces so Auth0, another OIDC provider, or a self-hosted provider can be substituted later without changing Premium authorization or book storage logic.

## References

[1]: https://openid.net/developers/how-connect-works/ "OpenID Foundation: How OpenID Connect Works"
[2]: https://docs.pingcap.com/tidbcloud/mysql-compatibility/ "TiDB Cloud: MySQL Compatibility"
[3]: https://supabase.com/docs/guides/auth "Supabase: Auth"
