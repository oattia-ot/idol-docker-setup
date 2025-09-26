#!/bin/sh
LD_LIBRARY_PATH=./:../bin:./ffmpeg:./filters:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH
clear
echo "--------------------------------------------------------------------"
echo "OpenText License Server"
echo "Copyright 1999-2023 Open Text"
echo "--------------------------------------------------------------------"
echo "This script will start License Server"
echo "(licenseserver.exe)"
echo ""
echo "Hit return to continue"
echo "Hit Ctrl-C to end this script now!"
echo "--------------------------------------------------------------------"
echo "Starting License Server..."
cd /LicenseServer_25.3.0_LINUX_X86_64
chmod u+x licenseserver.exe
./licenseserver.exe
