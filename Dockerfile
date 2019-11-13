# originally based on debian:stretch-slim
# with python3 debootstrap nfs-kernel-server qemu rpcbind ser2net telnet tftpd-hpa
# u-boot-tools docker-ce-cli img2simg simg2img, etc
ARG version=latest
ARG tgtplatform=linux/arm64
FROM --platform=${tgtplatform} lavasoftware/lava-dispatcher:${version}
WORKDIR /opt/
RUN apt -q update || apt -q update
RUN DEBIAN_FRONTEND=noninteractive apt-get -q -y install build-essential git pkg-config cmake libusb-dev libftdi-dev
RUN git clone https://github.com/96boards/96boards-uart.git
# Avoid using new libusb because of build-error
RUN cd 96boards-uart && git checkout 1d2bc993083d97b54d21ecdf72556066efce11f7
RUN cd 96boards-uart/96boardsctl/ && cmake . && make

FROM --platform=${tgtplatform} lavasoftware/lava-dispatcher:${version}

# setup extra packages for whatever reason
ARG extra_packages="git iputils-ping"
RUN apt-get -y -q update && apt-get -y -q --no-install-recommends install ${extra_packages}

COPY configs/ /root/configs/
# Old worker /etc/lava-worker/config file ( < ver2021 )
ARG version=latest
RUN echo "$version" && case ${version} in \
2021*) \
echo "ver${verion}: copy lava-worker to /etc/lava-dispatcher/lava-worker"; \
mv /root/configs/lava-worker /etc/lava-dispatcher/lava-worker; \
;; \
*) \
echo "ver${version}: copy lava-slave to /etc/lava-dispatcher/lava-slave"; \
mv /root/configs/lava-slave /etc/lava-dispatcher/lava-slave; \
;; \
esac;
RUN if [ -f /root/configs/tftpd-hpa ]; then mv /root/configs/tftpd-hpa /etc/default/tftpd-hpa; fi

# setup lava-coordinator
RUN if [ -f /root/etc/lava-coordinator/lava-coordinator.conf ]; then mkdir -p /etc/lava-coordinator && \
mv /root/configs/lava-coordinator/lava-coordinator.conf /etc/lava-coordinator && \
apt-get -y -q update && apt-get -y -q --no-install-recommends install lava-coordinator; fi

