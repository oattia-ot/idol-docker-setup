#!/bin/bash

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