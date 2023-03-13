#!/bin/bash -x

extra_pkgs=${2:-sudo iputils-ping task-spooler sshpass flashrom nbd-server telnet ser2net dnsmasq nftables tftpd-hpa u-boot-tools}

#check for root
BEROOT=""
if [ $(id -u) -ne 0 ];then
    BEROOT=sudo
fi

#
# install lava via apt repository
#
$BEROOT apt install -y --no-install-recommends wget gnupg2
$BEROOT wget -O - https://apt.lavasoftware.org/lavasoftware.key.asc | apt-key add -
$BEROOT echo "deb https://apt.lavasoftware.org/release bullseye main" > /etc/apt/sources.list.d/lava.list
$BEROOT apt update && apt install -y --no-install-recommends $extra_pkgs

pushd $(dirname $0)

# configure lava dispatcher
if [ -d ./configs ]; then
	echo "Setup Lava-dispatcher configuration"

	$BEROOT apt install -y --no-install-recommends lava-dispatcher lavacli

	# copy lava-worker configuration to default location at /etc/lava-dispatcher/
	$BEROOT mkdir -p /etc/lava-dispatcher
	if [ -f ./configs/lava-worker ]; then
		$BEROOT cp -f ./configs/lava-worker /etc/lava-dispatcher/
	fi
	# copy phyhostname
	if [ -f ./configs/phyhostname ]; then
		$BEROOT cp -f ./configs/phyhostname /etc/lava-dispatcher/
		# modify the hostname of the debian machine
		FQDN=$(cat ./configs/phyhostname)
		OLDNAME=$(cat /etc/hostname)
		sed -e "s,${OLDNAME},${FQDN/%.*},g" -i /etc/hosts
		$BEROOT echo "${FQDN/%.*}" > /etc/hostname
	fi
	# copy setupenv
	if [ -f ./configs/setupenv ]; then
		$BEROOT cp -f ./configs/setupenv /etc/lava-dispatcher/
	fi
	# for lava-server: copy devices configuration to default location at /etc/lava-server/dispatcher-config/devices/
	# for lava-dispatcher: copy devices configuration to default location at /etc/lava-dispatcher/devices/
	if [ -d ./configs/devices/ ]; then
		$BEROOT mkdir -p /etc/lava-dispatcher/devices
		mv -f ./configs/devices/* /etc/lava-dispatcher/devices/
#		for dev in ./configs/devices/*; do
#			$BEROOT mkdir -p /etc/lava-dispatcher/devices/${dev//.*\//}
#			$BEROOT cp -rf ${dev} ${HOME}/devices/
#		done
	fi
	if [ -d ./configs/device-types/ ]; then
		$BEROOT mkdir -p /etc/lava-dispatcher/device-types
		$BEROOT mv -f ./configs/device-types/* /etc/lava-dispatcher/device-types/
	fi
	if [ -d ./configs/deviceinfo/ ]; then
		$BEROOT mkdir -p /etc/lava-dispatcher/deviceinfo
		$BEROOT mv -f ./configs/deviceinfo/* /etc/lava-dispatcher/deviceinfo/
	fi
	if [ -d ./configs/tags/ ]; then
		$BEROOT mkdir -p /etc/lava-dispatcher/tags
		$BEROOT mv -f ./configs/tags/* /etc/lava-dispatcher/tags/
	fi
	if [ -d ./configs/aliases/ ]; then
		$BEROOT mkdir -p /etc/lava-dispatcher/aliases
		$BEROOT mv -f ./configs/aliases/* /etc/lava-dispatcher/aliases/
	fi

	# copy additional scripts to appropriate locations
	if [ -d ./scripts ]; then
		if [ -f ./scripts/retire.sh ]; then
			$BEROOT chmod a+x ./scripts/retire.sh && $BEROOT cp -f ./scripts/retire.sh /usr/local/bin
		fi
		if [ -f ./scripts/getworkertoken.py ]; then
			$BEROOT chmod a+x ./scripts/getworkertoken.py && $BEROOT cp -f ./scripts/getworkertoken.py /usr/local/bin
		fi
		if [ -f ./scripts/setdispatcherip.py ]; then
			$BEROOT chmod a+x ./scripts/setdispatcherip.py && $BEROOT cp -f ./scripts/setdispatcherip.py /usr/local/bin
		fi
	fi

	# copy ser2net settings for debug console to DUT
	if [ -f ./configs/ser2net.yaml ]; then
		if [ -f /etc/ser2net.yaml ]; then
			$BEROOT systemctl stop ser2net.service
			$BEROOT systemctl disable ser2net.service
			$BEROOT mv -f /etc/ser2net.yaml /etc/ser2net.yaml~
		fi
		$BEROOT cp -f ./configs/ser2net.yaml /etc/ser2net.yaml
		$BEROOT systemctl enable ser2net.service
		$BEROOT systemctl restart ser2net.service
	fi

	# update tftpd-hpa config, cannot use dnsmasq as tftpd, because lava-dispatcher controls tftpd-hpa
	if [ -f ./configs/tftpd-hpa ]; then
		if [ -f /etc/default/tftpd-hpa ]; then
			$BEROOT systemctl stop tftpd-hpa.service
			$BEROOT mv -f /etc/default/tftpd-hpa /etc/default/tftpd-hpa~
		fi
		$BEROOT cp -f ./configs/tftpd-hpa /etc/default/tftpd-hpa
		$BEROOT systemctl restart tftpd-hpa.service
	fi

	# modify nbd ports for network block device, avoid linux dynamic port range: 32768-60999
	find /usr/lib/python3/dist-packages/lava_common/ -iname constants.py | xargs $BEROOT sed -i 's,XNBD_PORT_RANGE_MIN.*,XNBD_PORT_RANGE_MIN=61950,'
	find /usr/lib/python3/dist-packages/lava_common/ -iname constants.py | xargs $BEROOT sed -i 's,XNBD_PORT_RANGE_MAX.*,XNBD_PORT_RANGE_MAX=62000,'

	# BIOS PXE booting, copy grub.cfg to /boot/grub of tftpd and intel.efi to tftpd rootdir
	#$BEROOT apt install grub-efi-amd64-bin:amd64
	if [ -d /srv/tftp ]; then
		$BEROOT rm -rf /srv/tftp/boot
	fi
	$BEROOT mkdir -p /srv/tftp
	$BEROOT grub-mknetdir --net-directory=/srv/tftp
	if [ -f ./configs/grub.cfg ]; then
		$BEROOT cp -f ./configs/grub.cfg /srv/tftp/boot/grub/
	fi
	if [ -f ./configs/intel.efi ]; then
		$BEROOT cp -f ./configs/intel.efi /srv/tftp/intel.efi
	fi
	if [ -f ./configs/snp.efi ]; then
		$BEROOT cp -f ./configs/snp.efi /srv/tftp/snp.efi
	fi
	if [ -f ./configs/snponly.efi ]; then
		$BEROOT cp -f ./configs/snponly.efi /srv/tftp/snponly.efi
	fi

	################################################################################
	# network setting for DUT and NAT of Brideged vNICs. *necessary for VM
	################################################################################
	# 1. vNICs setup for enp0s3 (bridged from Host WIFI network adaptor)
	if [ -f ./configs/wifi-bridge.network ]; then
		if [ -f /etc/systemd/network/wifi-bridge.network ]; then
			$BEROOT mv -f /etc/systemd/network/wifi-bridge.network /etc/systemd/network/wifi-bridge.network~
		fi
		$BEROOT cp -f ./configs/wifi-bridge.network /etc/systemd/network/
	fi
	# 2. vNICs setup for enp0s8 (bridged Host ethernet adaptor to DUT) packets allowd to VM
	if [ -f ./configs/eth-bridge.network ]; then
		if [ -f /etc/systemd/network/eth-bridge.network ]; then
			$BEROOT mv -f /etc/systemd/network/eth-bridge.network /etc/systemd/network/eth-bridge.network~
		fi
		$BEROOT cp -f ./configs/eth-bridge.network /etc/systemd/network/
	fi
	$BEROOT systemctl restart systemd-networkd.service

	# 3. install and setup dnsmasq to enable dhcp, dns and tftp for DUT bridged network
	if [ -f ./configs/alternative.conf ]; then
		if [ -f /etc/dnsmasq.d/alternative.conf ]; then
			$BEROOT systemctl stop dnsmasq.service
			$BEROOT systemctl disable dnsmasq.service
			$BEROOT mv -f /etc/dnsmasq.d/alternative.conf /etc/dnsmasq.d/alternative.conf~
		fi
		$BEROOT cp -f ./configs/alternative.conf /etc/dnsmasq.d/
		$BEROOT rm -f /etc/resolv.conf && echo "nameserver 127.0.0.1" | $BEROOT tee /etc/resolv.conf
		$BEROOT systemctl stop systemd-resolved.service
		$BEROOT systemctl disable systemd-resolved.service
		$BEROOT systemctl enable dnsmasq.service
		$BEROOT systemctl restart dnsmasq.service
	fi
	# 4. nft (netfilter table / iptable) setting to forward packets from enp0s8 to enp0s3
	# and masquerade forwarded packets
	if [ -f ./configs/nftables.conf ]; then
		if [ -f /etc/nftables.conf ]; then
			$BEROOT systemctl stop nftables.service
			$BEROOT systemctl disable nftables.service
			$BEROOT mv -f /etc/nftables.conf /etc/nftables.conf~
		fi
		$BEROOT cp -f ./configs/nftables.conf /etc/
		$BEROOT systemctl enable nftables.service
		$BEROOT systemctl restart nftables.service
	fi
	# 5. enable sysctl ip forward
	if [ -f /etc/sysctl.conf ]; then
		$BEROOT sed -e 's,#net.ipv4.ip_forward=1,net.ipv4.ip_forward=1,g' -i /etc/sysctl.conf
		$BEROOT sysctl -p
	fi

	# 6. restart lava-worker by running setup-dispatcher.sh first
	if [ -f ./scripts/setup-dispatcher.sh -a -f /lib/systemd/system/lava-worker.service ]; then
		$BEROOT systemctl stop lava-worker.service
		$BEROOT systemctl disable lava-worker.service
		$BEROOT chmod a+x ./scripts/setup-dispatcher.sh && cp -f ./scripts/setup-dispatcher.sh /etc/lava-dispatcher/
		if ! grep -q "ExecStartPre=.*setup-dispatcher.sh" /lib/systemd/system/lava-worker.service; then
			$BEROOT sed -e 's,ExecStart,ExecStartPre=/etc/lava-dispatcher/setup-dispatcher.sh\nExecStart,g' -i /lib/systemd/system/lava-worker.service
		fi
	fi
	$BEROOT systemctl enable lava-worker.service
	$BEROOT systemctl restart lava-worker.service
else
	echo "No configs for Lava-dispatcher configuration"
	popd
	exit 1
fi

popd

