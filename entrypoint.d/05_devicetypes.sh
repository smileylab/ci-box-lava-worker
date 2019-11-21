#!/bin/bash

echo "===== Handle device types ====="

if [ -z "$LAVA_MASTER_URI" ];then
	echo "ERROR: Missing LAVA_MASTER_URI"
	exit 11
fi
LAVACLIOPTS="--uri $LAVA_MASTER_URI"

for devicetype in $(ls /root/aliases/)
do
	lavacli $LAVACLIOPTS device-types aliases list $devicetype > /tmp/device-types-aliases-$devicetype.list
	while read alias
	do
		grep -q " $alias$" /tmp/device-types-aliases-$devicetype.list
		if [ $? -eq 0 ];then
			echo "DEBUG: $alias for $devicetype already present"
			continue
		fi
		echo "DEBUG: Add alias $alias to $devicetype"
		lavacli $LAVACLIOPTS device-types aliases add $devicetype $alias || exit $?
		echo " $alias" >> /tmp/device-types-aliases-$devicetype.list
	done < /root/aliases/$devicetype
done
exit 0
