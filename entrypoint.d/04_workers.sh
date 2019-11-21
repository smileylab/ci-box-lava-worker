#!/bin/bash

echo "===== Handle workers ====="

if [ -z "$LAVA_MASTER_URI" ];then
	echo "ERROR: Missing LAVA_MASTER_URI"
	exit 11
fi
LAVACLIOPTS="--uri $LAVA_MASTER_URI"

for worker in $(ls /root/devices/)
do
	lavacli $LAVACLIOPTS workers list |grep -q $worker
	if [ $? -eq 0 ];then
		echo "Remains of $worker, cleaning it"
		/usr/local/bin/retire.sh $LAVA_MASTER_URI $worker
		#lavacli $LAVACLIOPTS workers update $worker || exit $?
	else
		echo "Adding worker $worker"
		lavacli $LAVACLIOPTS workers add --description "LAVA dispatcher on $(cat /root/phyhostname)" $worker || exit $?
	fi
	if [ ! -z "$LAVA_DISPATCHER_IP" ];then
		echo "Add dispatcher_ip $LAVA_DISPATCHER_IP to $worker"
		/usr/local/bin/setdispatcherip.py $LAVA_MASTER_URI $worker $LAVA_DISPATCHER_IP || exit $?
	fi
	for device in $(ls /root/devices/$worker/)
	do
		devicename=$(echo $device | sed 's,.jinja2,,')
		devicetype=$(grep -h extends /root/devices/$worker/$device| grep -o '[a-zA-Z0-9_-]*.jinja2' | sed 's,.jinja2,,')
		if [ -e /root/.lavadocker/devicetype-$devicetype ];then
			echo "Skip devicetype $devicetype"
		else
			echo "Add devicetype $devicetype"
			grep -q "$devicetype[[:space:]]" /tmp/device-types.list
			if [ $? -eq 0 ];then
				echo "Skip devicetype $devicetype"
			else
				lavacli $LAVACLIOPTS device-types add $devicetype || exit $?
			fi
			touch /root/.lavadocker/devicetype-$devicetype
		fi
		DEVICE_OPTS=""
		if [ -e /root/deviceinfo/$devicename ];then
			echo "Found customization for $devicename"
			. /root/deviceinfo/$devicename
			if [ ! -z "$DEVICE_USER" ];then
				echo "DEBUG: give $devicename to $DEVICE_USER"
				DEVICE_OPTS="$DEVICE_OPTS --user $DEVICE_USER"
			fi
			if [ ! -z "$DEVICE_GROUP" ];then
				echo "DEBUG: give $devicename to group $DEVICE_GROUP"
				DEVICE_OPTS="$DEVICE_OPTS --group $DEVICE_GROUP"
			fi
		fi
		echo "Add device $devicename on $worker"
		grep -q "$devicename[[:space:]]" /tmp/devices.list
		if [ $? -eq 0 ];then
			echo "$devicename already present"
			#verify if present on another worker
			lavacli $LAVACLIOPTS devices show $devicename |grep ^worker > /tmp/current-worker
			if [ $? -ne 0 ]; then
				CURR_WORKER=""
			else
				CURR_WORKER=$(cat /tmp/current-worker | sed '^.* ,,')
			fi
			if [ ! -z "$CURR_WORKER" -a "$CURR_WORKER" != "$worker" ];then
				echo "ERROR: $devicename already present on another worker $CURR_WORKER"
				exit 1
			fi
			DEVICE_HEALTH=$(grep "$devicename[[:space:]]" /tmp/devices.list | sed 's/.*,//')
			case "$DEVICE_HEALTH" in
			Retired)
				echo "DEBUG: Keep $devicename state: $DEVICE_HEALTH"
				DEVICE_HEALTH='RETIRED'
			;;
			Maintenance)
				echo "DEBUG: Keep $devicename state: $DEVICE_HEALTH"
				DEVICE_HEALTH='MAINTENANCE'
			;;
			*)
				echo "DEBUG: Set $devicename state to UNKNOWN (from $DEVICE_HEALTH)"
				DEVICE_HEALTH='UNKNOWN'
			;;
			esac
			lavacli $LAVACLIOPTS devices update --worker $worker --health $DEVICE_HEALTH $DEVICE_OPTS $devicename || exit $?
			# always reset the device dict in case of update of it
			lavacli $LAVACLIOPTS devices dict set $devicename /root/devices/$worker/$device || exit $?
		else
			lavacli $LAVACLIOPTS devices add --type $devicetype --worker $worker $DEVICE_OPTS $devicename || exit $?
			lavacli $LAVACLIOPTS devices dict set $devicename /root/devices/$worker/$device || exit $?
		fi
		if [ -e /root/tags/$devicename ];then
			while read tag
			do
				echo "DEBUG: Add tag $tag to $devicename"
				lavacli $LAVACLIOPTS devices tags add $devicename $tag || exit $?
			done < /root/tags/$devicename
		fi
	done
done
exit 0
