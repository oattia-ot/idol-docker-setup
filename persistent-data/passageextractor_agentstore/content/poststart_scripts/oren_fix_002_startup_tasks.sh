#!/bin/bash

# Source the same utilities used by healthcheck.sh
source ./utilities/utils.sh

if [[ -z ${IDOL_SSL} ]]; then
    HTTP_SCHEME=http
else
    HTTP_SCHEME=https
fi

# Derive ACI port dynamically from IDOL_PORTS env var (same as healthcheck.sh)
ACI_PORT=$(echo ${IDOL_PORTS} | awk -F' ' '{print $1}')

function wait_for_aci_service {
    local HOST=$1
    local PORT=$2
    local SLEEP_TIME=$3
    local MAX_RETRIES=$4
    local RETRIES=0
    echo "Waiting for ACI service on ${HOST}:${PORT}..."
    while :
    do
        if [ ! $RETRIES -lt $MAX_RETRIES ]; then
            echo "Timeout while waiting for ACI service on ${HOST}:${PORT}"
            exit 1
        fi
        HTTP_STATUS="$(ping_endpoint "${HTTP_SCHEME}://${HOST}:${PORT}/a=getpid" || true)"
        if [ -z "$HTTP_STATUS" ] || [ "$HTTP_STATUS" = "000" ]; then
            sleep $SLEEP_TIME
            RETRIES=$((RETRIES+1))
            continue
        else
            echo "ACI service on ${HOST}:${PORT} is available (HTTP ${HTTP_STATUS})"
            break
        fi
    done
}

wait_for_aci_service localhost ${ACI_PORT} 1 60

for i in $(ls idx/*.idx.gz 2>/dev/null); do
    if [ ! -e $i.indexed ]; then
        echo "Indexing $i"
        ping_endpoint "${HTTP_SCHEME}://localhost:${ACI_PORT}/DREADD?/content/$i" > /dev/null
        touch $i.indexed
    fi
done
rm -f doc.txt*