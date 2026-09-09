#!/bin/bash
# Install custom CA into RHEL system trust store
if [ -f /etc/pki/ca-trust/source/anchors/idol-ca-chain.pem ]; then
    update-ca-trust extract
    echo "✓ IDOL CA installed into system trust store"
fi
