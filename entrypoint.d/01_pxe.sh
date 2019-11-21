#!/bin/bash

# check static slave for master
if [ ! -e "/root/devices/$(hostname)" ];then
	echo "Static slave for $LAVA_MASTER"
	exit 1
fi

# Install PXE
echo "===== Handle PXE (grub settings) ====="
OPWD=$(pwd)
cd /var/lib/lava/dispatcher/tmp && grub-mknetdir --net-directory=.
cp /root/grub.cfg /var/lib/lava/dispatcher/tmp/boot/grub/
cd $OPWD
exit 0