#
# Setup Tools for Serial Console Control for the DUTs
#
# SNMP MIBS for Networked PDU Control
# setup packages for using SNMP MIBS from non-free
RUN echo "deb http://http.us.debian.org/debian/ stable non-free" >> /etc/apt/sources.list.d/non-free.list
RUN apt-get -y -q update && apt-get -y -q --no-install-recommends install software-properties-common net-tools snmp snmp-mibs-downloader && rm /etc/apt/sources.list.d/non-free.list
RUN download-mibs
# Add MIBs for PowerNet428 (NetworkManagementCard 2 (NMC2)for ModularPDU)
RUN mkdir -p /usr/share/snmp/mibs/
ADD powernet428.mib /usr/share/snmp/mibs/
# Add lava-lab (public-shared) scripts for Networked PDU Control
ADD https://git.linaro.org/lava/lava-lab.git/plain/shared/lab-scripts/snmp_pdu_control /usr/local/bin/
RUN chmod a+x /usr/local/bin/snmp_pdu_control
ADD https://git.linaro.org/lava/lava-lab.git/plain/shared/lab-scripts/eth008_control /usr/local/bin/
RUN chmod a+x /usr/local/bin/eth008_control
#
# cu conmux (is for console via conmux),
# note: conmux need cu >= 1.07-24 See https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=336996
RUN if [ -n "$(ls -1 /root/configs/conmux)" ]; then mv configs/conmux/*.conf /etc/conmux/ && \
echo "deb http://deb.debian.org/debian/ testing main" >> /etc/apt/sources.list.d/testing.list && \
apt-get -y -q update && apt-get -y -q --no-install-recommends install cu conmux && rm /etc/apt/sources.list.d/testing.list; fi
#
# telnet (is for using ser2net)
# ser2net > 3.2 is only availlable from sid
RUN if [ -f /root/configs/ser2net.conf ]; then mv /root/configs/ser2net.conf /etc/ && \
echo "deb http://deb.debian.org/debian/ sid main" >> /etc/apt/sources.list.d/sid.list && \
apt-get -y -q update && apt-get -y -q --no-install-recommends install telnet ser2net && rm /etc/apt/sources.list.d/sid.list; fi && \
sed -e 's,ser2net.yaml,ser2net.conf,g' -i /etc/default/ser2net

# Caution to not use any port between the Linux dynamic port range: 32768-60999
# sed replaces values in lava_common/constants.py
RUN find /usr/lib/python3/dist-packages/ -iname constants.py | xargs sed -i 's,XNBD_PORT_RANGE_MIN.*,XNBD_PORT_RANGE_MIN=61950,'
RUN find /usr/lib/python3/dist-packages/ -iname constants.py | xargs sed -i 's,XNBD_PORT_RANGE_MAX.*,XNBD_PORT_RANGE_MAX=62000,'
#
# setup screen for terminal
RUN if [ -f /root/configs/lava-screen.conf ]; then mv /root/configs/lava-screen.conf /root/ && \
apt-get -y -q --no-install-recommends install screen; fi

# ssh keys
# setup ssh keys for PDU control over TechNexion's PowerControl daughter boards on pico-imx7d
RUN if [ -f /root/configs/backup/ssh.tar.gz ]; then apt-get update && apt-get -y -q -f --install-suggests install openssh-server && \
tar xzf /root/configs/backup/ssh.tar.gz && chown root:root -R /root/.ssh && \
chmod 600 /root/.ssh/id_rsa && chmod 644 /root/.ssh/id_rsa.pub && \
rm -rf /root/configs/backup; else ssh-keygen -q -f /root/.ssh/id_rsa && \
cat /root/.ssh/id_rsa.pub > /root/.ssh/authorized_keys; fi

ARG pdu_server=10.88.88.12
ENV LAVA_PDU_SERVER ${pdu_server}

#
# PXE
# grub-efi-amd64-bin package if docker machine architecture is not amd64
RUN if [ $(uname -m) != amd64 ]; then dpkg --add-architecture amd64 && apt-get update; fi
RUN if [ -f /root/configs/grub.cfg ]; then mv /root/configs/grub.cfg /root/ && \
apt-get -y -q --no-install-recommends install grub-efi-amd64-bin:amd64; fi
RUN if [ $(uname -m) != amd64 ]; then dpkg --remove architecture amd64 && apt-get update; fi
# intel.efi(iPXE) binary (pre-build by yocto)
RUN if [ -f /root/configs/intel.efi ]; then mv /root/configs/intel.efi /root/; else echo "WARN: no intel.efi(iPXE) found for uefi BIOS PXE boot"; fi

# copy additional default settings for lava or other packages
RUN if [ -n "$(ls -1 /root/configs/default)" ]; then mv /root/configs/default/* /etc/default/; fi

# copy phyhostname to be used by setup.sh
RUN if [ -f /root/configs/phyhostname ]; then mv /root/configs/phyhostname /root/; fi

# copy over zmq_auth (scripts?) to etc/lava-dispatcher/certificates.d
RUN if [ -n "$(ls -1 /root/configs/zmq_auth)" ]; then mv /root/configs/zmq_auth/* /etc/lava-dispatcher/certificates.d/; fi

# copy other default lava-worker folders
RUN mkdir -p /root/devices && if [ -n "$(ls -1 /root/configs/devices)" ]; then mv /root/configs/devices/* /root/devices/; fi
RUN mkdir -p /root/tags && if [ -n "$(ls -1 /root/configs/tags)" ]; then mv /root/configs/tags/* /root/tags/; fi
RUN mkdir -p /root/aliases && if [ -n "$(ls -1 /root/configs/aliases)" ]; then mv /root/configs/aliases/* /root/aliases/; fi
RUN mkdir -p /root/deviceinfo/ && if [ -n "$(ls -1 /root/configs/deviceinfo)" ]; then mv /root/configs/deviceinfo/* /root/deviceinfo/; fi

# remove all copied /root/configs/*
RUN rm -rf /root/configs

#
# Patches, scripts and other stuff
#
# copy bash scripts (include extra_actions)
COPY entrypoint.d/ /root/entrypoint.d/
RUN chmod +x /root/entrypoint.d/*.sh
COPY scripts/ /usr/local/bin/
RUN chmod a+x /usr/local/bin/*

# patch any lava patches to python3's dist-packages
COPY lava-patch/ /root/lava-patch/
RUN if [ -n $(ls -1 /root/lava-patch) ]; then apt-get -y -q --no-install-recommends install patch && \
cd /usr/lib/python3/dist-packages && \
for patch in $(ls /root/lava-patch/*patch); do patch -p1 < $patch || exit $?; done && \
rm -rf /root/lava-patch; fi

# needed for lavacli identities
RUN mkdir -p /root/.config

# execute the extra_actions (if it has been set)
RUN if [ -x /usr/local/bin/extra_actions ]; then /usr/local/bin/extra_actions; fi

# TODO: send this fix to upstream
RUN if [ -f /root/entrypoint.sh ]; then \
sed -i 's,find /root/entrypoint.d/ -type f,find /root/entrypoint.d/ -type f | sort,' /root/entrypoint.sh && \
sed -i 's,echo "$0,echo "========== $0,' /root/entrypoint.sh && \
sed -i 's,ing ${f}",ing ${f} ========== ",' /root/entrypoint.sh; fi

#
# lavacli - lava cli tool for setting up the lava-dispatcher
#
RUN apt-get -y -q update && apt-get -y -q --no-install-recommends install lavacli && rm -rf /var/cache/apk/*

ARG version=latest
ENV LAVA_VERSION=${version}

EXPOSE 69/udp 80

CMD /root/entrypoint.sh && while [ true ]; do sleep 365d; done

