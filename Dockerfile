# Compile 96board-uart tool, i.e. 96boardsctl
ARG version=latest
ARG tgtplatform=linux/arm64
FROM --platform=${tgtplatform} lavasoftware/lava-dispatcher:${version}
WORKDIR /opt/
RUN apt -q update || apt -q update
RUN DEBIAN_FRONTEND=noninteractive apt-get -q -y install build-essential git pkg-config cmake libusb-dev libftdi-dev
# clone source code for building
RUN git clone https://github.com/96boards/96boards-uart.git
# Avoid using new libusb because of build-error
RUN cd 96boards-uart && git checkout 1d2bc993083d97b54d21ecdf72556066efce11f7
RUN cd 96boards-uart/96boardsctl/ && cmake . && make

#
# From https://github.com/kernelci/lava-docker.git lava-slave/Dockerfile
#
ARG version=latest
ARG tgtplatform=linux/arm64
FROM --platform=${tgtplatform} lavasoftware/lava-dispatcher:${version}
ARG required_packages="git patch lavacli"
ARG extra_packages="iputils-ping"
RUN apt-get -y -q update && DEBIAN_FRONTEND=noninteractive apt-get -y -q --no-install-recommends install ${required_packages} ${extra_packages} && rm -rf /var/cache/apk/*

#
# Setup Tools for Serial Console Control for the DUTs
#
# Add 96boardsctl
COPY --from=0 /opt/96boards-uart/96boardsctl/96boardsctl /usr/bin/
# SNMP MIBS for Networked PDU Control
# setup packages for using SNMP MIBS from non-free
RUN echo "deb http://http.us.debian.org/debian/ stable non-free" >> /etc/apt/sources.list.d/non-free.list
RUN apt-get -y -q update && DEBIAN_FRONTEND=noninteractive apt-get -y -q --no-install-recommends install software-properties-common net-tools snmp snmp-mibs-downloader && rm -rf /var/cache/apk/* && rm /etc/apt/sources.list.d/non-free.list
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
# ssh keys
# setup ssh keys for PDU control (on RPI3)
#
ADD configs/ssh.tar.gz /root/
RUN if [ -d /root/.ssh ]; then chown root:root -R /root/.ssh && chmod 600 /root/.ssh/id_rsa && \
chmod 644 /root/.ssh/id_rsa.pub && cat /root/.ssh/id_rsa.pub > /root/.ssh/authorized_keys; fi
RUN apt-get -y -q update && DEBIAN_FRONTEND=noninteractive apt-get -y -q -f --install-suggests install openssh-server && rm -rf /var/cache/apk/*

#
# Setup lava-slave config and tftpd-hpa config
#
COPY configs/lava-slave /etc/lava-dispatcher/lava-slave
COPY configs/lava-worker /etc/lava-dispatcher/lava-worker
COPY configs/tftpd-hpa /etc/default/tftpd-hpa

# Caution to not use any port between the Linux dynamic port range: 32768-60999
# sed replaces values in lava_common/constants.py
RUN find /usr/lib/python3/dist-packages/ -iname constants.py | xargs sed -i 's,XNBD_PORT_RANGE_MIN.*,XNBD_PORT_RANGE_MIN=61950,'
RUN find /usr/lib/python3/dist-packages/ -iname constants.py | xargs sed -i 's,XNBD_PORT_RANGE_MAX.*,XNBD_PORT_RANGE_MAX=62000,'

#
# cu conmux (is for console via conmux),
# note: conmux need cu >= 1.07-24 See https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=336996
#
COPY configs/conmux/ /etc/conmux/
RUN echo "deb http://deb.debian.org/debian/ testing main" >> /etc/apt/sources.list.d/testing.list && \
apt-get -y -q update && apt-get -y -q --no-install-recommends install cu conmux && rm -rf /var/cache/apk/* && rm /etc/apt/sources.list.d/testing.list

#
# telnet (is for using ser2net)
# ser2net > 3.2 is only availlable from sid
#
RUN echo "deb http://deb.debian.org/debian/ sid main" >> /etc/apt/sources.list.d/sid.list && \
apt-get -y -q update && apt-get -y -q --no-install-recommends install telnet ser2net && rm -rf /var/cache/apk/* && rm /etc/apt/sources.list.d/sid.list
COPY configs/ser2net.yaml /etc

#
# screen (for terminal)
#
COPY configs/lava-screen.conf /root/
RUN apt-get -y -q update && apt-get -y -q --no-install-recommends install screen && rm -rf /var/cache/apk/*

#
# PXE
# grub-efi-amd64-bin package if docker machine architecture is not amd64
RUN if [ $(uname -m) != amd64 -a $(uname -m) != x86_64 ]; then dpkg --add-architecture amd64 && apt-get update; fi
RUN apt-get -y -q install grub-efi-amd64-bin:amd64
RUN if [ $(uname -m) != amd64 -a $(uname -m) != x86_64 ]; then dpkg --remove architecture amd64 && apt-get update; fi
COPY configs/grub.cfg /root/
# intel.efi(iPXE) binary (pre-build by yocto)
COPY configs/intel.efi /root/

# copy additional default settings for lava or other packages
COPY configs/default/* /etc/default/
# copy phyhostname to be used by setup-dispatcher.sh
COPY configs/phyhostname /root/
# copy setupenv to be sourced by setup-dispatcher.sh
COPY configs/setupenv /root/
# copy setup-dispatcher.sh script to be called by start-dispatcher.sh
COPY scripts/setup-dispatcher.sh .

# patch any lava patches to lava src code located in python dist-packages
COPY lava-patch/ /root/lava-patch/
RUN cd /usr/lib/python3/dist-packages && for patch in $(ls /root/lava-patch/*patch); do echo "APPLY $patch"; patch -p1 < $patch || exit $?; done;

# needed for lavacli identities
RUN mkdir -p /root/.config

# copy other default lava-worker folders and scripts (include extra_actions)
COPY configs/devices/ /root/devices/
COPY configs/tags/ /root/tags/
COPY configs/aliases/ /root/aliases/
COPY configs/deviceinfo/ /root/deviceinfo/
COPY entrypoint.d/* /root/entrypoint.d/
RUN chmod a+x /root/entrypoint.d/* || :
COPY scripts/* /usr/local/bin/
RUN chmod a+x /usr/local/bin/* || :

# execute the extra_actions (if it has been set)
RUN if [ -x /usr/local/bin/extra_actions ]; then /usr/local/bin/extra_actions; fi

# TODO: send this fix to upstream
RUN if [ -f /root/entrypoint.sh ]; then \
sed -i 's,find /root/entrypoint.d/ -type f,find /root/entrypoint.d/ -type f | sort,' /root/entrypoint.sh && \
sed -i 's,echo "$0,echo "========== $0,' /root/entrypoint.sh && \
sed -i 's,ing ${f}",ing ${f} ========== ",' /root/entrypoint.sh; fi

# extra stuff for adlink setup
ARG pdu_server=10.88.88.12
ENV LAVA_PDU_SERVER ${pdu_server}

ARG version=latest
ENV LAVA_VERSION=${version}

EXPOSE 69/udp 80

CMD /usr/local/bin/start-dispatcher.sh

