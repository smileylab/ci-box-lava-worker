#!/bin/bash

echo "===== Handle devices ====="

if [ -z "$LAVA_MASTER_URI" ];then
	echo "ERROR: Missing LAVA_MASTER_URI"
	exit 11
fi
LAVACLIOPTS="--uri $LAVA_MASTER_URI"

# This directory is used for storing device-types already added
mkdir -p /root/.lavadocker/
if [ -e /root/device-types ];then
	for i in $(ls /root/device-types/*jinja2)
	do
		devicetype=$(basename $i |sed 's,.jinja2,,')
		echo "Adding custom $devicetype"
		lavacli $LAVACLIOPTS device-types list || exit $?
		touch /root/.lavadocker/devicetype-$devicetype
	done
fi

lavacli $LAVACLIOPTS device-types list > /tmp/device-types.list
if [ $? -ne 0 ];then
	exit 1
fi

lavacli $LAVACLIOPTS devices list -a > /tmp/devices.list
if [ $? -ne 0 ];then
	exit 1
fi
exit 0
