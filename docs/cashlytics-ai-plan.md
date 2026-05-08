# Cashlytics-AI – ProxmoxVED Contribution Plan

> **Branch:** `feat/cashlytics-ai`  
> **Author:** aaronjoeldev  
> **Date:** 2026-05-08  
> **Status:** In Progress

---

## 1. What We Are Building

A native LXC install script for [Cashlytics](https://github.com/aaronjoeldev/cashlytics-ai) — a self-hosted personal finance application with an AI assistant, built on Next.js 16 and PostgreSQL 16.

### Files to Create

| File | Purpose |
|---|---|
| `ct/cashlytics-ai.sh` | Container definition + update logic (runs on Proxmox host) |
| `install/cashlytics-ai-install.sh` | Application installation (runs inside LXC) |
| `json/cashlytics-ai.json` | Website metadata (name, logo, tags, resources) |

---

## 2. Application Analysis

### Tech Stack

| Component | Detail |
|---|---|
| Runtime | Node.js 22 |
| Framework | Next.js 16 (App Router, `output: standalone`) |
| Database | PostgreSQL 16 (mandatory) |
| ORM | Drizzle ORM → migration via `npm run db:push` |
| Auth | Auth.js → `AUTH_SECRET` (random base64) |
| Email | Nodemailer + React Email (optional SMTP) |
| AI | Vercel AI SDK + OpenAI (optional `OPENAI_API_KEY`) |
| Push | Web Push API (VAPID keys, optional) |
| Cron | Alpine curl cronjob → hits `/api/cron/upcoming-payments` |
| Port | 3000 |
| Releases | GitHub tags `v0.1.0` → `v0.7.0` (latest: v0.7.0, 2026-05-06) |

### GitHub Releases
The repo publishes stable releases — `fetch_and_deploy_gh_release` can be used directly. Update detection via GitHub API `releases/latest`.

### Environment Variables (Required vs Optional)

| Variable | Required | Default | Notes |
|---|---|---|---|
| `DATABASE_URL` | Yes | auto-generated | Points to local PG |
| `AUTH_SECRET` | Yes | auto-generated | `openssl rand -base64 32` |
| `AUTH_TRUST_HOST` | Yes | `true` | Required behind reverse proxy / IP access |
| `NEXT_PUBLIC_APP_URL` | Yes | `http://${LOCAL_IP}:3000` | |
| `SINGLE_USER_MODE` | Yes | `true` | **Prompt during install** |
| `OPENAI_API_KEY` | No | empty | **Prompt during install** |
| `CRON_SECRET` | No | auto-generated | Secures cron endpoint |
| `VAPID_*` | No | auto-generated | Push notifications |
| `SMTP_*` | No | empty | Post-install .env edit |

### Key Differences from Blinko (closest existing script)

| Aspect | Blinko | Cashlytics-AI |
|---|---|---|
| Runtime | Bun | Node.js (npm) |
| ORM | Prisma | **Drizzle** (`npm run db:push`) |
| Migration cmd | `bun run prisma:migrate:deploy` | **`npm run db:push`** |
| Cron | None | systemd timer → curl |
| Build | `bun run build:web` | `npm run build` |

---

## 3. Design Decisions

### A. Installation Approach: Native (not Docker-in-LXC)

Native install (clone → build → systemd) was chosen over Docker-in-LXC for the following reasons:
- Matches the style of every existing script in ProxmoxVED
- Smaller container footprint (~8 GB vs ~15 GB)
- No privileged container required
- Cleaner update mechanism
- Docker-in-LXC PRs are consistently rejected by maintainers

### B. Two Interactive Prompts During Install

Only two decisions cannot be safely defaulted and must be made at install time:

1. **Single-User Mode** — fundamentally changes registration behavior
2. **OpenAI API Key** — optional, but must be set before first build (baked into env)

All other variables (SMTP, locale, currency, notification schedule) are written to `.env` with sensible defaults and documented in the post-install message.

### C. Cron Service: systemd Timer

The Docker deployment includes a separate Alpine container that calls `/api/cron/upcoming-payments` daily. The native equivalent is a systemd oneshot service + timer:

- `cashlytics-cron.service` — runs `curl` with the Bearer token
- `cashlytics-cron.timer` — fires at 08:00 UTC daily

This replicates the Docker cron container behavior with zero extra runtime.

### D. VAPID Key Generation

Push notification keys are generated at install time via:
```bash
npx --yes web-push generate-vapid-keys --json
```
This runs once, keys are written to `.env`, and the container never needs npm/web-push again.

---

## 4. Resource Allocation

| Resource | Value | Reasoning |
|---|---|---|
| CPU | 2 | Build step is CPU-intensive; 1 core causes timeout |
| RAM | 2048 MB | Next.js build needs ~1.5 GB peak, runtime ~400 MB |
| Disk | 8 GB | App + node_modules + PG data fits comfortably |
| OS | Debian 13 | Community standard for Node.js apps |
| Unprivileged | 1 (yes) | No special privileges needed |

---

## 5. Update Logic

```
stop cashlytics.service
backup /opt/cashlytics-ai/.env → /opt/cashlytics-ai.env.bak
fetch_and_deploy_gh_release (new tarball overwrites /opt/cashlytics-ai/)
restore .env from backup
npm ci --omit=dev
npm run build
npm run db:push          ← Drizzle: additive only, safe for upgrades
start cashlytics.service
echo version > /opt/cashlytics-ai_version.txt
```

---

## 6. Post-Install Message

```
Cashlytics setup has been successfully initialized!
Access: http://<IP>:3000

Config file: /opt/cashlytics-ai/.env
  → Set SMTP_* for password reset emails
  → Set NEXT_PUBLIC_DEFAULT_LOCALE (de|en)
  → Set NEXT_PUBLIC_DEFAULT_CURRENCY (EUR|USD|GBP|CHF)
  → Set NOTIFICATION_SCHEDULE for cron timing

Restart after changes: systemctl restart cashlytics
```

---

## 7. Pre-PR Checklist

- [ ] `bash -n ct/cashlytics-ai.sh` — no syntax errors
- [ ] `bash -n install/cashlytics-ai-install.sh` — no syntax errors
- [ ] `shellcheck ct/cashlytics-ai.sh` — no critical warnings
- [ ] `shellcheck install/cashlytics-ai-install.sh` — no critical warnings
- [ ] Tested on real Proxmox instance (Debian 13 LXC)
- [ ] Container creation successful
- [ ] App accessible at `http://<IP>:3000`
- [ ] Single-user mode prompt works (yes/no)
- [ ] OpenAI key prompt works (empty = skip)
- [ ] Update function detects new GitHub releases
- [ ] `.env` backed up and restored during update
- [ ] systemd timer fires correctly
- [ ] No temp files after install

---

## 8. PR Template (ready to copy)

```markdown
## Description
Adds Cashlytics, a self-hosted personal finance app with optional AI assistant.
Built on Next.js 16 + PostgreSQL 16 + Drizzle ORM.

## Type of Change
- [x] New application (ct/cashlytics-ai.sh + install/cashlytics-ai-install.sh)

## Testing
- [ ] Tested on Proxmox VE 8.x
- [ ] Container creation successful
- [ ] Application installation successful
- [ ] Application is accessible at http://IP:3000
- [ ] Update function works
- [ ] No temporary files left after installation

## Application Details
- **App Name**: Cashlytics
- **Source**: https://github.com/aaronjoeldev/cashlytics-ai
- **Default OS**: Debian 13
- **Recommended Resources**: 2 CPU, 2 GB RAM, 8 GB Disk
- **Tags**: finance;ai
- **Access URL**: http://IP:3000
```
