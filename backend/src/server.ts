import 'dotenv/config';

import cors from 'cors';
import express, { type NextFunction, type Request, type Response } from 'express';
import { mkdirSync } from 'node:fs';
import { spawn } from 'node:child_process';
import path from 'node:path';
import multer from 'multer';
import { SignJWT, jwtVerify } from 'jose';
import { z } from 'zod';
import { databaseConfigured, databaseHealthy, persistAudit, persistBook, persistBookmark, persistEntitlement, persistProgress, persistUser } from './db.js';

const app = express();
const port = Number(process.env.PORT ?? 8787);
const storageRoot = path.resolve(process.env.STORAGE_ROOT ?? './storage');
const isProduction = process.env.NODE_ENV === 'production';
const demoMode = !isProduction && process.env.DEMO_MODE === 'true';
const databaseRequired = isProduction && process.env.DATABASE_REQUIRED === 'true';
const storageProvider = process.env.STORAGE_PROVIDER ?? 'local';
const authProvider = process.env.AUTH_PROVIDER ?? 'demo';
if (isProduction && authProvider === 'demo') {
  throw new Error('AUTH_PROVIDER must be configured for production');
}
if (isProduction && storageProvider === 'local' && process.env.ALLOW_LOCAL_STORAGE !== 'true') {
  throw new Error('Local storage is disabled in production; configure protected object storage');
}
if (databaseRequired && !process.env.DATABASE_URL) {
  throw new Error('DATABASE_URL is required when DATABASE_REQUIRED=true');
}
const allowedOrigins = new Set((process.env.CORS_ORIGINS ?? '').split(',').map((origin) => origin.trim()).filter(Boolean));
if (isProduction && (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32)) {
  throw new Error('JWT_SECRET must be at least 32 characters in production');
}
mkdirSync(storageRoot, { recursive: true });

app.use(cors({
  credentials: true,
  origin: (origin, callback) => {
    if (!origin || allowedOrigins.size === 0 || allowedOrigins.has(origin)) return callback(null, true);
    return callback(new Error('Origin is not allowed'));
  },
}));
app.use(express.json({ limit: '2mb' }));

const users = new Map<string, { id: number; openId: string; name: string; email: string; role: 'user' | 'admin' }>();
const entitlements = new Map<string, { status: 'active' | 'expired' | 'revoked'; expiresAt: string | null }>();
const progress = new Map<string, { pageNumber: number; percent: number }>();
const bookmarks = new Map<string, Array<{ id: string; pageNumber: number; note: string | null }>>();
const auditLogs: Array<{ id: string; adminUserId: number; action: string; entityType: string; entityId: string; createdAt: string }> = [];
const accountDeletionRequests: Array<{ id: string; userId: number; status: 'received'; createdAt: string }> = [];
const conversionJobs = new Map<string, ConversionJob>();
let nextUserId = 1;
let nextBookId = 4;

const books = [
  { id: 1, slug: 'midnight-river', status: 'published', titleMy: 'ညသန်းခေါင်က မြစ်', titleEn: 'The Midnight River', author: 'Aye Thiri', description: 'A quiet novel about memory, distance, and the choices that bring people home.', hasPreview: true, pdfKey: null as string | null, epubKey: null as string | null },
  { id: 2, slug: 'rain-letter', status: 'published', titleMy: 'မိုးရေစက်စာ', titleEn: 'Letters in the Rain', author: 'Min Thu', description: 'Two unfinished letters become a journey through Yangon, Mandalay, and old promises.', hasPreview: true, pdfKey: null as string | null, epubKey: null as string | null },
  { id: 3, slug: 'last-lantern', status: 'published', titleMy: 'နောက်ဆုံးမီးအိမ်', titleEn: 'The Last Lantern', author: 'Su Myat', description: 'A warm story of a small bookstore and the people who find it.', hasPreview: true, pdfKey: null as string | null, epubKey: null as string | null },
];

const secret = new TextEncoder().encode(process.env.JWT_SECRET ?? 'local-development-only-change-me');
const premiumProducts = new Set(['book_app_premium_monthly', 'book_app_premium_yearly']);
const upload = multer({
  dest: storageRoot,
  limits: { fileSize: Number(process.env.MAX_UPLOAD_MB ?? 100) * 1024 * 1024 },
});

