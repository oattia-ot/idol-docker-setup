#!/bin/bash

# Get to correct directory to run <COMPONENT>.
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

pushd /<COMPONENT> > /dev/null 2>&1

run_prestart_scripts() {
  for script in /<COMPONENT>/prestart_scripts/*.sh; do [ -f "$script" ] && source "$script"; done
}

run_poststart_scripts() {
  for script in /<COMPONENT>/poststart_scripts/*.sh; do [ -f "$script" ] && source "$script"; done
}

if [ $1 == 'start' ]
then
    run_prestart_scripts

    echo "--------------------------------------------------------------------"
    echo "Micro Focus <COMPONENT> Server"
    echo "(c) 1999-2021 Micro Focus"
    echo "--------------------------------------------------------------------"
    echo "Starting <COMPONENT> Server..."

    /<COMPONENT>/<COMPONENT>.exe -configfile /<COMPONENT>/cfg/<COMPONENT>.cfg &
    serverpid=$!
    echo "Started <COMPONENT> Server with PID $serverpid"

    run_poststart_scripts
fi

if [ $1 == 'stop' ]
then
    echo "Stopping <COMPONENT> Server..."
    if [ -f <COMPONENT>.pid ]
    then
        kill -15 `cat <COMPONENT>.pid`
        echo "Stopped <COMPONENT> Server"
        else
        echo "Could not locate <COMPONENT>.pid - unable to stop <COMPONENT> Server"
    fi 
fi

exit

