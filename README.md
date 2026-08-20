# Flutter Book App

A cross-platform Flutter reading app for iOS and Android with Myanmar/English localization, light/dark themes, preview-only access for free users, Premium entitlement gating, a protected book API, and an admin EPUB-to-PDF conversion workflow.

## Current implementation

The Flutter client includes the home experience, bilingual catalog, search, book detail pages, sample reader, Premium screen, profile settings, theme/language switching, admin upload UI, conversion-job status UI, and local reading-progress state. The backend includes JWT-based session handling, user/admin role checks, catalog routes, protected full-book access, entitlement routes, reading-progress routes, admin book creation, multipart upload, and an asynchronous EPUB-to-PDF worker using Python, BeautifulSoup, and WeasyPrint.

The client currently contains a local demo mode so the UI can be explored without external credentials. `lib/api_client.dart` and `lib/premium_service.dart` provide the production integration boundary for the backend API and App Store/Google Play billing. Real Apple/Google receipt verification, persistent database wiring, object-storage credentials, and store product configuration must be supplied before production release.

## Repository layout

```text
lib/main.dart                         Flutter app shell and core screens
lib/api_client.dart                   Typed backend API client
lib/premium_service.dart              App Store/Google Play purchase service
backend/src/server.ts                 Express API and authorization middleware
backend/src/schema.ts                 Drizzle database model
backend/src/schema.sql                MySQL provisioning snapshot
backend/scripts/epub_to_pdf.py        EPUB-to-PDF conversion worker
backend/.env.example                  Backend environment template
test/widget_test.dart                 Flutter smoke tests
```

## Run the Flutter client

Install Flutter 3.x and then run:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

To point the client at a local backend, pass the API base URL at build time. Android emulators normally reach the host machine through `10.0.2.2`; a physical device needs the host machine's LAN address.

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8787
```

## Run the backend

```bash
cd backend
cp .env.example .env
pnpm install
pnpm run check
pnpm run build
pnpm start
```

The default API URL is `http://localhost:8787`. Useful endpoints include:

| Endpoint | Purpose | Access |
|---|---|---|
| `GET /api/health` | Health check | Public |
| `POST /api/auth/demo` | Local demo session | Public; replace before production |
| `GET /api/books` | Published catalog | Public |
| `GET /api/books/:id/access` | Full-book access decision | Authenticated + Premium/admin |
| `POST /api/premium/verify` | Store receipt verification boundary | Authenticated |
| `PUT /api/reader/progress/:bookId` | Save reading progress | Authenticated |
| `POST /api/admin/books` | Create a draft book | Admin |
| `POST /api/admin/books/:id/upload` | Upload PDF/EPUB and queue conversion | Admin |
| `GET /api/admin/jobs` | Conversion job status | Admin |

## Database and storage

The repository contains `backend/src/schema.sql` for MySQL provisioning and `backend/src/schema.ts` for Drizzle model alignment. The current local smoke server uses an in-memory fallback to make the demo runnable without credentials. Production must connect the queries to the configured MySQL/TiDB database and move book assets from local disk to protected object storage with expiring signed URLs.

Do not commit `.env`, private keys, App Store service-account files, real book files, or store credentials. Use `.env.example` as the configuration template.

## Premium configuration

Configure matching monthly/yearly products in App Store Connect and Google Play Console using the IDs in `lib/premium_service.dart`. The client sends purchase data to `/api/premium/verify`; the backend must verify Apple and Google receipts server-side before creating an active entitlement. The demo activation endpoint is for local testing only and must be disabled or protected from production use.

## EPUB conversion

The admin upload route accepts `.epub` and `.pdf`. EPUB files are placed in a conversion queue and rendered to PDF by `backend/scripts/epub_to_pdf.py`. The conversion worker removes executable HTML elements and renders document content only. A production deployment should run the conversion worker in a dedicated process or job service, enforce upload limits, validate file signatures, clean temporary files, and use licensed Myanmar fonts where required.

## Validation performed

The following checks pass in the development environment:

```bash
flutter analyze
flutter test
cd backend && pnpm run check && pnpm run build
python3 backend/scripts/epub_to_pdf.py sample.epub sample.pdf
```

The sandbox does not include the Android SDK or Xcode, so Android release builds, iOS builds, TestFlight, and Google Play internal testing still require platform-specific developer environments and signing credentials.

## Before production release

Replace demo authentication with the selected OAuth/email authentication provider. Connect the database and protected object storage. Implement Apple App Store and Google Play receipt verification. Configure privacy policy, terms of use, account deletion, copyright contact, app identifiers, signing certificates, store products, and real licensed book content. Then test on physical iOS and Android devices using TestFlight and Google Play internal testing.

## Official references

- [Apple In-App Purchase](https://developer.apple.com/in-app-purchase/)
- [Google Play Billing subscriptions](https://developer.android.com/google/play/billing/subscriptions)
- [Flutter in_app_purchase](https://pub.dev/packages/in_app_purchase)
