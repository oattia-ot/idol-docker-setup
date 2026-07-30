#!/bin/bash

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
