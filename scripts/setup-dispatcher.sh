#!/bin/bash

CONF_PATH="$(find /etc -type d -name lava-dispatcher | head -1)"
if [ -z $CONF_PATH -o ! -d $CONF_PATH -o -n "${LAVA_VERSION}" ]; then
	CONF_PATH="/root"
fi

source ${CONF_PATH}/setupenv

if [ ! -e "${CONF_PATH}/devices/$(hostname)" ];then
	echo "Static slave setting for $LAVA_MASTER ($LAVA_MASTER_URI)"
	exit 0
fi

if [ -z "$LAVA_MASTER_URI" ];then
	echo "ERROR: Missing LAVA_MASTER_URI"
	exit 11
fi

echo "===== ssh key scan for pdu server ($0) ====="
if ping -c 3 ${LAVA_PDU_SERVER}; then
	ssh-keygen -f ~/.ssh/known_hosts -R ${LAVA_PDU_SERVER}
	ssh-keyscan ${LAVA_PDU_SERVER} >> ~/.ssh/known_hosts
fi

echo "===== Handle lava identify ($0) ====="
lavacli identities add --uri $LAVA_MASTER_BASEURI --token $LAVA_MASTER_TOKEN --username $LAVA_MASTER_USER default

echo "Dynamic slave setting for $LAVA_MASTER ($LAVA_MASTER_URI)"
LAVACLIOPTS="--uri $LAVA_MASTER_URI"

# do a sort of ping for letting master to be up
TIMEOUT=1200
while [ $TIMEOUT -ge 1 ];
do
	STEP=2
	lavacli $LAVACLIOPTS device-types list >/dev/null
	if [ $? -eq 0 ];then
		TIMEOUT=0
	else
		echo "Wait for master.... (${TIMEOUT}s remains)"
		sleep $STEP
	fi
	TIMEOUT=$(($TIMEOUT-$STEP))
done

