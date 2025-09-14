#!/bin/sh
clear
echo "--------------------------------------------------------------------"
echo "OpenText IDOL server - License Server"
echo "--------------------------------------------------------------------"
echo "This script will stop License Server"
echo "(licenseserver.exe)"
echo ""
echo "Hit return to continue"
echo "Hit Ctrl-C to end this script now!"
echo "--------------------------------------------------------------------"
read DUMMY
echo "Stopping License Server..."
if [ -f licenseserver.pid ]
then
  kill -15 `cat licenseserver.pid`
  echo "Stopped License Server"
else
  echo "Could not locate licenseserver.pid - unable to stop License Server"
fi 

