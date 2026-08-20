# Premium Provider Decision

The app must keep store verification on the backend rather than trusting a mobile client. Apple’s current guidance identifies the App Store Server API and App Store Server Notifications V2 as the modern server-side path; Apple also states that the legacy `verifyReceipt` endpoint is deprecated. Google’s current publisher APIs expose subscription state through the purchases subscriptions resources, with newer SubscriptionPurchaseV2 methods preferred over the deprecated resource. Google also requires purchase acknowledgement and real-time developer notifications for a robust subscription lifecycle.

| Platform | Backend integration target | Required production inputs |
|---|---|---|
| iOS | Apple App Store Server API plus App Store Server Notifications V2 | App Store Connect API key, issuer ID, key ID, team/bundle identifiers, signed JWS handling, sandbox/production environment logic |
| Android | Google Play Developer API SubscriptionPurchaseV2 plus Real-time Developer Notifications | Google Cloud service account, Play Console access, package name, subscription product/base-plan identifiers, purchase-token acknowledgement |

The current endpoint remains a demo verifier only when `DEMO_MODE=true` and `BILLING_VERIFY_MODE=demo`. Production mode rejects that path and returns a configuration error until provider-backed verification is installed. The mobile client already forwards platform, product ID, and server verification data to the backend; the next provider-specific implementation must verify the transaction, make entitlement writes idempotent using the transaction/order identifier, handle renewal/expiry/refund/revocation notifications, and return the server’s entitlement state.

References:

1. [Apple App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)
2. [Apple: Validating receipts with the App Store](https://developer.apple.com/documentation/storekit/validating-receipts-with-the-app-store)
3. [Google Play Developer API: purchases.subscriptions](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptions)
4. [Google Play subscriptions guide](https://developer.android.com/google/play/billing/subscriptions)