type AuthRequest = Request & { user?: { id: number; openId: string; name: string; email: string; role: 'user' | 'admin' } };
type ConversionJob = { id: string; bookId: number; sourceFilename: string; outputKey: string | null; status: 'queued' | 'processing' | 'completed' | 'failed'; errorMessage?: string };

async function issueToken(user: { id: number; openId: string; name: string; email: string; role: 'user' | 'admin' }) {
  return new SignJWT({ role: user.role, name: user.name, email: user.email })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(String(user.id))
    .setIssuedAt()
    .setExpirationTime('30d')
    .sign(secret);
}

async function auth(req: AuthRequest, res: Response, next: NextFunction) {
  const value = req.header('authorization');
  if (!value?.startsWith('Bearer ')) return res.status(401).json({ error: 'Authentication required' });
  try {
    const { payload } = await jwtVerify(value.slice(7), secret);
    const user = [...users.values()].find((candidate) => candidate.id === Number(payload.sub));
    if (!user) return res.status(401).json({ error: 'Session user not found' });
    req.user = user;
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired session' });
  }
}

function adminOnly(req: AuthRequest, res: Response, next: NextFunction) {
  if (req.user?.role !== 'admin') return res.status(403).json({ error: 'Admin role required' });
  next();
}

function hasPremium(userId: number) {
  const record = entitlements.get(String(userId));
  if (!record || record.status !== 'active') return false;
  return !record.expiresAt || new Date(record.expiresAt).getTime() > Date.now();
}

function recordAudit(adminUserId: number, action: string, entityType: string, entityId: string) {
  auditLogs.unshift({ id: `audit-${Date.now()}`, adminUserId, action, entityType, entityId, createdAt: new Date().toISOString() });
  void persistAudit({ adminUserId, action, entityType, entityId });
}

function runEpubConversion(inputPath: string, outputPath: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn('python3', [path.resolve('scripts/epub_to_pdf.py'), inputPath, outputPath], { stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';
    child.stderr.on('data', (chunk: Buffer) => { stderr += chunk.toString(); });
    child.on('error', reject);
    child.on('close', (code) => code === 0 ? resolve() : reject(new Error(stderr || `converter exited with code ${code}`)));
  });
}

app.get('/api/health', async (_req, res) => res.json({ status: 'ok', service: 'book-app-api', databaseConfigured: databaseConfigured(), databaseHealthy: await databaseHealthy(), storageProvider }));

app.post('/api/auth/demo', async (req, res) => {
  if (!demoMode) return res.status(404).json({ error: 'Demo authentication is disabled' });
  const input = z.object({ role: z.enum(['user', 'admin']).default('user'), name: z.string().min(1).max(80).default('Demo Reader') }).parse(req.body ?? {});
  const openId = `demo-${input.role}`;
  let user = users.get(openId);
  if (!user) {
    user = { id: nextUserId++, openId, name: input.name, email: `${openId}@example.local`, role: input.role };
    users.set(openId, user);
  }
  void persistUser(user);
  const token = await issueToken(user);
  res.json({ token, user });
});

app.get('/api/auth/me', auth, (req: AuthRequest, res) => {
  const isPremium = hasPremium(req.user!.id);
  res.json({ user: req.user, isPremium, entitlement: entitlements.get(String(req.user!.id)) ?? null });
});

app.post('/api/auth/signup', (req, res) => {
  const input = z.object({ name: z.string().min(1).max(80), email: z.string().email(), password: z.string().min(8) }).parse(req.body ?? {});
  res.status(501).json({ error: 'Sign-up is delegated to the configured authentication provider', provider: authProvider, email: input.email });
});

app.post('/api/auth/password-reset', (req, res) => {
  const input = z.object({ email: z.string().email() }).parse(req.body ?? {});
  res.status(501).json({ error: 'Password reset is delegated to the configured authentication provider', provider: authProvider, email: input.email });
});

app.get('/api/account/subscription', auth, (req: AuthRequest, res) => {
  const entitlement = entitlements.get(String(req.user!.id)) ?? null;
  res.json({ isPremium: hasPremium(req.user!.id), entitlement });
});

app.post('/api/account/delete-request', auth, (req: AuthRequest, res) => {
  const request = { id: `delete-${Date.now()}`, userId: req.user!.id, status: 'received' as const, createdAt: new Date().toISOString() };
  accountDeletionRequests.unshift(request);
  res.status(202).json({ requestId: request.id, status: request.status, message: 'Account deletion request received' });
});

app.get('/api/books', (_req, res) => res.json({ books }));

