#!/bin/bash

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

source /community/startup_utils.sh

COMMUNITY_PORT=DA_COMMUNITY_ACI_PLACEHOLDER

# FIX: use correct env var names (IDOL_AGENTSTORE_PORT not IDOL_AGENTSTORE_ACI_PORT)
_IDOL_CONTENT_HOST=${IDOL_CONTENT_HOST:-idol-content}
_IDOL_CONTENT_PORT=${PORT_DATA_ADMIN_PASSAGE_CONTENT:-DA_PASSAGEEXTRATOR_CONTENT_ACI_PLACEHOLDER}
_IDOL_AGENTSTORE_HOST=${IDOL_AGENTSTORE_HOST:-idol-agentstore}
_IDOL_AGENTSTORE_PORT=${PORT_DATA_ADMIN_QMS_AGENTSTORE:-DA_QMS_AGENTSTORE_ACI_PLACEHOLDER}

function checkAesKeyfile() {
    if [ -e ./autpassword.exe ]
    then
        local AESKEYFILE=/community/cfg/aes.keyfile
        if [ -e $AESKEYFILE ]
        then
            echo "Found AES keyfile"
        else
            ./autpassword.exe -x -tAES -oKeyFile=$AESKEYFILE
        fi
    fi
}

function finalizeConfigFile {
    sed -i "s/XX_IDOL_AGENTSTORE_HOST_XX/${_IDOL_AGENTSTORE_HOST}/g" /community/cfg/community.cfg
    sed -i "s/XX_IDOL_AGENTSTORE_PORT_XX/${_IDOL_AGENTSTORE_PORT}/g" /community/cfg/community.cfg
    sed -i "s/XX_IDOL_CONTENT_HOST_XX/${_IDOL_CONTENT_HOST}/g" /community/cfg/community.cfg
    sed -i "s/XX_IDOL_CONTENT_PORT_XX/${_IDOL_CONTENT_PORT}/g" /community/cfg/community.cfg
}

checkAesKeyfile
waitForAci $_IDOL_CONTENT_HOST:$_IDOL_CONTENT_PORT
waitForAci $_IDOL_AGENTSTORE_HOST:$_IDOL_AGENTSTORE_PORT
finalizeConfigFile