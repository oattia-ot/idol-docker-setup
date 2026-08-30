#!/bin/bash

source /community/startup_utils.sh

# ===================================================================
# Environment variable fallbacks (exactly like the community script)
# ===================================================================
_IDOL_FACTBANK_POSTGRES_HOST=${IDOL_FACTBANK_POSTGRES_HOST:-idol-factbank-postgres}
_IDOL_FACTBANK_POSTGRES_PORT=${PORT_DATA_ADMIN_FACTBANK_POSTGRES:-5432}
_IDOL_FACTBANK_USER=${IDOL_FACTBANK_USER:-postgres}
_IDOL_FACTBANK_DBNAME=${IDOL_FACTBANK_DBNAME:-factbank-data}
_IDOL_FACTBANK_PASSWORD=${IDOL_FACTBANK_PASSWORD:-password}

_IDOL_ANSWERBANK_AGENTSTORE_HOST=${IDOL_ANSWERBANK_AGENTSTORE_HOST:-idol-answerbank-agentstore}
_IDOL_ANSWERBANK_AGENTSTORE_PORT=${PORT_DATA_ADMIN_ANSWERBANK_AGENTSTORE:-12200}

_IDOL_PASSAGEEXTRACTOR_CONTENT_HOST=${IDOL_PASSAGEEXTRACTOR_CONTENT_HOST:-idol-passageextractor-content}
_IDOL_PASSAGEEXTRACTOR_CONTENT_PORT=${PORT_DATA_ADMIN_PASSAGEEXTRACTOR_CONTENT:-9100}
_IDOL_PASSAGEEXTRACTOR_AGENTSTORE_HOST=${IDOL_PASSAGEEXTRACTOR_AGENTSTORE_HOST:-idol-passageextractor-agentstore}
_IDOL_PASSAGEEXTRACTOR_AGENTSTORE_PORT=${PORT_DATA_ADMIN_PASSAGEEXTRACTOR_AGENTSTORE:-12310}

_IDOL_LICENSESERVER_HOST=${IDOL_LICENSESERVER_HOST:-idol-licenseserver}
_IDOL_LICENSESERVER_PORT=${PORT_DATA_ADMIN_LICENSESERVER:-20000}

# HTTPS control (set this env var to true in your Docker Compose / deployment)
USE_HTTPS=${USE_HTTPS:-false}
SSL_CONFIG_NAME="IDOLSSLConfig"

CONFIG_FILE="/community/cfg/answerserver.cfg"

# ===================================================================
# Original wait_for_pg_isready function (unchanged)
# ===================================================================
function wait_for_pg_isready {
    local HOST=$1
    local PORT=$2
    local USER=$3
    local DBNAME=$4
    local SLEEP_TIME=$5
    local MAX_RETRIES=$6

    echo "Waiting for postgres DB $DBNAME on $HOST:$PORT"

    local RETRIES=0

    while :
    do
        if [ ! $RETRIES -lt $MAX_RETRIES ]
        then
            echo "Timeout while waiting for postgres $DBNAME on $HOST:$PORT"
            exit 1
        fi

        /usr/pgsql-14/bin/pg_isready -d $DBNAME -h $HOST -p $PORT -U $USER --quiet
        case "$?" in
        0     ) return;;
        1 | 2 ) sleep $SLEEP_TIME; RETRIES=$((RETRIES+1));;
        3 | * ) exit 1;;
        esac
    done
}

# ===================================================================
# AES keyfile (required by every IDOL component)
# ===================================================================
function checkAesKeyfile() {
    if [ -e ./autpassword.exe ]
    then
        local AESKEYFILE=/community/cfg/aes.keyfile
        if [ -e $AESKEYFILE ]
        then
            echo "Found AES keyfile"
        else
            ./autpassword.exe -x -tAES -oKeyFile=$AESKEYFILE
        fi
    fi
}