app.get('/api/books/:id', (req, res) => {
  const book = books.find((item) => item.id === Number(req.params.id));
  if (!book || book.status !== 'published') return res.status(404).json({ error: 'Book not found' });
  res.json({ book });
});

app.get('/api/books/:id/access', auth, (req: AuthRequest, res) => {
  const book = books.find((item) => item.id === Number(req.params.id));
  if (!book || book.status !== 'published') return res.status(404).json({ error: 'Book not found' });
  const premium = hasPremium(req.user!.id) || req.user!.role === 'admin';
  if (!premium) return res.status(403).json({ error: 'Premium entitlement required', previewAvailable: book.hasPreview });
  res.json({ access: 'full', bookId: book.id, fileUrl: `/api/books/${book.id}/file`, expiresInSeconds: 900 });
});

app.get('/api/books/:id/file', auth, (req: AuthRequest, res) => {
  const premium = hasPremium(req.user!.id) || req.user!.role === 'admin';
  if (!premium) return res.status(403).json({ error: 'Premium entitlement required' });
  const book = books.find((item) => item.id === Number(req.params.id));
  if (!book?.pdfKey) return res.status(404).json({ error: 'PDF asset is not available yet' });
  res.sendFile(book.pdfKey);
});

app.post('/api/premium/demo-activate', auth, (req: AuthRequest, res) => {
  if (!demoMode) return res.status(404).json({ error: 'Demo Premium activation is disabled' });
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
  entitlements.set(String(req.user!.id), { status: 'active', expiresAt });
  res.json({ status: 'active', expiresAt, mode: 'demo' });
});

app.post('/api/premium/verify', auth, (req: AuthRequest, res) => {
  const input = z.object({ platform: z.enum(['ios', 'android']), productId: z.string().min(1), purchaseToken: z.string().min(1) }).parse(req.body);
  if (!premiumProducts.has(input.productId)) return res.status(400).json({ error: 'Unknown Premium product' });
  if (!demoMode || process.env.BILLING_VERIFY_MODE !== 'demo') {
    return res.status(501).json({ error: 'Store verification is not configured', received: { platform: input.platform, productId: input.productId } });
  }
  const durationDays = input.productId.endsWith('_yearly') ? 365 : 30;
  const expiresAt = new Date(Date.now() + durationDays * 24 * 60 * 60 * 1000).toISOString();
  const entitlement = { status: 'active' as const, expiresAt, platform: input.platform, productId: input.productId, transactionId: `demo-${Date.now()}` };
  entitlements.set(String(req.user!.id), entitlement);
  void persistEntitlement({ userId: req.user!.id, platform: entitlement.platform, productId: entitlement.productId, transactionId: entitlement.transactionId, status: entitlement.status, expiresAt: entitlement.expiresAt });
  res.json({ ...entitlement, mode: 'demo' });
});

app.get('/api/reader/progress/:bookId', auth, (req: AuthRequest, res) => {
  res.json(progress.get(`${req.user!.id}:${req.params.bookId}`) ?? { pageNumber: 1, percent: 0 });
});

app.put('/api/reader/progress/:bookId', auth, (req: AuthRequest, res) => {
  const input = z.object({ pageNumber: z.number().int().min(1), percent: z.number().int().min(0).max(100) }).parse(req.body);
  progress.set(`${req.user!.id}:${req.params.bookId}`, input);
  void persistProgress({ userId: req.user!.id, bookId: Number(req.params.bookId), ...input });
  res.json(input);
});

app.get('/api/reader/bookmarks/:bookId', auth, (req: AuthRequest, res) => {
  res.json({ bookmarks: bookmarks.get(`${req.user!.id}:${req.params.bookId}`) ?? [] });
});

app.post('/api/reader/bookmarks/:bookId', auth, (req: AuthRequest, res) => {
  const input = z.object({ pageNumber: z.number().int().min(1), note: z.string().max(500).nullable().optional() }).parse(req.body);
  const key = `${req.user!.id}:${req.params.bookId}`;
  const items = bookmarks.get(key) ?? [];
  const existing = items.find((item) => item.pageNumber === input.pageNumber);
  if (existing) return res.json({ bookmark: existing, created: false });
  const bookmark = { id: `bookmark-${Date.now()}`, pageNumber: input.pageNumber, note: input.note ?? null };
  items.push(bookmark);
  bookmarks.set(key, items);
  void persistBookmark({ userId: req.user!.id, bookId: Number(req.params.bookId), pageNumber: bookmark.pageNumber, note: bookmark.note });
  res.status(201).json({ bookmark, created: true });
});

