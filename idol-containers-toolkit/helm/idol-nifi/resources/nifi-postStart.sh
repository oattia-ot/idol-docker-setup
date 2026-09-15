#! /bin/bash

# BEGIN COPYRIGHT NOTICE
# Copyright 2023 Open Text.
#
# The only warranties for products and services of Open Text and its affiliates and licensors
# ("Open Text") are as may be set forth in the express warranty statements accompanying such
# products and services. Nothing herein should be construed as constituting an additional warranty.
# Open Text shall not be liable for technical or editorial errors or omissions contained herein.
# The information contained herein is subject to change without notice.
#
# END COPYRIGHT NOTICE

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

logfile=/opt/nifi/nifi-current/logs/post-start.log
(
    . "$( dirname "${BASH_SOURCE[0]}" )/nifi-toolkit-utils.sh"

    if [ -z "${JAVA_HOME}" ]
    then
        JAVA_HOME=$(java -XshowSettings:properties -version 2>&1 | grep java.home | cut -d = -f 2 | xargs)
        export JAVA_HOME="$JAVA_HOME"
        echo ["$(date)"] Using auto-detected JAVA_HOME: "$JAVA_HOME"
    fi

    nifitoolkit_nifi_waitForCLI
    nifitoolkit_configure_threads "${IDOL_NIFI_THREADS:-10}"

    statefulsetname=${POD_NAME%-*}
    grep "${statefulsetname}-0" /etc/hostname
    notprimary=$?
    if [ 1 == ${notprimary} ]; then
        echo ["$(date)"] Skipping post-start checks as non-primary instance
        exit 0
    fi

    NODECOUNT=
    nifitoolkit_nifi_getClusterNodeCount NODECOUNT
    if [ "${NODECOUNT}" -gt 1 ]; then
        echo ["$(date)"] Skipping post-start checks as cluster is already running "( ${NODECOUNT} )"
        exit 0
    fi

    /scripts/connect-registry.sh
    if [ -f /scripts/prometheous-reporting.sh ]; then
        /scripts/prometheous-reporting.sh
    fi
    /scripts/import-flow.sh

    echo ["$(date)"] postStart completed
) | tee -a ${logfile}