# ===================================================================
# Finalize config – replaces ALL hardcoded values + enables HTTPS
# ===================================================================
function finalizeConfigFile {
    echo "Finalizing answerserver.cfg ..."

    # === Replace hardcoded hosts/ports (exact matches from your cfg) ===
    sed -i "s|idol-factbank-postgres|${_IDOL_FACTBANK_POSTGRES_HOST}|g" "$CONFIG_FILE"
    sed -i "s|Port=5432|Port=${_IDOL_FACTBANK_POSTGRES_PORT}|g" "$CONFIG_FILE"
    sed -i "s|Database=factbank-data|Database=${_IDOL_FACTBANK_DBNAME}|g" "$CONFIG_FILE"
    sed -i "s|Uid=postgres|Uid=${_IDOL_FACTBANK_USER}|g" "$CONFIG_FILE"
    sed -i "s|password=password|password=${_IDOL_FACTBANK_PASSWORD}|g" "$CONFIG_FILE"

    sed -i "s|idol-answerbank-agentstore|${_IDOL_ANSWERBANK_AGENTSTORE_HOST}|g" "$CONFIG_FILE"
    sed -i "s|IdolAciPort=12200|IdolAciPort=${_IDOL_ANSWERBANK_AGENTSTORE_PORT}|g" "$CONFIG_FILE"

    sed -i "s|idol-passageextractor-content|${_IDOL_PASSAGEEXTRACTOR_CONTENT_HOST}|g" "$CONFIG_FILE"
    sed -i "s|IdolAciPort=9100|IdolAciPort=${_IDOL_PASSAGEEXTRACTOR_CONTENT_PORT}|g" "$CONFIG_FILE"
    sed -i "s|idol-passageextractor-agentstore|${_IDOL_PASSAGEEXTRACTOR_AGENTSTORE_HOST}|g" "$CONFIG_FILE"
    sed -i "s|AgentstoreAciPort=12310|AgentstoreAciPort=${_IDOL_PASSAGEEXTRACTOR_AGENTSTORE_PORT}|g" "$CONFIG_FILE"

    sed -i "s|idol-licenseserver|${_IDOL_LICENSESERVER_HOST}|g" "$CONFIG_FILE"
    sed -i "s|LicenseServerACIPort=20000|LicenseServerACIPort=${_IDOL_LICENSESERVER_PORT}|g" "$CONFIG_FILE"

    # === HTTPS / SSL ENABLEMENT (this is the part you asked for) ===
    if [ "${USE_HTTPS}" = "true" ] || [ "${IDOL_USE_HTTPS}" = "true" ]; then
        echo "✅ Enabling HTTPS/SSL in answerserver.cfg"

        # Add SSLConfig reference to every ACI client section
        sed -i '/\[AnswerBank\]/a\IdolSSLConfig='"${SSL_CONFIG_NAME}" "$CONFIG_FILE"
        sed -i '/\[PassageExtractor\]/a\IdolSSLConfig='"${SSL_CONFIG_NAME}" "$CONFIG_FILE"
        sed -i '/\[RAG\]/a\IdolSSLConfig='"${SSL_CONFIG_NAME}" "$CONFIG_FILE"

        # Enable SSL on the answerserver itself (listening port)
        sed -i '/\[Server\]/a\SSLConfig='"${SSL_CONFIG_NAME}" "$CONFIG_FILE"

        # Append the IDOLSSLConfig section (only once)
        if ! grep -q "\[${SSL_CONFIG_NAME}\]" "$CONFIG_FILE"; then
            cat >> "$CONFIG_FILE" << EOF

# =============================================
# HTTPS/SSL configuration (added by startup script)
# =============================================
[${SSL_CONFIG_NAME}]
SSLEnabled=True
# CertificateFile=/community/cfg/ssl/server.crt
# PrivateKeyFile=/community/cfg/ssl/server.key
# CACertificateFile=/community/cfg/ssl/ca.crt
# You can mount your real certificates via Docker volume and update the paths above
EOF
        fi
    else
        echo "HTTPS/SSL disabled (set USE_HTTPS=true to enable)"
    fi

    echo "answerserver.cfg finalized"
}

# ===================================================================
# Main startup sequence (same order as community script)
# ===================================================================
checkAesKeyfile

# Wait for PostgreSQL
wait_for_pg_isready "$_IDOL_FACTBANK_POSTGRES_HOST" "$_IDOL_FACTBANK_POSTGRES_PORT" "$_IDOL_FACTBANK_USER" "$_IDOL_FACTBANK_DBNAME" 1 60

# Wait for the other IDOL components this service talks to (ACI)
waitForAci "${_IDOL_ANSWERBANK_AGENTSTORE_HOST}:${_IDOL_ANSWERBANK_AGENTSTORE_PORT}"
waitForAci "${_IDOL_PASSAGEEXTRACTOR_CONTENT_HOST}:${_IDOL_PASSAGEEXTRACTOR_CONTENT_PORT}"
# waitForAci for agentstore is optional – PassageExtractor already waits for it internally

finalizeConfigFile

echo "✅ answerserver startup tasks completed successfully"