# Quint local development

## Run the stack

```bash
docker compose up --build
```

- Public site: `http://localhost:4321/it/`
- English site: `http://localhost:4321/en/`
- PocketBase health: `http://localhost:8090/api/quint/health`
- PocketBase backoffice: `http://localhost:8090/_/`

Create the first PocketBase superuser locally in the backoffice. It is intentionally not seeded or committed.

## Quality checks

```bash
cd quint-website-frontend
npm ci
npm run test
npm run build
npx playwright install --with-deps chromium
npm run test:e2e

cd ../quint-website-backend
npm test
```

The frontend coverage configuration enforces 90% minimum lines, functions, branches and statements for tested business modules. Playwright uses accessible roles, labels and `data-testid` only. Visual regression baselines are managed with `npm run test:e2e:update`; inspect the generated report before accepting changes.

## Environment

Copy `quint-website-frontend/.env.example` to a local environment file if the backend runs on a different URL. Development and production indexing are environment-aware: development defaults to `noindex,nofollow`.
