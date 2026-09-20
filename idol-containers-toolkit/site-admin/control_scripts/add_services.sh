#!/bin/bash
###
# Copyright (c) 2021 Micro Focus or one of its affiliates.
#
# Licensed under the MIT License (the "License"); you may not use this file
# except in compliance with the License.
#
# The only warranties for products and services of Micro Focus and its affiliates
# and licensors ("Micro Focus") are as may be set forth in the express warranty
# statements accompanying such products and services. Nothing herein should be
# construed as constituting an additional warranty. Micro Focus shall not be
# liable for technical or editorial errors or omissions contained herein. The
# information contained herein is subject to change without notice.
###

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

source /controller/startup_utils.sh

## Command to call with an HTTP request
MAKE_REQUEST="curl -s"

## Functions to add services to controller
function add_content_service {
    content_controller_hostname=$1

    # Wait for controller to be available
    waitForAci ${content_controller_hostname}:41200
    # Add service
    ${MAKE_REQUEST} "http://localhost:41200/a=addservice&execpath=/content/content.exe&configpath=/content/cfg/content.cfg&controlmethod=script&initscriptpath=/content/control-content.sh"
}

function add_support_services {
    # Add agentstore, categorisation-agentstore, community, view

    support_controller_hostname=$1

    # Wait for controllers to be available
    waitForAci ${support_controller_hostname}:41200

    # Agentstore
    ${MAKE_REQUEST} "http://localhost:41200/a=addservice&execpath=/agentstore/agentstore.exe&configpath=/agentstore/cfg/agentstore.cfg&controlmethod=script&initscriptpath=/agentstore/control-agentstore.sh"

    # Categorisation-agentstore
    ${MAKE_REQUEST} "http://localhost:41200/a=addservice&execpath=/categorisation-agentstore/categorisation-agentstore.exe&configpath=/categorisation-agentstore/cfg/categorisation-agentstore.cfg&controlmethod=script&initscriptpath=/categorisation-agentstore/control-categorisation-agentstore.sh"

    # Community
    ${MAKE_REQUEST} "http://localhost:41200/a=addservice&execpath=/community/community.exe&configpath=/community/cfg/community.cfg&controlmethod=script&initscriptpath=/community/control-community.sh"

    # View
    ${MAKE_REQUEST} "http://localhost:41200/a=addservice&execpath=/view/view.exe&configpath=/view/cfg/view.cfg&controlmethod=script&initscriptpath=/view/control-view.sh"
}

function add_siteadmin_backend_services {
    # Add agentstore, community

    siteadmin_backend_controller_hostname=$1

    # Wait for controllers to be available
    waitForAci ${siteadmin_backend_controller_hostname}:41200

    # Agentstore
    ${MAKE_REQUEST} "http://localhost:41200/a=addservice&execpath=/agentstore/agentstore.exe&configpath=/agentstore/cfg/agentstore.cfg&controlmethod=script&initscriptpath=/agentstore/control-agentstore.sh"

    # Community
    ${MAKE_REQUEST} "http://localhost:41200/a=addservice&execpath=/community/community.exe&configpath=/community/cfg/community.cfg&controlmethod=script&initscriptpath=/community/control-community.sh"
}


## Functions to start services
function start_content {
    content_controller_hostname=$1

    # Wait for controller to be available
    waitForAci ${content_controller_hostname}:41200

    # Start service
    ${MAKE_REQUEST} "http://localhost:41200/a=startservice&port=9100"
    waitForAci localhost:9100
}

function start_support_services {
    # Add agentstore, categorisation-agentstore, community, view

    support_controller_hostname=$1
    content_controller_hostname=$2

    # Wait for controllers to be available
    waitForAci ${support_controller_hostname}:41200
    waitForAci ${content_controller_hostname}:41200

    # Agentstore
    ${MAKE_REQUEST} "http://localhost:41200/a=startservice&port=9050"
    waitForAci localhost:9050

    # Categorisation-agentstore
    ${MAKE_REQUEST} "http://localhost:41200/a=startservice&port=9182"
    waitForAci localhost:9182

    # Community
    waitForAci ${content_controller_hostname}:9100
    ${MAKE_REQUEST} "http://localhost:41200/a=startservice&port=9030"
    waitForAci localhost:9030

    # View
    ${MAKE_REQUEST} "http://localhost:41200/a=startservice&port=9080"
    waitForAci localhost:9080
}

function start_siteadmin_backend_services {
    # Add agentstore, community

    support_controller_hostname=$1
    content_controller_hostname=$2

    # Wait for controllers to be available
    waitForAci ${support_controller_hostname}:41200
    waitForAci ${content_controller_hostname}:41200

    # Agentstore
    ${MAKE_REQUEST} "http://localhost:41200/a=startservice&port=9050"
    waitForAci localhost:9050

    # Community
    waitForAci ${content_controller_hostname}:9100
    ${MAKE_REQUEST} "http://localhost:41200/a=startservice&port=9030"
    waitForAci localhost:9030
}


function add_to_coordinator {
    controller_hostname=$1
    # Once coordinator is ready, add this controller to it
    waitForAci idol-coordinator:40200
    ${MAKE_REQUEST} "http://idol-coordinator:40200/a=addcontroller&HostName="${controller_hostname}"&Port=41200&ConnectByHostName=True"
}