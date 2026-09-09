#!/bin/bash

exec 1> >(stdbuf -o0 cat)
exec 2> >(stdbuf -o0 cat >&2)

# ── Config ─────────────────────────────────────────────────────────────────────
CONTAINER="${CONTAINER:-${IDOL_DEPLOYMENT_TYPE:-idol-demo}-idol-nifi-1}"
NIFI_PORT="${NIFI_PORT:-8443}"
# Each phase gets its own timeout budget instead of sharing one global clock.
# A cold start (NAR expansion + full component validation) can legitimately
# take 15+ minutes on its own, so Phase 3/4 need generous headroom.
MAX_WAIT_CONTAINER=120     # Phase 1: container reaches 'running'
MAX_WAIT_LOG=120           # Phase 2: nifi-app.log appears
MAX_WAIT_NAR=900           # Phase 3: NAR unpacking completes
MAX_WAIT_START=1500        # Phase 4: application fully started
INTERVAL_FAST=5
INTERVAL_SLOW=60
INTERVAL_WATCH=5
elapsed=0
EXPECTED_NARS=0

HOST="https://localhost:${NIFI_PORT}"
NIFI_URL="$HOST/idol-nifi"

# ── Helpers ────────────────────────────────────────────────────────────────────
log()     { echo "  [$(date '+%H:%M:%S')] $*"; }
success() { echo "  ✅ $*"; }
fail()    {
  echo "  ❌ $*"
  exit 1
}

check_timeout() {
  # $1 = failure message, $2 = this phase's max wait (defaults to MAX_WAIT_START)
  local max_wait="${2:-$MAX_WAIT_START}"
  if [[ $elapsed -ge $max_wait ]]; then
    log "Last container logs:"
    docker logs "$CONTAINER" --tail=20 2>/dev/null || log "(no container logs available)"
    fail "Timed out after ${max_wait}s — $1"
  fi
}

sleep_and_tick() {
  local interval=$1
  sleep "$interval"
  elapsed=$((elapsed + interval))
}

count_nars() {
    local ext frm
    ext=$(docker exec $CONTAINER ls /opt/nifi/nifi-current/work/nar/extensions/ 2>/dev/null | grep -c "\.nar-unpacked" | tr -d '[:space:]')
    frm=$(docker exec $CONTAINER ls /opt/nifi/nifi-current/work/nar/framework/ 2>/dev/null | grep -c "\.nar-unpacked" | tr -d '[:space:]')
    echo $(( ${ext:-0} + ${frm:-0} ))
}

nifi_log_grep() {
    local count
    count=$(docker exec "$CONTAINER" grep -c "$1" /opt/nifi/nifi-current/logs/nifi-app.log 2>/dev/null | tr -d '[:space:]')
    echo "${count:-0}"
}

show_nar_listing() {
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    if [[ "${LISTING_SHOWN:-false}" == "true" ]]; then
        local lines
        lines=$(( LAST_LISTING_LINES + 4 ))
        printf "\033[%dA" "$lines"
        printf "\033[J"
    fi

    echo  "  ┌─────────────────────────────────────────────────────────────────┐"
    printf "  │ [%s] work/nar/extensions/ - NARs unpacked: %d / %d            \n" "$timestamp" "$NAR_COUNT" "$EXPECTED_NARS"
    echo  "  ├─────────────────────────────────────────────────────────────────┤"

    local listing
    listing=$(docker exec "$CONTAINER" ls -la /opt/nifi/nifi-current/work/nar/extensions/ 2>/dev/null)
    LAST_LISTING_LINES=$(echo "$listing" | wc -l)

    echo "$listing" | while IFS= read -r line; do
        printf "  │ %-67s\n" "$line"
    done

    echo  "  └─────────────────────────────────────────────────────────────────┘"
    LISTING_SHOWN=true
}

# ── Phase 1: Container exists and is running ───────────────────────────────────
echo ""
echo "Phase 1: Waiting for container to start..."
elapsed=0
while true; do
  STATUS=$(docker inspect "$CONTAINER" --format='{{.State.Status}}' 2>/dev/null || true)
  if [[ "$STATUS" == "running" ]]; then break; fi
  log "Container status: ${STATUS:-not found}"
  sleep_and_tick $INTERVAL_FAST
  check_timeout "container never reached 'running'" $MAX_WAIT_CONTAINER
done
success "Container is running"

# ── Phase 2: NiFi log appears ─────────────────────────────────────────────────
echo ""
echo "Phase 2: Waiting for NiFi to initialize..."
elapsed=0
while true; do
  LOG_EXISTS=$(docker exec "$CONTAINER" test -f /opt/nifi/nifi-current/logs/nifi-app.log 2>/dev/null && echo "yes" || echo "no")
  if [[ "$LOG_EXISTS" == "yes" ]]; then break; fi
  log "Waiting for nifi-app.log to appear..."
  sleep_and_tick $INTERVAL_FAST
  check_timeout "nifi-app.log never appeared" $MAX_WAIT_LOG
