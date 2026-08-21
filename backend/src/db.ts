import mysql, { type Pool } from 'mysql2/promise';

type UserRecord = { id: number; openId: string; name: string; email: string; role: 'user' | 'admin' };
type BookRecord = { id: number; slug: string; status: string; pdfKey: string | null; epubKey: string | null; description?: string };

let pool: Pool | null | undefined;

export function databaseConfigured(): boolean {
  return Boolean(process.env.DATABASE_URL);
}

function getPool(): Pool | null {
  if (pool !== undefined) return pool;
  if (!process.env.DATABASE_URL) {
    pool = null;
    return pool;
  }
  try {
    pool = mysql.createPool({
      uri: process.env.DATABASE_URL,
      connectionLimit: Number(process.env.DB_POOL_SIZE ?? 5),
      waitForConnections: true,
      enableKeepAlive: true,
    });
  } catch (error) {
    console.warn('[Database] Could not create MySQL pool:', error);
    pool = null;
  }
  return pool;
}

async function safe(operation: string, work: (db: Pool) => Promise<void>): Promise<void> {
  const db = getPool();
  if (!db) return;
  try {
    await work(db);
  } catch (error) {
    console.warn(`[Database] ${operation} failed; local fallback remains active:`, error);
  }
}

export async function databaseHealthy(): Promise<boolean> {
  const db = getPool();
  if (!db) return false;
  try {
    await db.query('SELECT 1');
    return true;
  } catch (error) {
    console.warn('[Database] Health check failed:', error);
    return false;
  }
}

export async function persistUser(user: UserRecord): Promise<void> {
  await safe('user upsert', async (db) => {
    await db.execute(
      `INSERT INTO users (id, open_id, name, email, role)
       VALUES (?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE name = VALUES(name), email = VALUES(email), role = VALUES(role), updated_at = CURRENT_TIMESTAMP`,
      [user.id, user.openId, user.name, user.email, user.role],
    );
  });
}

export async function persistBook(book: BookRecord): Promise<void> {
  await safe('book upsert', async (db) => {
    await db.execute(
      `INSERT INTO books (id, slug, status, pdf_key, epub_key)
       VALUES (?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE slug = VALUES(slug), status = VALUES(status), pdf_key = VALUES(pdf_key), epub_key = VALUES(epub_key), updated_at = CURRENT_TIMESTAMP`,
      [book.id, book.slug, book.status, book.pdfKey, book.epubKey],
    );
  });
}

export async function persistEntitlement(input: {
  userId: number;
  platform: 'ios' | 'android' | 'admin';
  productId: string;
  transactionId: string;
  status: 'active' | 'expired' | 'revoked' | 'pending';
  expiresAt: string | null;
}): Promise<void> {
  await safe('entitlement write', async (db) => {
    await db.execute(
      `INSERT INTO entitlements (user_id, platform, product_id, transaction_id, status, expires_at, verified_at)
       VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
       ON DUPLICATE KEY UPDATE status = VALUES(status), expires_at = VALUES(expires_at), verified_at = CURRENT_TIMESTAMP`,
      [input.userId, input.platform, input.productId, input.transactionId, input.status, input.expiresAt],
    );
  });
}

export async function persistProgress(input: { userId: number; bookId: number; pageNumber: number; percent: number }): Promise<void> {
  await safe('progress write', async (db) => {
    await db.execute(
      `INSERT INTO reading_progress (user_id, book_id, page_number, percent)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE page_number = VALUES(page_number), percent = VALUES(percent), updated_at = CURRENT_TIMESTAMP`,
      [input.userId, input.bookId, input.pageNumber, input.percent],
    );
  });
}

export async function persistBookmark(input: { userId: number; bookId: number; pageNumber: number; note: string | null }): Promise<void> {
  await safe('bookmark write', async (db) => {
    await db.execute(
      `INSERT INTO bookmarks (user_id, book_id, page_number, note) VALUES (?, ?, ?, ?)`,
      [input.userId, input.bookId, input.pageNumber, input.note],
    );
  });
}

export async function persistAudit(input: { adminUserId: number; action: string; entityType: string; entityId: string }): Promise<void> {
  await safe('audit write', async (db) => {
    await db.execute(
      `INSERT INTO admin_audit_logs (admin_user_id, action, entity_type, entity_id) VALUES (?, ?, ?, ?)`,
      [input.adminUserId, input.action, input.entityType, input.entityId],
    );
  });
}

export type PersistedUser = UserRecord;
export type PersistedBook = BookRecord & { titleMy?: string; titleEn?: string; author?: string; description?: string; hasPreview?: boolean };
export type PersistedEntitlement = { status: 'active' | 'expired' | 'revoked' | 'pending'; expiresAt: string | null; platform: 'ios' | 'android' | 'admin'; productId: string; transactionId: string };

export async function readUserById(id: number): Promise<PersistedUser | null> {
  const db = getPool();
  if (!db) return null;
  try {
    const [rows] = await db.query('SELECT id, open_id AS openId, name, email, role FROM users WHERE id = ? LIMIT 1', [id]);
    const row = (rows as Array<Record<string, unknown>>)[0];
    if (!row) return null;
    return { id: Number(row.id), openId: String(row.openId), name: String(row.name ?? ''), email: String(row.email ?? ''), role: row.role === 'admin' ? 'admin' : 'user' };
  } catch (error) {
    console.warn('[Database] user read failed; local fallback remains active:', error);
    return null;
  }
}

