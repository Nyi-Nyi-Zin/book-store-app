import { compactVerify, decodeJwt, decodeProtectedHeader, importPKCS8, importSPKI, SignJWT } from 'jose';
import { X509Certificate } from 'node:crypto';

export type BillingPlatform = 'ios' | 'android';
export type VerifiedEntitlement = {
  platform: BillingPlatform;
  productId: string;
  transactionId: string;
  purchaseToken: string;
  status: 'active' | 'expired' | 'revoked' | 'pending';
  expiresAt: string | null;
  source: 'apple' | 'google';
};

const allowedProducts = new Set(['book_app_premium_monthly', 'book_app_premium_yearly']);

function requireValue(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required for production billing verification`);
  return value;
}

function normalizedPrivateKey(value: string): string {
  return value.replace(/\\n/g, '\n');
}

async function appleApiToken(): Promise<string> {
  const key = await importPKCS8(normalizedPrivateKey(requireValue('APPLE_PRIVATE_KEY')), 'ES256');
  return new SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: requireValue('APPLE_KEY_ID'), typ: 'JWT' })
    .setIssuer(requireValue('APPLE_ISSUER_ID'))
    .setAudience('appstoreconnect-v1')
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(key);
}

async function verifyAppleTransaction(signedTransactionInfo: string): Promise<Record<string, unknown>> {
  const header = decodeProtectedHeader(signedTransactionInfo);
  const chain = Array.isArray(header.x5c) ? header.x5c.map(String) : [];
  if (header.alg !== 'ES256' || chain.length < 2) throw new Error('Apple JWS is missing the expected ES256 certificate chain');
  const rootValue = requireValue('APPLE_ROOT_CA_CERT');
  const root = new X509Certificate(rootValue.includes('BEGIN CERTIFICATE') ? rootValue : Buffer.from(rootValue, 'base64'));
  const certificates = chain.map((certificate) => new X509Certificate(Buffer.from(certificate, 'base64')));
  const trustedChain = [...certificates, root];
  const now = Date.now();
  for (let index = 0; index < certificates.length; index += 1) {
    const certificate = certificates[index];
    if (now < Date.parse(certificate.validFrom) || now > Date.parse(certificate.validTo)) throw new Error('Apple JWS certificate is outside its validity period');
    if (!certificate.verify(trustedChain[index + 1].publicKey)) throw new Error('Apple JWS certificate chain verification failed');
  }
  const publicKey = certificates[0].publicKey.export({ type: 'spki', format: 'pem' }).toString();
  const verified = await compactVerify(signedTransactionInfo, await importSPKI(publicKey, 'ES256'), { algorithms: ['ES256'] });
  return JSON.parse(new TextDecoder().decode(verified.payload)) as Record<string, unknown>;
}

async function verifyApple(input: { productId: string; purchaseToken: string }): Promise<VerifiedEntitlement> {
  const bundleId = requireValue('APPLE_BUNDLE_ID');
  if (!allowedProducts.has(input.productId)) throw new Error('Unknown Apple Premium product');
  const environment = process.env.APPLE_ENVIRONMENT === 'sandbox' ? 'sandbox' : 'production';
  const host = environment === 'sandbox' ? 'https://api.storekit-sandbox.itunes.apple.com' : 'https://api.storekit.itunes.apple.com';
  const response = await fetch(`${host}/inApps/v1/transactions/${encodeURIComponent(input.purchaseToken)}`, { headers: { Authorization: `Bearer ${await appleApiToken()}` } });
  if (!response.ok) throw new Error(`Apple transaction lookup failed with status ${response.status}`);
  const body = await response.json() as { signedTransactionInfo?: string };
  if (!body.signedTransactionInfo) throw new Error('Apple response contained no signed transaction information');
  const claims = await verifyAppleTransaction(body.signedTransactionInfo);
  if (claims.bundleId !== bundleId || claims.productId !== input.productId) throw new Error('Apple transaction does not match the configured app or product');
  const transactionId = String(claims.transactionId ?? input.purchaseToken);
  const revocationDate = claims.revocationDate;
  const expiresAt = claims.expiresDate ? new Date(Number(claims.expiresDate)).toISOString() : null;
  return { platform: 'ios', productId: input.productId, transactionId, purchaseToken: input.purchaseToken, status: revocationDate ? 'revoked' : expiresAt && new Date(expiresAt).getTime() <= Date.now() ? 'expired' : 'active', expiresAt, source: 'apple' };
}

async function googleAccessToken(): Promise<string> {
  const account = JSON.parse(requireValue('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON')) as { client_email?: string; private_key?: string; token_uri?: string };
  if (!account.client_email || !account.private_key) throw new Error('Google service account JSON is missing client_email or private_key');
  const assertionKey = await importPKCS8(normalizedPrivateKey(account.private_key), 'RS256');
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/androidpublisher' })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(account.client_email)
    .setAudience(account.token_uri ?? 'https://oauth2.googleapis.com/token')
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(assertionKey);
  const response = await fetch(account.token_uri ?? 'https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }) });
  if (!response.ok) throw new Error(`Google OAuth token request failed with status ${response.status}`);
  const body = await response.json() as { access_token?: string };
  if (!body.access_token) throw new Error('Google OAuth response contained no access token');
  return body.access_token;
}

async function acknowledgeGoogle(packageName: string, productId: string, purchaseToken: string, accessToken: string): Promise<void> {
  const response = await fetch(`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}/purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`, { method: 'POST', headers: { Authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' }, body: '{}' });
  if (!response.ok && response.status !== 409) throw new Error(`Google purchase acknowledgement failed with status ${response.status}`);
}

async function verifyGoogle(input: { productId: string; purchaseToken: string }): Promise<VerifiedEntitlement> {
  const packageName = requireValue('GOOGLE_PLAY_PACKAGE_NAME');
  if (!allowedProducts.has(input.productId)) throw new Error('Unknown Google Premium product');
  const accessToken = await googleAccessToken();
  const response = await fetch(`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(input.purchaseToken)}`, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!response.ok) throw new Error(`Google subscription lookup failed with status ${response.status}`);
  const body = await response.json() as { subscriptionState?: string; lineItems?: Array<{ productId?: string; expiryTime?: string; latestSuccessfulOrderId?: string }> };
  const line = body.lineItems?.find((item) => item.productId === input.productId) ?? body.lineItems?.[0];
  if (!line || line.productId !== input.productId) throw new Error('Google transaction does not match the configured product');
  const expiresAt = line.expiryTime ? new Date(line.expiryTime).toISOString() : null;
  const status = body.subscriptionState === 'SUBSCRIPTION_STATE_ACTIVE' ? 'active' : body.subscriptionState === 'SUBSCRIPTION_STATE_CANCELED' ? 'expired' : 'pending';
  if (status === 'active') await acknowledgeGoogle(packageName, input.productId, input.purchaseToken, accessToken);
  return { platform: 'android', productId: input.productId, transactionId: String(line.latestSuccessfulOrderId ?? input.purchaseToken), purchaseToken: input.purchaseToken, status, expiresAt, source: 'google' };
}

export async function verifyStorePurchase(input: { platform: BillingPlatform; productId: string; purchaseToken: string }): Promise<VerifiedEntitlement> {
  return input.platform === 'ios' ? verifyApple(input) : verifyGoogle(input);
}

export async function verifyAppleNotification(signedPayload: string): Promise<{ notificationType: string | null; transaction: Record<string, unknown> }> {
  const outer = await verifyAppleTransaction(signedPayload);
  const data = outer.data as { signedTransactionInfo?: string } | undefined;
  const transaction = data?.signedTransactionInfo ? await verifyAppleTransaction(data.signedTransactionInfo) : {};
  return { notificationType: typeof outer.notificationType === 'string' ? outer.notificationType : null, transaction };
}

export function parseGoogleNotification(payload: { subscriptionNotification?: { purchaseToken?: string; subscriptionId?: string } }): { purchaseToken: string | null; productId: string | null } {
  return { purchaseToken: payload.subscriptionNotification?.purchaseToken ?? null, productId: payload.subscriptionNotification?.subscriptionId ?? null };
}
