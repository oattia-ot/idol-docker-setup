#! /bin/sh

# BEGIN COPYRIGHT NOTICE
# Copyright 2023-2024 Open Text.
# 
# The only warranties for products and services of Open Text and its affiliates and licensors
# ("Open Text") are as may be set forth in the express warranty statements accompanying such
# products and services. Nothing herein should be construed as constituting an additional warranty.
# Open Text shall not be liable for technical or editorial errors or omissions contained herein.
# The information contained herein is subject to change without notice.
#
# END COPYRIGHT NOTICE

# This is run by the dih edit-config initContainer to populate initial dih config

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

. "/scripts/distributed-idol/common_utils.sh"

function checkMirrorModeChange() {
  if [ -e /mnt/store/dih/dih.cfg ]
  then 
    local cfg_mirrormode
    local want_mirrormode
    cfg_mirrormode=$(grep MirrorMode /mnt/store/dih/dih.cfg)
    want_mirrormode=$(grep MirrorMode /mnt/config-map/dih.cfg)
    if [ "${cfg_mirrormode}" != "${want_mirrormode}" ]
    then 
      echo "[$(date)] Detected an attempt to alter MirrorMode configuration (${cfg_mirrormode} -> ${want_mirrormode}). Aborting."
      exit 1; 
    fi
    echo "[$(date)] No modifications made to extant dih.cfg."
    exit 0;
  fi
}

logfile=/mnt/store/dih/edit-config.log
(
  echo "[$(date)] Start dih init" 
  checkMirrorModeChange
  getMaxPodId
  writeDistIdolConfigChanges /mnt/config-map/dih.cfg /mnt/store/dih/dih.install.cfg
) | tee -a "${logfile}"