echo "===== Handle device types ($0) ====="
# This directory is used for storing device-types already added
mkdir -p ${CONF_PATH}/.lavadocker/
if [ -e ${CONF_PATH}/device-types ];then
	for i in $(ls ${CONF_PATH}/device-types/*jinja2)
	do
		devicetype=$(basename $i |sed 's,.jinja2,,')
		echo "Adding custom $devicetype"
		lavacli $LAVACLIOPTS device-types list || exit $?
		touch ${CONF_PATH}/.lavadocker/devicetype-$devicetype
	done
fi

lavacli $LAVACLIOPTS device-types list > /tmp/device-types.list
if [ $? -ne 0 ];then
	echo "ERROR: fail to list device-types"
	exit 1
fi
lavacli $LAVACLIOPTS devices list -a > /tmp/devices.list
if [ $? -ne 0 ];then
	echo "ERROR: fail to list devices"
	exit 1
fi

echo "===== Handle worker ($0) ====="
for worker in $(ls ${CONF_PATH}/devices/)
do
	lavacli $LAVACLIOPTS workers list | grep -q $worker
	if [ $? -eq 0 ];then
		echo "Remains of $worker on lava-server, cleaning it"
		/usr/local/bin/retire.sh $LAVA_MASTER_URI $worker
		#lavacli $LAVACLIOPTS workers update $worker || exit $?
	else
		echo "Adding worker $worker to lava-server"
		lavacli $LAVACLIOPTS workers add --description "LAVA dispatcher on $(cat ${CONF_PATH}/phyhostname)" $worker || exit $?
	fi
	# worker need a token because we ran 2020.09+
	if [ -f ${CONF_PATH}/entrypoint.sh ]; then
		grep -q "TOKEN" ${CONF_PATH}/entrypoint.sh
	elif [ -f ${CONF_PATH}/lava-worker ]; then
		grep -q "TOKEN" ${CONF_PATH}/lava-worker
	fi
	if [ $? -eq 0 ];then
		# This is 2020.09+
		echo "DEBUG: Worker need a TOKEN"
		if [ -z "$LAVA_WORKER_TOKEN" ];then
			echo "DEBUG: get token dynamicly"
			# Does not work on 2020.09, since token was not added yet in RPC2
			WTOKEN=$(python3 /usr/local/bin/getworkertoken.py $LAVA_MASTER_URI $worker)
			if [ $? -ne 0 ];then
				echo "ERROR: cannot get WORKER TOKEN"
				exit 1
			fi
			if [ -z "$WTOKEN" ];then
				echo "ERROR: got an empty token"
				exit 1
			fi
		else
			echo "DEBUG: got token from env"
			WTOKEN=$LAVA_WORKER_TOKEN
		fi
		echo "DEBUG: write token to /var/lib/lava/dispatcher/worker/token"
		mkdir -p /var/lib/lava/dispatcher/worker/
		echo "$WTOKEN" > /var/lib/lava/dispatcher/worker/token
		# lava worker need to run under root permission
		chown root:root /var/lib/lava/dispatcher/worker/token
		chmod 640 /var/lib/lava/dispatcher/worker/token
		sed -i "s,.*TOKEN.*,TOKEN=\"--token-file /var/lib/lava/dispatcher/worker/token\"," /etc/lava-dispatcher/lava-worker || exit $?

		echo "DEBUG: set master URL to $LAVA_MASTER_URL"
		sed -i "s,^# URL.*,URL=\"$LAVA_MASTER_URL\"," /etc/lava-dispatcher/lava-worker || exit $?
		cat /etc/lava-dispatcher/lava-worker
	else
		echo "DEBUG: Worker does not need a TOKEN"
	fi
	if [ ! -z "$LAVA_DISPATCHER_IP" ];then
		echo "Add dispatcher_ip $LAVA_DISPATCHER_IP to $worker on lava-server"
		python3 /usr/local/bin/setdispatcherip.py $LAVA_MASTER_URI $worker $LAVA_DISPATCHER_IP || exit $?
	fi
	echo "===== Handle devices for $worker ($0) ====="
	for device in $(ls ${CONF_PATH}/devices/$worker/)
	do
		devicename=$(echo $device | sed 's,.jinja2,,')
		devicetype=$(grep -h extends ${CONF_PATH}/devices/$worker/$device | grep -o '[a-zA-Z0-9_-]*.jinja2' | sed 's,.jinja2,,')
		if [ -e ${CONF_PATH}/.lavadocker/devicetype-$devicetype ]; then
			echo "Skip devicetype $devicetype"
		else
			echo "Add devicetype $devicetype"
			grep -q "$devicetype[[:space:]]" /tmp/device-types.list
			if [ $? -eq 0 ];then
				echo "Skip devicetype $devicetype"
			else
				lavacli $LAVACLIOPTS device-types add $devicetype || exit $?
			fi
			touch ${CONF_PATH}/.lavadocker/devicetype-$devicetype
		fi
		DEVICE_OPTS=""
		if [ -e ${CONF_PATH}/deviceinfo/$devicename ];then
			echo "Found customization for $devicename"
			. ${CONF_PATH}/deviceinfo/$devicename
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
			lavacli $LAVACLIOPTS devices show $devicename | grep ^worker > /tmp/current-worker
			if [ $? -ne 0 ]; then
				CURR_WORKER=""
			else
				CURR_WORKER=$(cat /tmp/current-worker | sed 's,^.* ,,')
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
			lavacli $LAVACLIOPTS devices dict set $devicename ${CONF_PATH}/devices/$worker/$device || exit $?
		else
			lavacli $LAVACLIOPTS devices add --type $devicetype --worker $worker $DEVICE_OPTS $devicename || exit $?
			lavacli $LAVACLIOPTS devices dict set $devicename ${CONF_PATH}/devices/$worker/$device || exit $?
		fi
		if [ -e ${CONF_PATH}/tags/$devicename ];then
			while read tag
			do
				echo "DEBUG: Add tag $tag to $devicename"
				lavacli $LAVACLIOPTS devices tags add $devicename $tag || exit $?
			done < ${CONF_PATH}/tags/$devicename
		fi
	done
done

echo "===== Handle alias for device types ($0) ====="
for devicetype in $(ls ${CONF_PATH}/aliases/)
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
	done < ${CONF_PATH}/aliases/$devicetype
done

exit 0
