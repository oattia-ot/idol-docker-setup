#!/bin/bash

# Source the same utilities used by healthcheck.sh
# IDOL OS detection (Ubuntu / macOS) — loads module/os-compat.sh when present
if [ -z "${IDOL_OS_COMPAT_LOADED:-}" ]; then
  _idol_os_src=""
  if [ -n "${IDOL_BASE_PATH:-}" ] && [ -f "${IDOL_BASE_PATH}/module/os-compat.sh" ]; then
    _idol_os_src="${IDOL_BASE_PATH}/module/os-compat.sh"
  else
    _idol_os_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
    _idol_os_probe="$_idol_os_dir"
    _idol_os_i=0
    while [ -n "$_idol_os_probe" ] && [ "$_idol_os_probe" != "/" ] && [ "$_idol_os_i" -lt 20 ]; do
      if [ -f "$_idol_os_probe/module/os-compat.sh" ]; then
        _idol_os_src="$_idol_os_probe/module/os-compat.sh"
        break
      fi
      _idol_os_probe="$(dirname "$_idol_os_probe")"
      _idol_os_i=$((_idol_os_i + 1))
    done
  fi
  if [ -n "$_idol_os_src" ]; then
    # shellcheck source=/dev/null
    . "$_idol_os_src"
  else
    case "$(uname -s 2>/dev/null)" in
      Darwin)
        export IDOL_HOST_OS=macos IDOL_OS_FAMILY=macos
        ;;
      Linux)
        export IDOL_OS_FAMILY=linux
        if [ -f /etc/os-release ] && grep -qi ubuntu /etc/os-release 2>/dev/null; then
          export IDOL_HOST_OS=ubuntu
        else
          export IDOL_HOST_OS=linux
        fi
        ;;
      *)
        export IDOL_HOST_OS=unknown IDOL_OS_FAMILY=unknown
        ;;
    esac
  fi
  unset _idol_os_src _idol_os_dir _idol_os_probe _idol_os_i
fi

source ./utilities/utils.sh

if [[ -z ${IDOL_SSL} ]]; then
    HTTP_SCHEME=http
else
    HTTP_SCHEME=https
fi

# Derive ACI port dynamically from IDOL_PORTS env var (same as healthcheck.sh)
ACI_PORT=$(echo ${IDOL_PORTS} | awk -F' ' '{print $1}')

function wait_for_aci_service {
    local HOST=$1
    local PORT=$2
    local SLEEP_TIME=$3
    local MAX_RETRIES=$4
    local RETRIES=0
    echo "Waiting for ACI service on ${HOST}:${PORT}..."
    while :
    do
        if [ ! $RETRIES -lt $MAX_RETRIES ]; then
            echo "Timeout while waiting for ACI service on ${HOST}:${PORT}"
            exit 1
        fi
        HTTP_STATUS="$(ping_endpoint "${HTTP_SCHEME}://${HOST}:${PORT}/a=getpid" || true)"
        if [ -z "$HTTP_STATUS" ] || [ "$HTTP_STATUS" = "000" ]; then
            sleep $SLEEP_TIME
            RETRIES=$((RETRIES+1))
            continue
        else
            echo "ACI service on ${HOST}:${PORT} is available (HTTP ${HTTP_STATUS})"
            break
        fi
    done
}

wait_for_aci_service localhost ${ACI_PORT} 1 60

for i in $(ls idx/*.idx.gz 2>/dev/null); do
    if [ ! -e $i.indexed ]; then
        echo "Indexing $i"
        ping_endpoint "${HTTP_SCHEME}://localhost:${ACI_PORT}/DREADD?/content/$i" > /dev/null
        touch $i.indexed
    fi
done
rm -f doc.txt*