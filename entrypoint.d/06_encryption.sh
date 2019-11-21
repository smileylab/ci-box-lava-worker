#!/bin/bash

echo "===== Handle encryptions ====="

if [ -e /etc/lava-dispatcher/certificates.d/$(hostname).key ];then
	echo "INFO: Enabling encryption"
	sed -i 's,.*ENCRYPT=.*,ENCRYPT="--encrypt",' /etc/lava-dispatcher/lava-slave
	sed -i "s,.*SLAVE_CERT=.*,SLAVE_CERT=\"--slave-cert /etc/lava-dispatcher/certificates.d/$(hostname).key_secret\"," /etc/lava-dispatcher/lava-slave
	(cd /etc/lava-dispatcher/certificates.d; if [ -e master.key ]; then cp master.key $LAVA_MASTER.key; fi)
	sed -i "s,.*MASTER_CERT=.*,MASTER_CERT=\"--master-cert /etc/lava-dispatcher/certificates.d/$LAVA_MASTER.key\"," /etc/lava-dispatcher/lava-slave
fi
exit 0
