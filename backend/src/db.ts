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
