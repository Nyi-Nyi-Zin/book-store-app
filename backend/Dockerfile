FROM node:22-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    python3 \
    python3-bs4 \
    python3-weasyprint \
    fonts-noto-cjk \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY backend/package.json backend/pnpm-lock.yaml ./
RUN npm install -g corepack@latest \
  && corepack pnpm install --frozen-lockfile
COPY backend ./
RUN corepack pnpm run build

ENV NODE_ENV=production
ENV PORT=8787
EXPOSE 8787
CMD ["node", "dist/server.js"]
