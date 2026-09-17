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

echo "=== Checking environment variables ==="
env | grep -i "PKCS\|JKS\|KEY\|PASS\|SSL"

echo -e "\n=== Checking mounted files ==="
ls -la /ssl/certs/ 2>/dev/null || echo "/ssl/certs not found"
ls -la /opt/find/*.jks 2>/dev/null || echo "No JKS files in /opt/find"
ls -la /opt/find/*.p12 /opt/find/*.pkcs12 2>/dev/null || echo "No PKCS12 files in /opt/find"

echo -e "\n=== Checking if PKCS12 file exists ==="
if [ -f "$IDOL_UI_PKCS_FILE" ]; then
    echo "PKCS file found at: $IDOL_UI_PKCS_FILE"
    echo "File size: $(stat -c%s "$IDOL_UI_PKCS_FILE") bytes"
else
    echo "ERROR: PKCS file NOT found at: $IDOL_UI_PKCS_FILE"
fi

echo -e "\n=== Testing keystore password ==="
if [ -f "/opt/find/find.jks" ]; then
    echo "Testing find.jks password..."
    keytool -list -keystore /opt/find/find.jks -storepass "$KEYSTORE_PASS" && echo "Password OK" || echo "Password FAILED"
fi

if [ -f "$IDOL_UI_PKCS_FILE" ]; then
    echo "Testing PKCS12 password..."
    keytool -list -keystore "$IDOL_UI_PKCS_FILE" -storetype PKCS12 -storepass "$KEYSTORE_PASS" && echo "Password OK" || echo "Password FAILED"
fi
