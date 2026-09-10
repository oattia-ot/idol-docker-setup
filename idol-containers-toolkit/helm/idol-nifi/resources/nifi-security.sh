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

set -ex -o allexport

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

ORGANISATION_UNIT=${ORGANISATION_UNIT:-'Cloud Services Application'}
ORGANISATION=${ORGANISATION:-'Cloud Services'}
#PUBLIC_DNS=${POD_NAME:-'nifi.tld'}
CITY=${CITY:-'London'}
STATE=${STATE:-'London'}
COUNTRY_CODE=${COUNTRY_CODE:-'GB'}
KEY_PASS=${KEY_PASS:-$KEYSTORE_PASS}
KEYSTORE_PASS=${KEYSTORE_PASS:-$NIFI_SENSITIVE_PROPS_KEY}
KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD:-$NIFI_SENSITIVE_PROPS_KEY}
#KEYSTORE_PATH=${NIFI_HOME}/keytool/keystore.p12
#KEYSTORE_TYPE=jks
TRUSTSTORE_PASS=${TRUSTSTORE_PASS:-$NIFI_SENSITIVE_PROPS_KEY}
TRUSTSTORE_PASSWORD=${TRUSTSTORE_PASSWORD:-$NIFI_SENSITIVE_PROPS_KEY}
#TRUSTSTORE_PATH=${NIFI_HOME}/keytool/truststore.jks
#TRUSTSTORE_TYPE=jks

if [[ ! -f "${NIFI_HOME}/keytool/keystore.p12" ]]
then
    echo "[$(date)] Creating keystore"
    keytool -genkey -noprompt -alias nifi-keystore \
    -dname "CN=${POD_NAME},OU=${ORGANISATION_UNIT},O=${ORGANISATION},L=${CITY},S=${STATE},C=${COUNTRY_CODE}" \
    -keystore "${NIFI_HOME}/keytool/keystore.p12" \
    -storepass "${KEYSTORE_PASS:-$NIFI_SENSITIVE_PROPS_KEY}" \
    -KeySize 2048 \
    -keypass "${KEY_PASS:-$NIFI_SENSITIVE_PROPS_KEY}" \
    -keyalg RSA \
    -storetype pkcs12
fi

if [[ ! -f "${NIFI_HOME}/keytool/truststore.jks" ]]
then
    echo "[$(date)] Creating truststore"
    keytool -genkey -noprompt -alias nifi-truststore \
    -dname "CN=${POD_NAME},OU=${ORGANISATION_UNIT},O=${ORGANISATION},L=${CITY},S=${STATE},C=${COUNTRY_CODE}" \
    -keystore "${NIFI_HOME}/keytool/truststore.jks" \
    -storetype jks \
    -keypass "${KEYSTORE_PASS:-$NIFI_SENSITIVE_PROPS_KEY}" \
    -keyalg RSA \
    -storepass "${KEY_PASS:-$NIFI_SENSITIVE_PROPS_KEY}" \
    -KeySize 2048
fi

#/usr/bin/bash ${NIFI_HOME}/../scripts/secure.sh
#eval ${NIFI_HOME}/../scripts/secure.sh