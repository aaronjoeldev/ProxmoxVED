#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: aaronjoeldev
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/aaronjoeldev/cashlytics-ai

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" setup_nodejs
PG_VERSION="16" setup_postgresql
PG_DB_NAME="cashlytics" PG_DB_USER="cashlytics" setup_postgresql_db

fetch_and_deploy_gh_release "cashlytics-ai" "aaronjoeldev/cashlytics-ai" "tarball"

msg_info "Configuring ${APP}"

# --- Interactive: Single-User Mode ---
if whiptail --title "Cashlytics – User Mode" \
  --yesno "Enable Single-User Mode?\n\nYes = Personal use (no login screen, first signup only)\nNo  = Open registration (family / multi-user)" \
  12 65; then
  SINGLE_USER_MODE="true"
else
  SINGLE_USER_MODE="false"
fi

# --- Interactive: OpenAI API Key (optional) ---
OPENAI_API_KEY=$(whiptail --title "Cashlytics – AI Features (optional)" \
  --inputbox "Enter your OpenAI API Key to enable the AI assistant.\nLeave empty to skip — can be added later in .env" \
  10 70 "" 3>&1 1>&2 2>&3) || OPENAI_API_KEY=""

# --- Generate secrets ---
AUTH_SECRET=$(openssl rand -base64 32)
CRON_SECRET=$(openssl rand -hex 32)

# --- Generate VAPID keys for push notifications ---
VAPID_JSON=$(cd /opt/cashlytics-ai && $STD npx --yes web-push generate-vapid-keys --json 2>/dev/null || echo "{}")
VAPID_PUBLIC_KEY=$(echo "${VAPID_JSON}" | grep -o '"publicKey":"[^"]*"' | cut -d'"' -f4)
VAPID_PRIVATE_KEY=$(echo "${VAPID_JSON}" | grep -o '"privateKey":"[^"]*"' | cut -d'"' -f4)

cat <<EOF >/opt/cashlytics-ai/.env
NODE_ENV=production
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
NEXT_PUBLIC_APP_URL=http://${LOCAL_IP}:3000
AUTH_SECRET=${AUTH_SECRET}
AUTH_TRUST_HOST=true
SINGLE_USER_MODE=${SINGLE_USER_MODE}
OPENAI_API_KEY=${OPENAI_API_KEY}
CRON_SECRET=${CRON_SECRET}
VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}
VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}
VAPID_SUBJECT=mailto:admin@cashlytics.local
NEXT_PUBLIC_DEFAULT_LOCALE=de
NEXT_PUBLIC_DEFAULT_CURRENCY=EUR
EOF

cd /opt/cashlytics-ai
$STD npm ci --omit=dev
$STD npm run build
$STD npm run db:push
echo "${RELEASE}" >/opt/cashlytics-ai_version.txt
msg_ok "Configured ${APP}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/cashlytics.service
[Unit]
Description=Cashlytics Finance App
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/cashlytics-ai
EnvironmentFile=/opt/cashlytics-ai/.env
ExecStart=/usr/bin/node /opt/cashlytics-ai/.next/standalone/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now cashlytics
msg_ok "Created Service"

msg_info "Creating Payment Reminder Timer"
cat <<EOF >/etc/systemd/system/cashlytics-cron.service
[Unit]
Description=Cashlytics Upcoming Payments Reminder
After=cashlytics.service

[Service]
Type=oneshot
ExecStart=/usr/bin/curl -sf \
  -H "Authorization: Bearer ${CRON_SECRET}" \
  http://127.0.0.1:3000/api/cron/upcoming-payments
EOF

cat <<EOF >/etc/systemd/system/cashlytics-cron.timer
[Unit]
Description=Daily Cashlytics Payment Reminder (08:00 UTC)
After=cashlytics.service

[Timer]
OnCalendar=*-*-* 08:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl enable -q --now cashlytics-cron.timer
msg_ok "Created Payment Reminder Timer"

motd_ssh
customize
cleanup_lxc
