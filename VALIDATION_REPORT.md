# Validation Report

The current feature-flow pass completed the following checks successfully.

| Area | Check | Result |
|---|---|---|
| Flutter | `dart format lib test` | Passed |
| Flutter | `flutter analyze` | No issues found |
| Flutter | `flutter test` | 2 widget tests passed |
| Backend | `pnpm run check` | Passed |
| Backend | `pnpm run build` | Passed |
| Premium/access | Free access returns `403`; demo verification returns active entitlement; full access returns `200` | Passed |
| Reader | Progress save and bookmark create/list flow | Passed |
| Admin | PDF upload, publish transition, conversion jobs, and audit log | Passed |
| Conversion | EPUB fixture rendered to a one-page PDF | Passed |
| CI | GitHub Actions workflow structural checks | Passed |
| Security | Production startup rejects missing/weak `JWT_SECRET`; demo routes require explicit development mode | Passed |
| PDF reader | `flutter_pdfview` integration, local cache path, protected byte download, and Premium-only file route | Passed |
| Persistence boundary | Optional MySQL adapter compiles, health metadata exposes DB state, and required-DB guard fails closed | Passed |
| Production config | Demo auth/local storage are rejected in production unless explicitly overridden | Passed |
| Account flows | Subscription status, deletion request, provider sign-up contract, and production auth guard | Passed |

The current demo billing verifier is intentionally limited to local development. Production must replace it with Apple App Store Server API / Notifications V2 and Google Play subscription verification / RTDN handling, then set `DEMO_MODE=false`.
