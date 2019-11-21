#!/bin/bash

echo "===== Start Services ====="

# start tftpd service
if [ -s /etc/default/tftpd-hpa ]; then
	echo " Start tftpd service..."
	service tftpd-hpa start || exit 4
fi

# start ser2net service
if [ -s /etc/ser2net.conf ]; then
	echo " Start ser2net service..."
	service ser2net start || exit 7
fi

# start conmux service
if [ -x /usr/sbin/conmux-registry -a -x /usr/sbin/conmux ]; then
	echo " Start conmux service..."
	touch /var/run/conmux-registry
	/usr/sbin/conmux-registry 63000 /var/run/conmux-registry &
	sleep 2
	for item in $(ls /etc/conmux/*cf)
	do
		echo "Add $item"
		# On some OS, the rights/user from host are not duplicated on guest
		grep -o '/dev/[a-zA-Z0-9_-]*' $item | xargs chown uucp
		/usr/sbin/conmux $item &
	done
fi

# start screen service over xterm / ssh
if [ -s /root/lava-screen.conf ]; then
	echo " Start screen service..."
	HAVE_SCREEN=0
	while read screenboard
	do
		echo "Start screen for $screenboard"
		TERM=xterm screen -d -m -S $screenboard /dev/$screenboard 115200 -ixoff -ixon || exit 9
		HAVE_SCREEN=1
	done < /root/lava-screen.conf
	if [ $HAVE_SCREEN -eq 1 ]; then
		sed -i 's,UsePAM.*yes,UsePAM no,' /etc/ssh/sshd_config || exit 10
		service ssh start || exit 11
	fi
fi

# start an http file server for boot/transfer_overlay support
if [ -d /var/lib/lava/dispatcher ]; then
	echo " Start httpd service... (on /var/lib/lava/dispatcher/)"
	(cd /var/lib/lava/dispatcher; python3 -m http.server 80) &
fi

# FIXME lava-slave does not run if old pid is present
rm -f /var/run/lava-slave.pid
exit 0

