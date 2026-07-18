# Quint Website

Quint is a static Astro website with a PocketBase backend for the contact form
and backoffice.

## Repository layout

- `quint-website-frontend/` — Astro static website, deployed to Vercel.
- `quint-website-backend/` — PocketBase service, deployed to Railway.
- `docker-compose.yml` — full local stack.

The frontend and backend are Git submodules. Clone this repository with:

```bash
git clone --recurse-submodules https://github.com/micio86dev/quint-website.git
cd quint-website
```

> **SSH access required:** the wrapper repository is cloned over HTTPS, but both
> submodules use GitHub SSH URLs. Configure GitHub SSH authentication before
> running the recursive clone (for example, with `ssh -T git@github.com`), or
> use an SSH agent that already has access to `micio86dev` repositories.

For an existing clone, first synchronise the submodule URLs, then initialise
or update the submodules:

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

## Run locally

### Prerequisites

- Docker Desktop, running, with Docker Compose v2.
- Git, only to clone or update the repository. GitHub SSH authentication is
  also required for the submodules.

Start the complete environment from the repository root:

```bash
./start-local.sh
```

The script validates Docker, the Compose file, and both project directories,
then builds and starts the backend before the frontend. It does not remove
containers, volumes, orphan services, or PocketBase data.

Use background mode when you need the terminal back:

```bash
./start-local.sh --detach
docker compose logs -f
```

Detached mode waits up to 90 seconds for the backend health endpoint and the
frontend HTTP endpoint before returning success. Set
`QUINT_READY_TIMEOUT_SECONDS` only when a slow local build needs more time:

```bash
QUINT_READY_TIMEOUT_SECONDS=180 ./start-local.sh --detach
```

Open these URLs after the services become healthy:

- Website: `http://localhost:4321`
- Backend health check: `http://localhost:8090/api/quint/health`
- PocketBase backoffice: `http://localhost:8090/_/`

On the first backend start, create the PocketBase superuser in the backoffice.
Contacts are stored in the Docker volume `pocketbase_data`; regular
`docker compose down` preserves it. To stop the stack, run:

```bash
docker compose down
```

`docker compose down -v` permanently deletes the local PocketBase data,
including contacts, superusers, and migration history. Use it only for
disposable local data.

### Local environment variables

The Compose stack provides the frontend API URL automatically. For running
Astro directly instead of Docker, copy the example and adjust values if
needed:

```bash
cp quint-website-frontend/.env.example quint-website-frontend/.env
```

| Variable | Local value | Purpose |
| --- | --- | --- |
| `PUBLIC_API_URL` | `http://localhost:8090` | Build-time browser URL for `POST /api/quint/contact`. |
| `SITE_URL` | `http://localhost:4321` | Canonical URLs and sitemap base URL. |

## Deploy

Deploy the backend first, then supply its public URL to the Vercel build. Do
not commit credentials or local `.env` files.

### Pre-deploy test gates

Run these gates from a clean checkout after updating the submodules. They use
the existing project commands and intentionally do not assert an invented
coverage threshold:

```bash
(cd quint-website-frontend && npm ci && npm test && npm run build)
(cd quint-website-backend && npm test)
docker compose config --quiet
```

Do not deploy until every command succeeds. Run the same commands in CI before
merging a release branch when CI is available.

### Railway: PocketBase backend

1. In Railway, create a project and choose **Deploy from GitHub repo**.
2. Select `micio86dev/quint-website-backend` and set the service root directory
   to the repository root. Railway reads `railway.toml` and builds the included
   `Dockerfile`.
3. Add exactly one persistent Railway volume mounted at `/pb/pb_data`. Before
   the first deploy, confirm the mount path and capacity in Railway's service
   settings; it must contain PocketBase data, superusers, contacts, and
   migration history. A deploy without this mount creates an ephemeral database.
4. Add the Railway service variable `PORT=8090`. The image serves PocketBase
   on this fixed port, and Railway uses `PORT` for its health check target.
5. Deploy, then generate a public domain in Railway networking.
6. Confirm `https://<railway-domain>/api/quint/health` returns
   `{"status":"ok"}` and create the first PocketBase superuser at
   `https://<railway-domain>/_/`.
7. In PocketBase **Settings → Application**, set the application URL to the
   final Railway public origin.

