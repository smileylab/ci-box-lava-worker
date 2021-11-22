#!/bin/bash

echo "===== Check for static slave hostname from /root/devices/ ====="

# check static slave for master
if [ ! -e "/root/devices/$(hostname)" ];then
	echo "ERROR: Specify static slave hostname for $LAVA_MASTER"
	exit 1
fi

# Install PXE
echo "===== Handle PXE (grub settings) ====="
OPWD=$(pwd)
cd /var/lib/lava/dispatcher/tmp && grub-mknetdir --net-directory=.
cp /root/grub.cfg /var/lib/lava/dispatcher/tmp/boot/grub/
cp /root/intel.efi /var/lib/lava/dispatcher/tmp/
cd $OPWD
exit 0
