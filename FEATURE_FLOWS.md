# Book App Production Flows and Data Contracts

## Product roles

The app has three runtime states: **Guest**, **Reader**, and **Admin**. A guest can browse published books and read a limited preview. A reader can sign in, maintain reading progress, buy or restore Premium, and read full books while an active entitlement exists. An admin can manage metadata, upload content, monitor conversion, publish/unpublish books, and inspect audit activity.

## Primary journeys

### Guest discovery flow

`Launch → choose Myanmar/English → browse Home → search/filter Catalog → open Book Detail → read Preview → choose Sign in or Premium`.

The catalog is readable without an account. Book Detail must clearly show whether the current user has preview access, full access, or a locked Premium state. A locked action never exposes the protected PDF URL; it routes to the authentication or Premium screen.

### Authentication flow

`Profile → Sign in → enter credentials/provider → backend session → restore session on next launch → role-aware home`.

On an invalid session, the app clears the local token and returns to Guest state. On a valid session, the app loads `/api/auth/me`, which is the source of truth for role and entitlement status. Admin navigation is hidden from non-admin users and protected again by backend authorization.

### Premium flow

`Book Detail/ Premium → choose monthly or yearly plan → native App Store/Google Play purchase → purchase stream → send receipt/token to backend → backend verifies → entitlement active → reload access → open full reader`.

Restore follows `Premium → Restore purchases → native store restore → server verification → entitlement reload`. Expired, revoked, pending, or rejected purchases never unlock the protected file. The app shows a localized error and preserves the user’s catalog and preview access.

### Reader flow

`Book Detail → access decision → preview or full PDF → reader controls → save progress/bookmarks/notes → resume from last page`.

Progress is saved locally immediately and synchronized to the backend when authenticated. If synchronization fails, the reader remains usable and marks the state for retry. Protected files are fetched only after a successful access decision and should be delivered using an expiring URL or authenticated stream.

### Admin flow

`Admin sign in → Admin dashboard → create/edit draft metadata → upload EPUB/PDF → queued conversion job → processing → completed/failed → inspect preview → publish → catalog visible`.

An EPUB upload never blocks the mobile request. The upload returns a job identifier, and the UI polls or subscribes to job status. A failed job exposes a retry action without publishing the incomplete book. Every mutation records admin identity, action, entity, and timestamp.

## API contracts

| Contract | Request | Successful response | Failure behavior |
|---|---|---|---|
| `POST /api/auth/demo` | `{ role, name }` for local development only | `{ token, user }` | Disabled in production |
| `GET /api/auth/me` | Bearer token | `{ user, isPremium }` | `401` clears session |
| `GET /api/books` | Optional language/search/category query | `{ books: [...] }` | Cached fallback and retry UI |
| `GET /api/books/:id/access` | Bearer token | `{ access, fileUrl, expiresInSeconds }` | `403` shows Premium gate |
| `POST /api/premium/verify` | `{ platform, productId, purchaseToken }` | `{ entitlement }` | Purchase remains unfulfilled |
| `GET /api/reader/progress/:bookId` | Bearer token | `{ pageNumber, percent }` | Local progress is retained |
| `PUT /api/reader/progress/:bookId` | `{ pageNumber, percent }` | Saved progress object | Queue retry |
| `POST /api/admin/books` | Bilingual metadata | Draft book object | Field validation error |
| `POST /api/admin/books/:id/upload` | Multipart PDF/EPUB | `{ book, job }` | Upload/conversion error state |
| `GET /api/admin/jobs` | Admin bearer token | `{ jobs: [...] }` | Admin-only `403` |

## Canonical models

```json
{
  "user": {
    "id": 12,
    "openId": "provider-user-id",
    "name": "Reader Name",
    "email": "reader@example.com",
    "role": "user"
  },
  "entitlement": {
    "status": "active",
    "platform": "ios",
    "productId": "book_app_premium_yearly",
    "expiresAt": "2027-08-20T00:00:00.000Z"
  },
  "book": {
    "id": 4,
    "slug": "converted-sample",
    "status": "published",
    "titleMy": "မြန်မာစာအုပ်",
    "titleEn": "English Book",
    "author": "Author",
    "description": "Description",
    "coverUrl": null,
    "hasPreview": true
  },
  "conversionJob": {
    "id": "job-123",
    "bookId": 4,
    "status": "processing",
    "sourceFilename": "book.epub",
    "outputKey": null,
    "errorMessage": null
  }
}
```

## Acceptance rules

The client must not trust a local Premium boolean for protected content. It must use the backend access decision. The backend must not trust a client-provided role, price, or entitlement status. Every full-book response must pass authentication, role/entitlement checks, publication-state checks, and asset-availability checks. All user-visible errors, empty states, and actions must be available in Myanmar and English.