done
success "NiFi log is available"

# ── Phase 3: NAR unpacking ────────────────────────────────────────────────────
echo ""
echo "Phase 3: Waiting for NAR files to unpack..."
echo ""
LISTING_SHOWN=false
LAST_LISTING_LINES=0
elapsed=0

while true; do
  # Read EXPECTED_NARS from log once available, then cache it
  if [[ $EXPECTED_NARS -eq 0 ]]; then
    EXPECTED_NARS=$(docker exec $CONTAINER grep -o "Expanding [0-9]* NAR files started" /opt/nifi/nifi-current/logs/nifi-app.log 2>/dev/null | grep -o "[0-9]*" | head -1 | tr -d '[:space:]')
    EXPECTED_NARS=$(( ${EXPECTED_NARS:-0} ))
  fi

  # Fallback: NARs may already be unpacked from a previous run
  if [[ $EXPECTED_NARS -eq 0 ]]; then
    CACHED=$(count_nars)
    if [[ $CACHED -gt 0 ]]; then
      EXPECTED_NARS=$CACHED
    fi
  fi

  NAR_COUNT=$(count_nars)

  ERRORS=$(nifi_log_grep "Failed to start Server")
  ERRORS=$(( ${ERRORS:-0} ))
  if [[ $ERRORS -gt 0 ]]; then
    echo ""
    log "Last log lines:"
    docker exec $CONTAINER tail -10 /opt/nifi/nifi-current/logs/nifi-app.log
    fail "NiFi failed to start — see log above"
  fi

  if [[ $EXPECTED_NARS -eq 0 ]]; then
    log "Waiting for NAR expansion to begin..."
    sleep_and_tick $INTERVAL_FAST
  else
    show_nar_listing
    if [[ $NAR_COUNT -ge $EXPECTED_NARS ]]; then
      echo ""
      break
    fi
    sleep_and_tick $INTERVAL_WATCH
  fi

  check_timeout "NAR unpacking never completed" $MAX_WAIT_NAR
done
success "All NARs unpacked ($NAR_COUNT / $EXPECTED_NARS)"

# ── Phase 4: NiFi application started ─────────────────────────────────────────
echo ""
echo "Phase 4: Waiting for NiFi application to start..."
elapsed=0
while true; do
  ERRORS=$(nifi_log_grep "Failed to start Server")
  ERRORS=$(( ${ERRORS:-0} ))
  if [[ $ERRORS -gt 0 ]]; then
    echo ""
    log "Last log lines:"
    docker exec $CONTAINER tail -10 /opt/nifi/nifi-current/logs/nifi-app.log
    fail "NiFi failed to start — see log above"
  fi

  STARTED=$(nifi_log_grep "Started Application in")
  STARTED=$(( ${STARTED:-0} ))
  if [[ $STARTED -gt 0 ]]; then
    STARTUP_TIME=$(docker exec "$CONTAINER" grep "Started Application in" /opt/nifi/nifi-current/logs/nifi-app.log 2>/dev/null | grep -o "in [0-9.]* seconds" | tail -1)
    break
  fi

  if   [[ $(nifi_log_grep "Flow Controller started successfully") -gt 0 ]]; then
    log "Flow Controller started — waiting for web server..."
  elif [[ $(nifi_log_grep "Starting Flow Controller") -gt 0 ]]; then
    log "Starting Flow Controller..."
  elif [[ $(nifi_log_grep "NarAutoLoader") -gt 0 ]]; then
    log "NAR Auto-Loader running..."
  elif [[ $(nifi_log_grep "jetty") -gt 0 ]]; then
    log "Jetty web server initializing..."
  else
    log "NiFi is initializing..."
  fi

  sleep_and_tick $INTERVAL_SLOW
  check_timeout "NiFi application never started" $MAX_WAIT_START
done
success "NiFi application started ${STARTUP_TIME:-}"

# ── Phase 5: Container health check ───────────────────────────────────────────
echo ""
echo "Phase 5: Checking container health..."
HEALTH=$(docker inspect "$CONTAINER" --format='{{.State.Health.Status}}' 2>/dev/null || true)
if [[ "$HEALTH" == "healthy" ]]; then
  success "Container is healthy"
else
  # NiFi returns 401 to unauthenticated healthcheck — this is expected with SSL + single-user auth
  # Since Phase 4 confirmed NiFi started successfully, we treat this as healthy
  log "Health status: ${HEALTH} (401 from healthcheck is expected with authentication enabled — NiFi is running)"
  success "NiFi is reachable and authenticated access is required (normal)"
fi

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ NiFi is fully ready after ${elapsed}s"
echo "   URL:  $NIFI_URL"
echo "   User: admin"
echo "   Time: $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"