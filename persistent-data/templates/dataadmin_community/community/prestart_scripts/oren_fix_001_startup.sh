#!/bin/bash

source /community/startup_utils.sh

COMMUNITY_PORT=DA_COMMUNITY_ACI_PLACEHOLDER

# FIX: use correct env var names (IDOL_AGENTSTORE_PORT not IDOL_AGENTSTORE_ACI_PORT)
_IDOL_CONTENT_HOST=${IDOL_CONTENT_HOST:-idol-content}
_IDOL_CONTENT_PORT=${PORT_DATA_ADMIN_PASSAGE_CONTENT:-DA_PASSAGEEXTRATOR_CONTENT_ACI_PLACEHOLDER}
_IDOL_AGENTSTORE_HOST=${IDOL_AGENTSTORE_HOST:-idol-agentstore}
_IDOL_AGENTSTORE_PORT=${PORT_DATA_ADMIN_QMS_AGENTSTORE:-DA_QMS_AGENTSTORE_ACI_PLACEHOLDER}

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

function finalizeConfigFile {
    sed -i "s/XX_IDOL_AGENTSTORE_HOST_XX/${_IDOL_AGENTSTORE_HOST}/g" /community/cfg/community.cfg
    sed -i "s/XX_IDOL_AGENTSTORE_PORT_XX/${_IDOL_AGENTSTORE_PORT}/g" /community/cfg/community.cfg
    sed -i "s/XX_IDOL_CONTENT_HOST_XX/${_IDOL_CONTENT_HOST}/g" /community/cfg/community.cfg
    sed -i "s/XX_IDOL_CONTENT_PORT_XX/${_IDOL_CONTENT_PORT}/g" /community/cfg/community.cfg
}

checkAesKeyfile
waitForAci $_IDOL_CONTENT_HOST:$_IDOL_CONTENT_PORT
waitForAci $_IDOL_AGENTSTORE_HOST:$_IDOL_AGENTSTORE_PORT
finalizeConfigFile