#!/bin/sh

docker network create idol-network 

docker compose -f $IDOL_LICENSE_SERVER_PATH/docker-compose.yml down

sudo rm $IDOL_LICENSE_SERVER_PATH/LicenseServer_25.3.0_LINUX_X86_64/licenseserver.lck
sudo rm -fr $IDOL_LICENSE_SERVER_PATH/LicenseServer_25.3.0_LINUX_X86_64/uid
sudo rm -fr $IDOL_LICENSE_SERVER_PATH/LicenseServer_25.3.0_LINUX_X86_64/license

docker compose -f $IDOL_LICENSE_SERVER_PATH/docker-compose.yml up -d --build licenseserver

sleep 3

curl http://localhost:20000/a=getlicenseinfo
