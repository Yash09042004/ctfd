#!/bin/bash

# Define networks and volumes
NETWORK_INTERNAL="internal"
PROJECT_PATH="/home/yash/Desktop/wargames/war/CTFd"  # Replace with your actual project path
VOLUME_DB_DATA="$PROJECT_PATH/.data/mysql"
VOLUME_REDIS_DATA="$PROJECT_PATH/.data/redis"
VOLUME_LOGS="$PROJECT_PATH/.data/CTFd/logs"
VOLUME_UPLOADS="$PROJECT_PATH/.data/CTFd/uploads"

# Function to stop and remove existing containers
cleanup() {
  for container in db cache ctfd nginx; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
      echo "Stopping and removing container: $container"
      docker stop "$container"
      docker rm "$container"
    fi
  done
}

# Cleanup existing containers
cleanup

# Create Docker network if not exists
if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_INTERNAL}$"; then
  docker network create --internal $NETWORK_INTERNAL
fi

# Start the MariaDB service
docker run -d \
  --name db \
  --network $NETWORK_INTERNAL \
  -e MARIADB_ROOT_PASSWORD=ctfd \
  -e MARIADB_USER=ctfd \
  -e MARIADB_PASSWORD=ctfd \
  -e MARIADB_DATABASE=ctfd \
  -e MARIADB_AUTO_UPGRADE=1 \
  -v "$VOLUME_DB_DATA:/var/lib/mysql" \
  mariadb:10.11 \
  mysqld --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci --wait_timeout=28800 --log-warnings=0

# Start the Redis service
docker run -d \
  --name cache \
  --network $NETWORK_INTERNAL \
  -v "$VOLUME_REDIS_DATA:/data" \
  redis:4

# Build and start the CTFd service
docker build -t ctfd_image .

docker run -d \
  --name ctfd \
  --network $NETWORK_INTERNAL \
  --restart always \
  -e SECRET_KEY=yuiopsdfghjkl \
  -e UPLOAD_FOLDER=/var/uploads \
  -e DATABASE_URL=mysql+pymysql://ctfd:ctfd@db/ctfd \
  -e REDIS_URL=redis://cache:6379 \
  -e WORKERS=1 \
  -e LOG_FOLDER=/var/log/CTFd \
  -e ACCESS_LOG=- \
  -e ERROR_LOG=- \
  -e REVERSE_PROXY=true \
  -v "$VOLUME_LOGS:/var/log/CTFd" \
  -v "$VOLUME_UPLOADS:/var/uploads" \
  -v "$PROJECT_PATH:/opt/CTFd:ro" \
  ctfd_image

# Start the Nginx service
docker run -d \
  --name nginx \
  --network $NETWORK_INTERNAL \
  --restart always \
  -v "$PROJECT_PATH/conf/nginx/http.conf:/etc/nginx/nginx.conf:ro" \
  -p 80:80 \
  nginx:stable

echo "All services are up and running."
