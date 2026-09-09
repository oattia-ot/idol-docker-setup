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
DEPLOY_PREFIX="${IDOL_DEPLOYMENT_TYPE:-idol-demo}"
CONTAINER="${CONTAINER:-${DEPLOY_PREFIX}-idol-dataadmin-1}"
ANSWERSERVER_CONTAINER="${ANSWERSERVER_CONTAINER:-${DEPLOY_PREFIX}-idol-answerserver-1}"
ANSWERSERVER_ACI_SCHEME="${ANSWERSERVER_ACI_SCHEME:-${HTTP_SCHEME}}"
ANSWERSERVER_ACI_HOST="${ANSWERSERVER_ACI_HOST:-${EXTRA_IP_SANS_ENV:-127.0.0.1}}"
# Host-mapped ACI port. Override with ANSWERSERVER_ACI_PORT or a subtype port env var.
ANSWERSERVER_ACI_PORT="${ANSWERSERVER_ACI_PORT:-${PORT_DATA_ADMIN_ANSWERSERVER:-${PORT_BASIC_IDOL_ANSWERSERVER:-}}}"
ANSWERSERVER_ACI_INTERNAL_PORT="${ANSWERSERVER_ACI_INTERNAL_PORT:-12000}"
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
    if [[ -n "${1:-}" && "$1" == answerserver ]]; then
      log "Last Answer Server logs:"
      docker logs "$ANSWERSERVER_CONTAINER" --tail=30 2>/dev/null || log "(no answerserver logs available)"
      fail "Timed out after ${MAX_WAIT}s — ${2:-answerserver not ready}"
    fi
    fail "Timed out after ${MAX_WAIT}s — $1"
  fi
}

sleep_and_tick() {
  local interval=$1
  sleep "$interval"
  elapsed=$((elapsed + interval))
}

resolve_answerserver_container() {
  if docker inspect "$ANSWERSERVER_CONTAINER" >/dev/null 2>&1; then
    return 0
  fi
  local found
  found=$(docker ps -a --format '{{.Names}}' | grep -iE 'idol-answerserver' | head -n1 || true)
  if [[ -n "$found" ]]; then
    ANSWERSERVER_CONTAINER="$found"
    log "Using discovered Answer Server container: $ANSWERSERVER_CONTAINER"
    return 0
  fi
  return 1
}

published_answerserver_port() {
  local mapped=""
  mapped=$(docker port "$ANSWERSERVER_CONTAINER" "${ANSWERSERVER_ACI_INTERNAL_PORT}/tcp" 2>/dev/null \
    | head -n1 | awk -F: '{print $NF}' | tr -d '\r' || true)
  if [[ "$mapped" =~ ^[0-9]+$ ]]; then
    echo "$mapped"
    return 0
  fi
  mapped=$(docker inspect -f "{{(index (index .NetworkSettings.Ports \"${ANSWERSERVER_ACI_INTERNAL_PORT}/tcp\") 0).HostPort}}" \
    "$ANSWERSERVER_CONTAINER" 2>/dev/null || true)
  if [[ "$mapped" =~ ^[0-9]+$ ]]; then
    echo "$mapped"
    return 0
  fi
  return 1
}

resolve_answerserver_aci_url() {
  local port="$ANSWERSERVER_ACI_PORT"
  if [[ -z "$port" ]]; then
    port=$(published_answerserver_port || true)
  fi
  if [[ -z "$port" ]]; then
    port="$ANSWERSERVER_ACI_INTERNAL_PORT"
  fi
  ANSWERSERVER_ACI_PORT="$port"
  ANSWERSERVER_ACI_URL="${ANSWERSERVER_ACI_SCHEME}://${ANSWERSERVER_ACI_HOST}:${ANSWERSERVER_ACI_PORT}/action=GetStatus"
}

answerserver_getstatus_ok() {
  local body http_code
  local curl_opts=()
  [[ "$ANSWERSERVER_ACI_SCHEME" == "https" ]] && curl_opts+=(-k)
  http_code=$(curl -sS "${curl_opts[@]}" --max-time 8 \
    -o /tmp/idol_answerserver_getstatus.xml \
    -w "%{http_code}" \
    "$ANSWERSERVER_ACI_URL" 2>/tmp/idol_answerserver_getstatus.err || true)
  body=$(cat /tmp/idol_answerserver_getstatus.xml 2>/dev/null || true)
  if [[ "$http_code" == "200" ]] && echo "$body" | grep -qiE '<response>SUCCESS</response>|"SUCCESS"'; then
    return 0
  fi
  # Some builds return SUCCESS XML with a non-200 or empty code; still accept SUCCESS
  if echo "$body" | grep -qiE '<response>SUCCESS</response>'; then
    return 0
  fi
  return 1
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
  # Some images have no HEALTHCHECK — treat missing Health as skip, not failure
  if [[ -z "$HEALTH" ]]; then
    log "No Healthcheck configured — skipping health wait"
    break
  fi
  log "Health status: ${HEALTH:-unknown}"
  sleep_and_tick $INTERVAL_SLOW
  check_timeout "container never became 'healthy'"
done
success "Container is healthy"

# ── Phase 2b: Answer Server ACI GetStatus ─────────────────────────────────────
echo ""
echo "Phase 2b: Waiting for Answer Server ACI GetStatus SUCCESS..."
echo "  Container: $ANSWERSERVER_CONTAINER"

while true; do
  if ! resolve_answerserver_container; then
    log "Answer Server container not found (looked for $ANSWERSERVER_CONTAINER)"
    sleep_and_tick $INTERVAL_FAST
    check_timeout answerserver "Answer Server container never appeared"
    continue
  fi

  AS_STATUS=$(docker inspect "$ANSWERSERVER_CONTAINER" --format='{{.State.Status}}' 2>/dev/null || true)
  if [[ "$AS_STATUS" != "running" ]]; then
    log "Answer Server status: ${AS_STATUS:-not found}"
    sleep_and_tick $INTERVAL_FAST
    check_timeout answerserver "Answer Server container never reached 'running'"
    continue
  fi

  resolve_answerserver_aci_url
  log "GET $ANSWERSERVER_ACI_URL"

  if answerserver_getstatus_ok; then
    success "Answer Server ACI is up (GetStatus SUCCESS on ${ANSWERSERVER_ACI_SCHEME}://${ANSWERSERVER_ACI_HOST}:${ANSWERSERVER_ACI_PORT})"
    break
  fi

  CURL_ERR=$(tr '\n' ' ' < /tmp/idol_answerserver_getstatus.err 2>/dev/null || true)
  HTTP_HINT=$(head -c 200 /tmp/idol_answerserver_getstatus.xml 2>/dev/null || true)
  log "GetStatus not ready yet${CURL_ERR:+ — $CURL_ERR}${HTTP_HINT:+ — $HTTP_HINT}"
  sleep_and_tick $INTERVAL_SLOW
  check_timeout answerserver "Answer Server GetStatus never returned SUCCESS"
done

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
rm -f "$COOKIES" /tmp/idol_health_response.html \
  /tmp/idol_answerserver_getstatus.xml /tmp/idol_answerserver_getstatus.err
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ IDOL UI is fully ready after ${elapsed}s"
echo "   URL:  $LOGIN_PAGE_URL"
[[ "${IDOL_UI_NAME:-}" == "dataadmin" ]] && echo "   User: $USERNAME"
echo "   Answer Server: $ANSWERSERVER_CONTAINER"
echo "   ACI GetStatus: ${ANSWERSERVER_ACI_URL:-n/a}"
echo "   Time: $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
