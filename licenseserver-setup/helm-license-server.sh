#!/bin/bash

helm install idol-licenseserver ./idol-containers-toolkit/helm/idol-licenseserver --set licenseServerIp=127.0.0.1 --set licenseServerExternalName=null