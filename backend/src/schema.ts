import {
  boolean,
  datetime,
  int,
  json,
  mysqlEnum,
  mysqlTable,
  text,
  timestamp,
  uniqueIndex,
  varchar,
} from 'drizzle-orm/mysql-core';

export const users = mysqlTable('users', {
  id: int('id').autoincrement().primaryKey(),
  openId: varchar('open_id', { length: 128 }).notNull().unique(),
  name: varchar('name', { length: 255 }),
  email: varchar('email', { length: 320 }),
  role: mysqlEnum('role', ['user', 'admin']).notNull().default('user'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().onUpdateNow().notNull(),
});

export const books = mysqlTable('books', {
  id: int('id').autoincrement().primaryKey(),
  slug: varchar('slug', { length: 160 }).notNull().unique(),
  status: mysqlEnum('status', ['draft', 'processing', 'published', 'archived']).notNull().default('draft'),
  coverKey: varchar('cover_key', { length: 512 }),
  pdfKey: varchar('pdf_key', { length: 512 }),
  samplePdfKey: varchar('sample_pdf_key', { length: 512 }),
  epubKey: varchar('epub_key', { length: 512 }),
  fileSize: int('file_size'),
  publishedAt: datetime('published_at'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().onUpdateNow().notNull(),
});

export const bookTranslations = mysqlTable('book_translations', {
  id: int('id').autoincrement().primaryKey(),
  bookId: int('book_id').notNull(),
  language: mysqlEnum('language', ['my', 'en']).notNull(),
  title: varchar('title', { length: 255 }).notNull(),
  author: varchar('author', { length: 255 }).notNull(),
  description: text('description'),
}, (table) => ({
  bookLanguage: uniqueIndex('book_language_idx').on(table.bookId, table.language),
}));

export const conversionJobs = mysqlTable('conversion_jobs', {
  id: int('id').autoincrement().primaryKey(),
  bookId: int('book_id').notNull(),
  sourceKey: varchar('source_key', { length: 512 }).notNull(),
  outputKey: varchar('output_key', { length: 512 }),
  status: mysqlEnum('status', ['queued', 'processing', 'completed', 'failed']).notNull().default('queued'),
  errorMessage: text('error_message'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().onUpdateNow().notNull(),
});

export const entitlements = mysqlTable('entitlements', {
  id: int('id').autoincrement().primaryKey(),
  userId: int('user_id').notNull(),
  platform: mysqlEnum('platform', ['ios', 'android', 'admin']).notNull(),
  productId: varchar('product_id', { length: 255 }).notNull(),
  transactionId: varchar('transaction_id', { length: 512 }).notNull().unique(),
  status: mysqlEnum('status', ['active', 'expired', 'revoked', 'pending']).notNull().default('pending'),
  expiresAt: datetime('expires_at'),
  verifiedAt: datetime('verified_at'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

export const readingProgress = mysqlTable('reading_progress', {
  id: int('id').autoincrement().primaryKey(),
  userId: int('user_id').notNull(),
  bookId: int('book_id').notNull(),
  pageNumber: int('page_number').notNull().default(1),
  percent: int('percent').notNull().default(0),
  updatedAt: timestamp('updated_at').defaultNow().onUpdateNow().notNull(),
}, (table) => ({
  userBook: uniqueIndex('progress_user_book_idx').on(table.userId, table.bookId),
}));

export const bookmarks = mysqlTable('bookmarks', {
  id: int('id').autoincrement().primaryKey(),
  userId: int('user_id').notNull(),
  bookId: int('book_id').notNull(),
  pageNumber: int('page_number').notNull(),
  note: text('note'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

export const adminAuditLogs = mysqlTable('admin_audit_logs', {
  id: int('id').autoincrement().primaryKey(),
  adminUserId: int('admin_user_id').notNull(),
  action: varchar('action', { length: 120 }).notNull(),
  entityType: varchar('entity_type', { length: 120 }).notNull(),
  entityId: varchar('entity_id', { length: 120 }),
  metadata: json('metadata'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

export const schema = { users, books, bookTranslations, conversionJobs, entitlements, readingProgress, bookmarks, adminAuditLogs };

export type User = typeof users.$inferSelect;
export type Book = typeof books.$inferSelect;
export type Entitlement = typeof entitlements.$inferSelect;
