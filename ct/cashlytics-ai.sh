#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: aaronjoeldev
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/aaronjoeldev/cashlytics-ai

APP="Cashlytics-AI"
var_tags="${var_tags:-finance;ai}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/cashlytics-ai ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "cashlytics-ai" "aaronjoeldev/cashlytics-ai"; then
    msg_info "Stopping ${APP}"
    systemctl stop cashlytics
    msg_ok "Stopped ${APP}"

    msg_info "Backing up Configuration"
    cp /opt/cashlytics-ai/.env /opt/cashlytics-ai.env.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "cashlytics-ai" "aaronjoeldev/cashlytics-ai" "tarball"

    msg_info "Restoring Configuration"
    cp /opt/cashlytics-ai.env.bak /opt/cashlytics-ai/.env
    rm -f /opt/cashlytics-ai.env.bak
    msg_ok "Restored Configuration"

    msg_info "Updating ${APP} to ${RELEASE}"
    cd /opt/cashlytics-ai
    $STD npm ci --omit=dev
    $STD npm run build
    $STD npm run db:push
    echo "${RELEASE}" >/opt/cashlytics-ai_version.txt
    msg_ok "Updated ${APP}"

    msg_info "Starting ${APP}"
    systemctl start cashlytics
    msg_ok "Started ${APP}"

    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
echo -e "${INFO}${YW} Config file: ${CL}${BGN}/opt/cashlytics-ai/.env${CL}"
echo -e "${INFO}${YW} To enable AI features, set ${CL}${BGN}OPENAI_API_KEY${CL}${YW} in the config file${CL}"
echo -e "${INFO}${YW} For multi-user access, set ${CL}${BGN}SINGLE_USER_MODE=false${CL}${YW} in the config file${CL}"
echo -e "${INFO}${YW} After editing: ${CL}${BGN}systemctl restart cashlytics${CL}"
