#!/bin/sh

set -e

[ -n "$1" ] && exec "$@"

# Set default variables
LOGGER_URL=${LOGGER_URL:-tcp://localhost:5555}
LOGLEVEL=${LOGLEVEL:-DEBUG}
LOGFILE=${LOGFILE:--}
MASTER_URL=${MASTER_URL:-tcp://localhost:5556}
URL=${URL:-http://localhost/}

# Import variables
if [ ${LAVA_VERSION//.*} -lt 2021 ]; then
	[ -e /etc/lava-dispatcher/lava-slave ] && . /etc/lava-dispatcher/lava-slave
else
	[ -e /etc/lava-dispatcher/lava-worker ] && . /etc/lava-dispatcher/lava-worker
fi

for f in $(find /root/entrypoint.d/ -type f); do
    case "$f" in
        *.sh)
            echo "$0: running ${f}"
            "${f}"
            ;;
        *)
        echo "$0: ignoring ${f}"
        ;;
    esac
done

if [ ${LAVA_VERSION//.*} -lt 2021 ]; then
	exec /usr/bin/lava-slave --level "$LOGLEVEL" --log-file "$LOGFILE" --master "$MASTER_URL" --socket-addr "$LOGGER_URL" $IPV6 $SOCKS_PROXY $ENCRYPT $MASTER_CERT $SLAVE_CERT $DISPATCHER_HOSTNAME
else
	exec /usr/bin/lava-worker --level "$LOGLEVEL" --log-file "$LOGFILE" --url "$URL" $TOKEN $WORKER_NAME $WS_URL $HTTP_TIMEOUT $JOB_LOG_INTERVAL
fi
