#!/bin/bash

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

logfile=/opt/nifi/nifi-current/logs/pre-stop.log
(
    statefulsetname=${POD_NAME%-*}
    grep "${statefulsetname}-0" /etc/hostname
    notprimary=$?
    if [ 0 == ${notprimary} ]; then
        echo "[$(date)] Skipping pre-stop as primary instance."
        exit 0
    fi

    host=${POD_NAME%-*}-0.${NIFI_WEB_HTTP_HOST#*.}
    echo "[$(date)] Primary instance host $host"

    port=$NIFI_WEB_HTTP_PORT
    echo "[$(date)] Primary instance port $port"

    cluster_node_id=$(curl -s "http://$NIFI_WEB_HTTP_HOST:$NIFI_WEB_HTTP_PORT/nifi-api/controller/cluster" | jq -r ".cluster.nodes[] | select(.address==\"$NIFI_WEB_HTTP_HOST\") | .nodeId ")
    echo "[$(date)] Cluster node id $cluster_node_id"

    setAndWaitForStatus () {
        echo "[$(date)] Setting status $1"
        cluster_node_status=$(curl -s -X PUT "http://$host:$port/nifi-api/controller/cluster/nodes/$cluster_node_id" -H 'Content-Type: application/json' -d "{\"node\":{\"nodeId\":\"$cluster_node_id\",\"status\": \"$1\"}}" | jq .node.status -r)
        while [ "$cluster_node_status" != "$2" ]
        do
            echo "[$(date)] Waiting for status $2, status is $cluster_node_status"
            sleep 1
            cluster_node_status=$(curl -s "http://$host:$port/nifi-api/controller/cluster/nodes/$cluster_node_id" | jq .node.status -r)
        done
        echo "[$(date)] Status reached $cluster_node_status"
    }

    if [ -z "$cluster_node_id" ]; then
        echo "[$(date)] Skipping pre-stop as no cluster_node_id."
        exit 0
    fi

    setAndWaitForStatus "DISCONNECTING" "DISCONNECTED"
    setAndWaitForStatus "OFFLOADING" "OFFLOADED"

    echo "[$(date)] Removing cluster node $cluster_node_id"
    curl -s -X DELETE "http://$host:$port/nifi-api/controller/cluster/nodes/$cluster_node_id"
    echo "[$(date)] Removed cluster node $cluster_node_id"
) | tee -a ${logfile}