Apart from Railway's required `PORT=8090`, the backend has no application
environment variables at present. PocketBase permits cross-origin browser
requests by default, which allows the Vercel contact form to call the custom
public endpoint. If CORS is later restricted, allow every deployed Vercel
origin that serves the form.

#### Railway persistence, backup, and recovery

Before each production release, create a manual backup in the Railway service
**Backups** tab and confirm it is listed with the expected timestamp. Configure
a daily, weekly, or monthly backup schedule appropriate for the recovery
objective, and keep at least one known-good recovery point. Railway volume
backups cover the mounted SQLite data. PocketBase also provides full `pb_data`
backups through **Settings → Backups**; use a separate S3-compatible backup
location when an independent copy is required.

Practice restore in a non-production environment. Railway restores a volume
only within the same project and environment, stages a replacement volume, and
redeploys the service after approval. A restore removes newer Railway backups,
so create a fresh manual backup before approving it. After any restore, verify
the superuser can sign in, migrations are present, and a known record can be
read before reopening the contact form.

For a bad deployment, inspect the failed deployment and logs first. Roll back
code only when the earlier image is compatible with the persisted schema; do
not treat a code rollback as a database rollback. The existing rate-limit
migration intentionally rejects `migrate down`, so prefer a reviewed
fix-forward migration. Restore the volume only for confirmed data recovery,
not as a shortcut for application errors.

### Vercel: Astro frontend

1. In Vercel, import `micio86dev/quint-website-frontend` as a separate
   project. Keep the project root at the repository root; Vercel reads
   `vercel.json`.
2. Set these environment variables for every environment that will receive
   contact-form traffic (Production and Preview as appropriate):

   | Variable | Required value |
   | --- | --- |
   | `PUBLIC_API_URL` | The Railway public origin, for example `https://api.example.com` (no trailing slash). |
   | `SITE_URL` | The final Vercel/custom-site origin, for example `https://www.example.com` (no trailing slash). |

3. Deploy and verify the generated website and its contact form.

`PUBLIC_API_URL` is embedded into the static client bundle at build time. A
change to the Railway domain therefore requires updating the Vercel variable
and redeploying the frontend. `SITE_URL` is also a build-time value used for
canonical links and the sitemap.

### Monitoring and alerting

This repository does not configure any monitoring, alert destinations, or log
retention. Configure and verify them in the provider dashboards before the
first production release.

- **Railway:** In the production environment's **Observability** dashboard,
  add CPU, memory, disk, network, and log widgets for the PocketBase service.
  Review HTTP logs for `@httpStatus:500..599`, `@responseTime:>500`, and the
  contact path. Add disk/CPU/RAM monitors where the plan supports them, then
  configure email, in-app, Slack, or webhook notifications for deployment
  failures and monitor alerts. Verify the destination receives a staging
  deployment event or an approved non-production monitor alert. Railway's
  built-in resource graphs do not replace application-level latency/error
  telemetry; add a third-party APM or synthetic probe if those signals are
  needed.
- **Vercel:** Review deployment/build logs and use **Observability** to inspect
  edge-request errors and traffic. Enable and verify provider alerts only when
  the team's plan includes Observability Plus; send them to an owned email,
  Slack channel, or webhook. Enable Speed Insights only after adding its
  required application integration; it is not enabled by this repository.
  Vercel sees static-site delivery, not the browser's direct request to
  Railway, so it cannot by itself detect a failed contact submission.
- **Independent checks:** Configure an external HTTPS monitor for both
  `https://<vercel-domain>/it/` and
  `https://<railway-domain>/api/quint/health`, with an alert route that is
  tested in a non-production exercise.

### Production checks

The Railway health endpoint returns a static `200` when the PocketBase process
is reachable. It does **not** prove that the SQLite volume is mounted,
migrations are correct, or a contact can be persisted. After both deployments,
verify:

```bash
curl --fail https://<railway-domain>/api/quint/health
curl --fail --head https://<vercel-domain>/it/
```

Submit one contact form in the deployed website and confirm the record is
visible only to a PocketBase superuser in the backoffice. This is the required
durable-write release check: submit an authorized non-PII test record, confirm
it remains visible after a controlled Railway restart or redeploy, then remove
the test record as a superuser. Before using a custom domain, update both
`PUBLIC_API_URL` and `SITE_URL` to their final HTTPS origins, redeploy Vercel,
and repeat every check.
