#!/bin/sh

docker network create idol-licenseserver-network

docker compose stop licenseserver
docker compose rm -f licenseserver
docker compose build licenseserver
docker compose up -d licenseserver

sleep 3

curl http://localhost:20000/a=getlicenseinfo

