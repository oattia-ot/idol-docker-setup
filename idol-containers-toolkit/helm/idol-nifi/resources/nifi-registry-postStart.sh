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

logdir=/opt/nifi-registry/nifi-registry-current/logs
mkdir -p ${logdir}

. "$( dirname "${BASH_SOURCE[0]}" )"/nifi-toolkit-utils.sh

NIFI_REGISTRY_URL=http://${HOSTNAME}:18080

logfile=${logdir}/post-start.log
(
    nifitoolkit_registry_waitForCLI "${NIFI_REGISTRY_URL}"

    for i in $(seq 0 "${NIFI_REGISTRY_BUCKET_COUNT}"); do
        if [  "$i" -eq "${NIFI_REGISTRY_BUCKET_COUNT}" ]; then
            continue
        fi

        FLOWFILES_ENV_NAME=NIFI_REGISTRY_BUCKET_FILES_$i
        BUCKETNAME_ENV_NAME=NIFI_REGISTRY_BUCKET_NAME_$i
        FLOWFILES="${!FLOWFILES_ENV_NAME}"
        BUCKET_NAME="${!BUCKETNAME_ENV_NAME}"

        # Create the bucket
        BUCKETID=
        nifitoolkit_registry_findOrCreateBucket "${NIFI_REGISTRY_URL}" "${BUCKET_NAME}" BUCKETID
        echo "[$(date)] Got bucket ${BUCKET_NAME}: ${BUCKETID}"

        # Check for envsubst support
        ENVSUBST=$(which envsubst)
        TMPDIR=$(mktemp -d)

        # Import any flows
        for ORIG_FLOWFILE in ${FLOWFILES//,/ }
        do
            echo "[$(date)] Processing FLOWFILE ${ORIG_FLOWFILE}"

            if [ ! -f "${ORIG_FLOWFILE}" ]; then
                echo "[$(date)] FLOWFILE ${ORIG_FLOWFILE} does not exist"
                echo "[$(date)] Flow import skipped"
                continue
            fi

            if [[ -z "${ENVSUBST}" ]]; then
                FLOWFILE="${ORIG_FLOWFILE}"
            else
                # Run flow through environment substitutions
                # This will only replace variables with exported values
                FLOWFILE="${TMPDIR}/$(basename "${ORIG_FLOWFILE}")"
                envsubst "$(compgen -e | awk '$0="${"$0"}"')" < "${ORIG_FLOWFILE}" > "${FLOWFILE}"
                echo "[$(date)] Expanded FLOWFILE: ${FLOWFILE}"
            fi

            FLOWID=
            FLOWVERSION=
            nifitoolkit_registry_importFlow "${NIFI_REGISTRY_URL}" "${BUCKETID}" "${FLOWFILE}" FLOWID FLOWVERSION
            echo "[$(date)] Imported Flow ${FLOWID} (version ${FLOWVERSION})"
        done

    done
) | tee -a ${logfile}
