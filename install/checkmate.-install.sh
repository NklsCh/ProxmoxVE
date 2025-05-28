#!/usr/bin/env bash

# Copyright (c) 2021-2025 NklsCh
# Author: NklsCh (NklsCh)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://checkmate.so/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Setup Python3"
$STD apt-get install -y \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv
rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
msg_ok "Setup Python3"

msg_info "Installing runlike"
$STD pip install runlike
msg_ok "Installed runlike"

msg_info "Installing Docker"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
$STD sh <(curl -fsSL https://get.docker.com)
msg_ok "Installed Docker"

# Define Checkmate image names
CHECKMATE_SERVER_IMAGE="ghcr.io/bluewave-labs/checkmate:backend-dist-mono"
CHECKMATE_REDIS_IMAGE="ghcr.io/bluewave-labs/checkmate:redis-dist"
CHECKMATE_MONGO_IMAGE="ghcr.io/bluewave-labs/checkmate:mongo-dist"

CHECKMATE_NETWORK="checkmate-net"
REDIS_CONTAINER_NAME="checkmate-redis"
MONGO_CONTAINER_NAME="checkmate-mongodb"
SERVER_CONTAINER_NAME="checkmate-server"

REDIS_VOLUME_NAME="checkmate_redis_data"
MONGO_VOLUME_NAME="checkmate_mongo_data"

msg_info "Creating Docker network '$CHECKMATE_NETWORK'"
$STD docker network create $CHECKMATE_NETWORK || true # Allow if already exists
msg_ok "Ensured Docker network '$CHECKMATE_NETWORK' exists"

# Install Redis
msg_info "Pulling Checkmate Redis Image ($CHECKMATE_REDIS_IMAGE)"
$STD docker pull $CHECKMATE_REDIS_IMAGE
msg_ok "Pulled Checkmate Redis Image"

msg_info "Installing Checkmate Redis"
$STD docker volume create $REDIS_VOLUME_NAME
$STD docker run -d \
  --name=$REDIS_CONTAINER_NAME \
  --network=$CHECKMATE_NETWORK \
  --restart=always \
  -v $REDIS_VOLUME_NAME:/data \
  $CHECKMATE_REDIS_IMAGE
msg_ok "Installed Checkmate Redis"

# Install MongoDB
msg_info "Pulling Checkmate MongoDB Image ($CHECKMATE_MONGO_IMAGE)"
$STD docker pull $CHECKMATE_MONGO_IMAGE
msg_ok "Pulled Checkmate MongoDB Image"

msg_info "Installing Checkmate MongoDB"
$STD docker volume create $MONGO_VOLUME_NAME
$STD docker run -d \
  --name=$MONGO_CONTAINER_NAME \
  --network=$CHECKMATE_NETWORK \
  --restart=always \
  -v $MONGO_VOLUME_NAME:/data/db \
  $CHECKMATE_MONGO_IMAGE \
  mongod --quiet --replSet rs0 --bind_ip_all
msg_ok "Installed Checkmate MongoDB"

# Install Checkmate Server
msg_info "Pulling Checkmate Server Image ($CHECKMATE_SERVER_IMAGE)"
$STD docker pull $CHECKMATE_SERVER_IMAGE
msg_ok "Pulled Checkmate Server Image"

msg_info "Installing Checkmate Server"
# Note: JWT_SECRET is hardcoded as 'my_secret' based on the provided Docker Compose.
# For production, consider a more secure way to handle secrets.
$STD docker run -d \
  --name=$SERVER_CONTAINER_NAME \
  --network=$CHECKMATE_NETWORK \
  --restart=always \
  -p 52345:52345 \
  -e UPTIME_APP_API_BASE_URL=http://localhost:52345/api/v1 \
  -e UPTIME_APP_CLIENT_HOST=http://localhost \
  -e DB_CONNECTION_STRING=mongodb://${MONGO_CONTAINER_NAME}:27017/uptime_db?replicaSet=rs0 \
  -e REDIS_URL=redis://${REDIS_CONTAINER_NAME}:6379 \
  -e CLIENT_HOST=http://localhost \
  -e JWT_SECRET=my_secret \
  $CHECKMATE_SERVER_IMAGE
msg_ok "Installed Checkmate Server"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
