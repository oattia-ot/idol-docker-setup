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

KEYSTORE_PASS="aaaaaaaaa"
TRUSTSTORE_PASS="bbbbbbbbb"

echo "Testing KeyStore password..."
if keytool -list -keystore ssl/intermediate/nifi/keystore.jks -storepass ${KEYSTORE_PASS} > /dev/null 2>&1; then
    echo "✓ KeyStore password is correct"
else
    echo "✗ KeyStore password is incorrect"
fi

echo "Testing TrustStore password..."
if keytool -list -keystore ssl/intermediate/nifi/truststore.jks -storepass ${TRUSTSTORE_PASS} > /dev/null 2>&1; then
    echo "✓ TrustStore password is correct"
else
    echo "✗ TrustStore password is incorrect"
fi

## What to Expect

# --> If the password is **correct**, you'll see output like:
# Keystore type: JKS
# Keystore provider: SUN
# Your keystore contains 1 entry
# idol-nifi, Jan 1, 2025, PrivateKeyEntry,
# Certificate fingerprint (SHA-256): ...


# --> If the password is **incorrect**, you'll get:
# keytool error: java.io.IOException: Keystore was tampered with, or password was incorrect