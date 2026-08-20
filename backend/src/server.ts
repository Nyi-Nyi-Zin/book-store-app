import 'dotenv/config';

import cors from 'cors';
import express, { type NextFunction, type Request, type Response } from 'express';
import { mkdirSync } from 'node:fs';
import { spawn } from 'node:child_process';
import path from 'node:path';
import multer from 'multer';
import { SignJWT, jwtVerify } from 'jose';
import { z } from 'zod';

const app = express();
const port = Number(process.env.PORT ?? 8787);
const storageRoot = path.resolve(process.env.STORAGE_ROOT ?? './storage');
mkdirSync(storageRoot, { recursive: true });

app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '2mb' }));

const users = new Map<string, { id: number; openId: string; name: string; email: string; role: 'user' | 'admin' }>();
const entitlements = new Map<string, { status: 'active' | 'expired' | 'revoked'; expiresAt: string | null }>();
const progress = new Map<string, { pageNumber: number; percent: number }>();
const conversionJobs = new Map<string, ConversionJob>();
let nextUserId = 1;
let nextBookId = 4;

const books = [
  { id: 1, slug: 'midnight-river', status: 'published', titleMy: 'ညသန်းခေါင်က မြစ်', titleEn: 'The Midnight River', author: 'Aye Thiri', description: 'A quiet novel about memory, distance, and the choices that bring people home.', hasPreview: true, pdfKey: null as string | null, epubKey: null as string | null },
  { id: 2, slug: 'rain-letter', status: 'published', titleMy: 'မိုးရေစက်စာ', titleEn: 'Letters in the Rain', author: 'Min Thu', description: 'Two unfinished letters become a journey through Yangon, Mandalay, and old promises.', hasPreview: true, pdfKey: null as string | null, epubKey: null as string | null },
  { id: 3, slug: 'last-lantern', status: 'published', titleMy: 'နောက်ဆုံးမီးအိမ်', titleEn: 'The Last Lantern', author: 'Su Myat', description: 'A warm story of a small bookstore and the people who find it.', hasPreview: true, pdfKey: null as string | null, epubKey: null as string | null },
];

const secret = new TextEncoder().encode(process.env.JWT_SECRET ?? 'local-development-only-change-me');
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

function runEpubConversion(inputPath: string, outputPath: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn('python3', [path.resolve('scripts/epub_to_pdf.py'), inputPath, outputPath], { stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';
    child.stderr.on('data', (chunk: Buffer) => { stderr += chunk.toString(); });
    child.on('error', reject);
    child.on('close', (code) => code === 0 ? resolve() : reject(new Error(stderr || `converter exited with code ${code}`)));
  });
}

app.get('/api/health', (_req, res) => res.json({ status: 'ok', service: 'book-app-api' }));

app.post('/api/auth/demo', async (req, res) => {
  const input = z.object({ role: z.enum(['user', 'admin']).default('user'), name: z.string().min(1).max(80).default('Demo Reader') }).parse(req.body ?? {});
  const openId = `demo-${input.role}`;
  let user = users.get(openId);
  if (!user) {
    user = { id: nextUserId++, openId, name: input.name, email: `${openId}@example.local`, role: input.role };
    users.set(openId, user);
  }
  const token = await issueToken(user);
  res.json({ token, user });
});

app.get('/api/auth/me', auth, (req: AuthRequest, res) => res.json({ user: req.user, isPremium: hasPremium(req.user!.id) }));

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
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
  entitlements.set(String(req.user!.id), { status: 'active', expiresAt });
  res.json({ status: 'active', expiresAt, mode: 'demo' });
});

app.post('/api/premium/verify', auth, (req: AuthRequest, res) => {
  const input = z.object({ platform: z.enum(['ios', 'android']), productId: z.string().min(1), purchaseToken: z.string().min(1) }).parse(req.body);
  res.status(501).json({ error: 'Store verification is not configured', received: { platform: input.platform, productId: input.productId } });
});

app.get('/api/reader/progress/:bookId', auth, (req: AuthRequest, res) => {
  res.json(progress.get(`${req.user!.id}:${req.params.bookId}`) ?? { pageNumber: 1, percent: 0 });
});

app.put('/api/reader/progress/:bookId', auth, (req: AuthRequest, res) => {
  const input = z.object({ pageNumber: z.number().int().min(1), percent: z.number().int().min(0).max(100) }).parse(req.body);
  progress.set(`${req.user!.id}:${req.params.bookId}`, input);
  res.json(input);
});

app.post('/api/admin/books', auth, adminOnly, (req: AuthRequest, res) => {
  const input = z.object({ slug: z.string().regex(/^[a-z0-9-]+$/), titleMy: z.string().min(1), titleEn: z.string().min(1), author: z.string().min(1), description: z.string().optional() }).parse(req.body);
  const book = { id: nextBookId++, status: 'draft', hasPreview: false, pdfKey: null as string | null, epubKey: null as string | null, ...input, description: input.description ?? '' };
  books.push(book);
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
  return res.status(202).json({ book, job });
});

app.get('/api/admin/jobs', auth, adminOnly, (_req, res) => res.json({ jobs: [...conversionJobs.values()] }));

app.use((error: unknown, _req: Request, res: Response, _next: NextFunction) => {
  console.error(error);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(port, () => console.log(`Book App API listening on http://localhost:${port}`));
