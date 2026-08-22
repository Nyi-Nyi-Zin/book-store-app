import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import mysql from 'mysql2/promise';

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required for migrations');

const schemaPath = path.resolve(process.cwd(), 'src/schema.sql');
const schema = await fs.readFile(schemaPath, 'utf8');
const connection = await mysql.createConnection({ uri: databaseUrl, multipleStatements: true, ssl: databaseUrl.includes('ssl') ? {} : undefined });
try {
  await connection.query(schema);
  console.log(`Applied schema from ${schemaPath}`);
} finally {
  await connection.end();
}
