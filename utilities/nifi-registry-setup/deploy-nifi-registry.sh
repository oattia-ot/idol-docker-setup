docker network create nifi-registry-network

docker compose \
  -f docker-compose.nifi-registry.yml \
  "$@"