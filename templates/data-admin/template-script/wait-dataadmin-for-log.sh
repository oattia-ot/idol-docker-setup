#!/bin/bash

exec 1> >(stdbuf -o0 cat)
exec 2> >(stdbuf -o0 cat >&2)

# ── SSL / scheme ───────────────────────────────────────────────────────────────
if [[ "${IDOL_LICENSESERVER_PROTOCOL:-}" == "https" ]]; then
    HTTP_SCHEME=https
    CURL_SSL_OPTS="--insecure"              # self-signed cert support
else
    HTTP_SCHEME=http
    CURL_SSL_OPTS=""
fi

# ── Config ─────────────────────────────────────────────────────────────────────
CONTAINER="${CONTAINER:-${IDOL_DEPLOYMENT_TYPE:-idol-demo}-idol-dataadmin-1}"
PORT="${IDOL_DATA_ADMIN_HTTPS_UI_PORT:-8080}"               # ← dynamic port, defaults to 8080
USERNAME="admin"
MAX_WAIT=300
INTERVAL_FAST=5
INTERVAL_SLOW=15
elapsed=0
COOKIES=$(mktemp)

# ── Determine UI endpoint based on IDOL_UI_NAME ────────────────────────────────
UI_ENDPOINT="login"
if [[ "${IDOL_UI_NAME:-}" == "dataadmin" ]]; then
    UI_ENDPOINT="login?defaultLogin=admin"
fi

HOST="${HTTP_SCHEME}://localhost:${PORT}"
LOGIN_PAGE_URL="$HOST/$UI_ENDPOINT"
SESSION_HEALTH_URL="$HOST/api/user/session-health"

# ── Helpers ────────────────────────────────────────────────────────────────────
log()     { echo "  [$(date '+%H:%M:%S')] $*"; }
success() { echo "  ✅ $*"; }
fail()    {
  echo "  ❌ $*"
  rm -f "$COOKIES" /tmp/idol_health_response.html
  exit 1
}

check_timeout() {
  if [[ $elapsed -ge $MAX_WAIT ]]; then
    log "Last container logs:"
    docker logs "$CONTAINER" --tail=20 2>/dev/null || log "(no container logs available)"
    fail "Timed out after ${MAX_WAIT}s — $1"
  fi
}

sleep_and_tick() {
  local interval=$1
  sleep "$interval"
  elapsed=$((elapsed + interval))
}

# ── Phase 1: Container exists and is running ───────────────────────────────────
echo ""
echo "Phase 1: Waiting for container to start..."
while true; do
  STATUS=$(docker inspect "$CONTAINER" --format='{{.State.Status}}' 2>/dev/null || true)
  if [[ "$STATUS" == "running" ]]; then break; fi
  log "Container status: ${STATUS:-not found}"
  sleep_and_tick $INTERVAL_FAST
  check_timeout "container never reached 'running'"
done
success "Container is running"

# ── Phase 2: Container health check ───────────────────────────────────────────
echo ""
echo "Phase 2: Waiting for container to become healthy..."
while true; do
  HEALTH=$(docker inspect "$CONTAINER" --format='{{.State.Health.Status}}' 2>/dev/null || true)
  if [[ "$HEALTH" == "healthy" ]]; then break; fi
  log "Health status: ${HEALTH:-unknown}"
  sleep_and_tick $INTERVAL_SLOW
  check_timeout "container never became 'healthy'"
done
success "Container is healthy"

# ── Phase 3: Login page returns 200 ───────────────────────────────────────────
echo ""
echo "Phase 3: Waiting for login page (HTTP 200)..."
echo "  Target: $LOGIN_PAGE_URL"
while true; do
  CURL_ERR_FILE=$(mktemp)
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -L \
    $CURL_SSL_OPTS \
    "$LOGIN_PAGE_URL" 2>"$CURL_ERR_FILE" || true)
  CURL_ERR=$(cat "$CURL_ERR_FILE"); rm -f "$CURL_ERR_FILE"

  if [[ -z "$HTTP_STATUS" || "$HTTP_STATUS" == "000" ]]; then
    log "Unable to connect to $LOGIN_PAGE_URL (no response)${CURL_ERR:+ — $CURL_ERR}"
  elif [[ "$HTTP_STATUS" == "200" ]]; then
    break
  else
    log "GET $LOGIN_PAGE_URL → HTTP $HTTP_STATUS (expected 200)"
  fi

  sleep_and_tick $INTERVAL_SLOW
  check_timeout "login page never returned 200"
done
success "Login page is up (HTTP 200)"

# ── Phase 4: Authenticate and verify session (dataadmin only) ──────────────────
if [[ "${IDOL_UI_NAME:-}" == "dataadmin" ]]; then
  echo ""
  echo "Phase 4: Authenticating as '$USERNAME'..."

  log "GET $LOGIN_PAGE_URL (auto-login via defaultLogin param)..."
  HTTP_CODE=$(curl -s -c "$COOKIES" -b "$COOKIES" \
    -o /dev/null \
    -w "%{http_code}" \
    --max-time 10 \
    -L \
    $CURL_SSL_OPTS \
    "$LOGIN_PAGE_URL" || true)
  log "GET /$UI_ENDPOINT → HTTP ${HTTP_CODE:-no response}"

  log "Verifying session via /api/user/session-health ..."
  HEALTH_CODE=$(curl -s -b "$COOKIES" \
    -o /tmp/idol_health_response.html \
    -w "%{http_code}" \
    --max-time 10 \
    $CURL_SSL_OPTS \
    "$SESSION_HEALTH_URL" || true)
  log "GET /api/user/session-health → HTTP ${HEALTH_CODE:-no response}"

  if [[ "$HEALTH_CODE" == "200" ]]; then
    success "Logged in and session verified (HTTP 200)"
  else
    log "Session-health response body:"
    cat /tmp/idol_health_response.html 2>/dev/null || true
    fail "Session verification failed — HTTP ${HEALTH_CODE:-no response}"
  fi
fi

# ── Done ───────────────────────────────────────────────────────────────────────
rm -f "$COOKIES" /tmp/idol_health_response.html
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ IDOL UI is fully ready after ${elapsed}s"
echo "   URL:  $LOGIN_PAGE_URL"
[[ "${IDOL_UI_NAME:-}" == "dataadmin" ]] && echo "   User: $USERNAME"
echo "   Time: $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"