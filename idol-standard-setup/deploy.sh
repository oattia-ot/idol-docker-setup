docker network create idol-network

docker compose \
  -f docker-compose.yml \
  -f docker-compose.expose-ports.yml \
  -f docker-compose.bindmount.yml \
  "$@"