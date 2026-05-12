# Bun deploy example

A worked example that uses Gungnir `ci-toolkit` to script the build and deploy of a tiny Bun project. It is meant to be copied into a real Bun project as a starting point.

## What this example demonstrates

- Sourcing `ci-toolkit` from a Bun project's scripts.
- Validating tools (`bun`, `docker`) and environment variables before doing anything risky.
- Wrapping `bun install` with `ci::retry` (registry calls are network-flaky).
- **Not** retrying `bun test` or `bun build` (failures must surface, not be hidden).
- A dry-run deploy that prints the planned docker commands without contacting a registry.
- A `release` entry point that chains `check → build → deploy`.

## Layout

```
examples/bun-deploy/
├── ci-toolkit           # symlink to ../../ci-toolkit (replace with curl in a real project)
├── package.json         # minimal Bun project
├── src/
│   ├── index.ts
│   └── index.test.ts
├── Dockerfile           # multi-stage Bun image
└── scripts/
    ├── check            # preconditions: tools + env vars
    ├── build            # bun install (retried) → bun test → bun run build
    ├── deploy           # docker build + push (dry-run by default)
    └── release          # chain: check → build → deploy
```

## In a real project

Replace the symlink with a downloaded copy and pin a version:

```bash
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.0/ci-toolkit -o ci-toolkit
chmod +x ci-toolkit
```

## Run locally

From `examples/bun-deploy/`:

```bash
# 1. preconditions only (no env vars yet → expect a deploy-var failure)
RUN_DEPLOY=0 ./scripts/check

# 2. build (installs, tests, bundles)
./scripts/build

# 3. dry-run deploy (no real registry contact)
IMAGE_TAG="$(date +%s)" \
REGISTRY_URL="ghcr.io/example" \
REGISTRY_TOKEN="dummy-token" \
./scripts/deploy

# 4. real deploy (only when you have a registry to push to)
DEPLOY_REAL=1 \
IMAGE_TAG="$(git rev-parse --short HEAD)" \
REGISTRY_URL="ghcr.io/your-org" \
REGISTRY_TOKEN="$YOUR_TOKEN" \
./scripts/deploy

# 5. one-shot pipeline
IMAGE_TAG="$(git rev-parse --short HEAD)" \
REGISTRY_URL="ghcr.io/example" \
REGISTRY_TOKEN="dummy-token" \
./scripts/release
```

## Environment variables

| Variable | Where it is checked | Purpose |
| --- | --- | --- |
| `IMAGE_TAG` | `check` (when `RUN_DEPLOY=1`), `deploy` | The container image tag. |
| `REGISTRY_URL` | `check`, `deploy` | The container registry host. |
| `REGISTRY_TOKEN` | `check`, `deploy` | Auth token; passed to `docker login --password-stdin`, never printed. |
| `REGISTRY_USER` | `deploy` | Optional; defaults to `ci`. |
| `RUN_DEPLOY` | `check` | Set to `0` to skip deploy-related precondition checks. Default `1`. |
| `DEPLOY_REAL` | `deploy` | Set to `1` to perform real `docker login`/`build`/`push`. Default `0` (dry-run). |
| `CI_TOOLKIT_DEBUG` | toolkit logging | Set to `1` to enable `ci::debug` output. |

## Where to adapt for a different deploy target

The toolkit is the same; only `scripts/deploy` changes. Examples:

- **Cloudflare Workers**: replace docker verbs with `bunx wrangler deploy`; keep the env/tool checks and `ci::retry` on the upload step.
- **SSH / rsync**: require `rsync` and `ssh`, validate `DEPLOY_HOST` and `DEPLOY_PATH`, retry the rsync call.
- **S3 static site**: require `aws`, validate `AWS_REGION` and `S3_BUCKET`, retry `aws s3 sync`.

The `check / build / deploy / release` shape stays the same.
