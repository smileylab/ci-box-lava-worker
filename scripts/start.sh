#!/bin/bash

/setup.sh || exit $?

# Set LAVA Master IP
if [[ -n "$LAVA_MASTER" ]]; then
	sed -i -e "s/{LAVA_MASTER}/$LAVA_MASTER/g" /etc/lava-dispatcher/lava-slave
fi

echo "LOGFILE=/var/log/lava-dispatcher/lava-slave.log" >> /etc/lava-dispatcher/lava-slave


echo "===== Start tftpd service ($0) ====="
service tftpd-hpa start || exit 4

echo "===== ser2net service ($0) ====="
if [ -s /etc/ser2net.yaml ]; then
	service ser2net start || exit 7
fi

echo "===== Start conmux registry ($0) ====="
touch /var/run/conmux-registry
/usr/sbin/conmux-registry 63000 /var/run/conmux-registry&
sleep 2
for item in $(ls /etc/conmux/*cf)
do
	echo "Add $item"
	# On some OS, the rights/user from host are not duplicated on guest
	grep -o '/dev/[a-zA-Z0-9_-]*' $item | xargs chown uucp
	/usr/sbin/conmux $item &
done

# start an http file server for boot/transfer_overlay support
echo "===== Start python3 http server ($0) ====="
(cd /var/lib/lava/dispatcher; python3 -m http.server 80) &

# FIXME lava-slave does not run if old pid is present
rm -f /var/run/lava-slave.pid
#service lava-slave start || exit 5
#/etc/init.d/lava-slave start

/root/entrypoint.sh

sleep 3650d