app.delete('/api/reader/bookmarks/:bookId/:bookmarkId', auth, (req: AuthRequest, res) => {
  const key = `${req.user!.id}:${req.params.bookId}`;
  const items = bookmarks.get(key) ?? [];
  bookmarks.set(key, items.filter((item) => item.id !== req.params.bookmarkId));
  res.status(204).send();
});

app.post('/api/admin/books', auth, adminOnly, (req: AuthRequest, res) => {
  const input = z.object({ slug: z.string().regex(/^[a-z0-9-]+$/), titleMy: z.string().min(1), titleEn: z.string().min(1), author: z.string().min(1), description: z.string().optional() }).parse(req.body);
  const book = { id: nextBookId++, status: 'draft', hasPreview: false, pdfKey: null as string | null, epubKey: null as string | null, ...input, description: input.description ?? '' };
  books.push(book);
  void persistBook(book);
  recordAudit(req.user!.id, 'book.created', 'book', String(book.id));
  res.status(201).json({ book });
});

app.post('/api/admin/books/:id/upload', auth, adminOnly, upload.single('file'), (req: AuthRequest, res) => {
  if (!req.file) return res.status(400).json({ error: 'file is required' });
  const book = books.find((item) => item.id === Number(req.params.id));
  if (!book) return res.status(404).json({ error: 'Book not found' });
  const isEpub = req.file.originalname.toLowerCase().endsWith('.epub');
  book.status = isEpub ? 'processing' : 'draft';
  if (!isEpub) {
    book.pdfKey = req.file.path;
    const job: ConversionJob = { id: `job-${Date.now()}`, bookId: book.id, sourceFilename: req.file.originalname, outputKey: req.file.path, status: 'completed' };
    conversionJobs.set(job.id, job);
    return res.status(202).json({ book, job });
  }

  book.epubKey = req.file.path;
  const outputPath = path.join(storageRoot, `${book.id}-${Date.now()}.pdf`);
  const job: ConversionJob = { id: `job-${Date.now()}`, bookId: book.id, sourceFilename: req.file.originalname, outputKey: outputPath, status: 'queued' };
  conversionJobs.set(job.id, job);
  void (async () => {
    job.status = 'processing';
    try {
      await runEpubConversion(req.file!.path, outputPath);
      book.pdfKey = outputPath;
      book.status = 'draft';
      job.status = 'completed';
    } catch (error) {
      book.status = 'draft';
      job.status = 'failed';
      job.errorMessage = error instanceof Error ? error.message : 'Conversion failed';
    }
  })();
  void persistBook(book);
  recordAudit(req.user!.id, isEpub ? 'book.epub_uploaded' : 'book.pdf_uploaded', 'book', String(book.id));
  return res.status(202).json({ book, job });
});

app.post('/api/admin/books/:id/publish', auth, adminOnly, (req: AuthRequest, res) => {
  const book = books.find((item) => item.id === Number(req.params.id));
  if (!book) return res.status(404).json({ error: 'Book not found' });
  if (!book.pdfKey) return res.status(409).json({ error: 'A converted PDF is required before publishing' });
  book.status = 'published';
  book.hasPreview = true;
  void persistBook(book);
  recordAudit(req.user!.id, 'book.published', 'book', String(book.id));
  res.json({ book });
});

app.post('/api/admin/books/:id/unpublish', auth, adminOnly, (req: AuthRequest, res) => {
  const book = books.find((item) => item.id === Number(req.params.id));
  if (!book) return res.status(404).json({ error: 'Book not found' });
  book.status = 'draft';
  void persistBook(book);
  recordAudit(req.user!.id, 'book.unpublished', 'book', String(book.id));
  res.json({ book });
});

app.get('/api/admin/jobs', auth, adminOnly, (_req, res) => res.json({ jobs: [...conversionJobs.values()] }));
app.get('/api/admin/audit', auth, adminOnly, (_req, res) => res.json({ logs: auditLogs }));

app.use((error: unknown, _req: Request, res: Response, _next: NextFunction) => {
  if (error instanceof z.ZodError) return res.status(400).json({ error: 'Invalid request', details: error.issues });
  console.error(error);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(port, () => console.log(`Book App API listening on http://localhost:${port}`));