export async function readPublishedBooks(): Promise<PersistedBook[] | null> {
  const db = getPool();
  if (!db) return null;
  try {
    const [rows] = await db.query(`
      SELECT b.id, b.slug, b.status, b.pdf_key AS pdfKey, b.epub_key AS epubKey,
        MAX(CASE WHEN bt.language = 'my' THEN bt.title END) AS titleMy,
        MAX(CASE WHEN bt.language = 'en' THEN bt.title END) AS titleEn,
        MAX(CASE WHEN bt.language = 'en' THEN bt.author END) AS author,
        MAX(CASE WHEN bt.language = 'en' THEN bt.description END) AS description
      FROM books b LEFT JOIN book_translations bt ON bt.book_id = b.id
      WHERE b.status = 'published'
      GROUP BY b.id, b.slug, b.status, b.pdf_key, b.epub_key
      ORDER BY b.id DESC
    `);
    return (rows as Array<Record<string, unknown>>).map((row) => ({
      id: Number(row.id), slug: String(row.slug), status: String(row.status), pdfKey: row.pdfKey ? String(row.pdfKey) : null, epubKey: row.epubKey ? String(row.epubKey) : null,
      titleMy: row.titleMy ? String(row.titleMy) : undefined, titleEn: row.titleEn ? String(row.titleEn) : undefined, author: row.author ? String(row.author) : undefined, description: row.description ? String(row.description) : undefined, hasPreview: true,
    }));
  } catch (error) {
    console.warn('[Database] book read failed; local fallback remains active:', error);
    return null;
  }
}

export async function readEntitlement(userId: number): Promise<PersistedEntitlement | null> {
  const db = getPool();
  if (!db) return null;
  try {
    const [rows] = await db.query('SELECT status, expires_at AS expiresAt, platform, product_id AS productId, transaction_id AS transactionId FROM entitlements WHERE user_id = ? ORDER BY verified_at DESC, id DESC LIMIT 1', [userId]);
    const row = (rows as Array<Record<string, unknown>>)[0];
    if (!row) return null;
    return { status: row.status as PersistedEntitlement['status'], expiresAt: row.expiresAt ? new Date(String(row.expiresAt)).toISOString() : null, platform: row.platform as PersistedEntitlement['platform'], productId: String(row.productId), transactionId: String(row.transactionId) };
  } catch (error) {
    console.warn('[Database] entitlement read failed; local fallback remains active:', error);
    return null;
  }
}

export async function readProgress(userId: number, bookId: number): Promise<{ pageNumber: number; percent: number } | null> {
  const db = getPool();
  if (!db) return null;
  try {
    const [rows] = await db.query('SELECT page_number AS pageNumber, percent FROM reading_progress WHERE user_id = ? AND book_id = ? LIMIT 1', [userId, bookId]);
    const row = (rows as Array<Record<string, unknown>>)[0];
    return row ? { pageNumber: Number(row.pageNumber), percent: Number(row.percent) } : null;
  } catch (error) {
    console.warn('[Database] progress read failed; local fallback remains active:', error);
    return null;
  }
}

export async function readBookmarks(userId: number, bookId: number): Promise<Array<{ id: string; pageNumber: number; note: string | null }> | null> {
  const db = getPool();
  if (!db) return null;
  try {
    const [rows] = await db.query('SELECT id, page_number AS pageNumber, note FROM bookmarks WHERE user_id = ? AND book_id = ? ORDER BY page_number', [userId, bookId]);
    return (rows as Array<Record<string, unknown>>).map((row) => ({ id: String(row.id), pageNumber: Number(row.pageNumber), note: row.note ? String(row.note) : null }));
  } catch (error) {
    console.warn('[Database] bookmark read failed; local fallback remains active:', error);
    return null;
  }
}

export type NotificationPreferences = { newBooks: boolean; premiumExpiry: boolean; announcements: boolean };

export async function persistNotificationPreferences(userId: number, input: NotificationPreferences): Promise<void> {
  await safe('notification preference write', async (db) => {
    await db.execute(
      `INSERT INTO notification_preferences (user_id, new_books, premium_expiry, announcements)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE new_books = VALUES(new_books), premium_expiry = VALUES(premium_expiry), announcements = VALUES(announcements), updated_at = CURRENT_TIMESTAMP`,
      [userId, input.newBooks ? 1 : 0, input.premiumExpiry ? 1 : 0, input.announcements ? 1 : 0],
    );
  });
}

export async function readNotificationPreferences(userId: number): Promise<NotificationPreferences | null> {
  const db = getPool();
  if (!db) return null;
  try {
    const [rows] = await db.query('SELECT new_books AS newBooks, premium_expiry AS premiumExpiry, announcements FROM notification_preferences WHERE user_id = ? LIMIT 1', [userId]);
    const row = (rows as Array<Record<string, unknown>>)[0];
    return row ? { newBooks: Boolean(row.newBooks), premiumExpiry: Boolean(row.premiumExpiry), announcements: Boolean(row.announcements) } : null;
  } catch (error) {
    console.warn('[Database] notification preference read failed; local fallback remains active:', error);
    return null;
  }
}
