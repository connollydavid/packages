#!/bin/sh

# Run a tunnel and pass packets through it, rather than only checking that the
# binary starts. A payload goes in one end and has to come back out unchanged:
#
#   socat -> [client :34203] ==tunnel==> [server :34202] -> echo :34201

set -e

BIN=udpspeeder
KEY=runtimetestkey
ECHO_PORT=34201
SERVER_PORT=34202
CLIENT_PORT=34203
PAYLOAD="udpspeeder runtime test payload"

ECHO_PID=""
SERVER_PID=""
CLIENT_PID=""
cleanup() {
	[ -n "$ECHO_PID" ] && kill "$ECHO_PID" 2>/dev/null
	[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
	[ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" 2>/dev/null
	return 0
}
trap cleanup EXIT

socat UDP4-RECVFROM:$ECHO_PORT,fork EXEC:cat >/dev/null 2>&1 &
ECHO_PID=$!

"$BIN" -s -l 127.0.0.1:$SERVER_PORT -r 127.0.0.1:$ECHO_PORT \
	-k "$KEY" -f 2:1 --log-level 1 >/tmp/udpspeeder-server.log 2>&1 &
SERVER_PID=$!

"$BIN" -c -l 127.0.0.1:$CLIENT_PORT -r 127.0.0.1:$SERVER_PORT \
	-k "$KEY" -f 2:1 --log-level 1 >/tmp/udpspeeder-client.log 2>&1 &
CLIENT_PID=$!

# Both ends are emulated here, so rather than guess how long they need to bind,
# retry the payload until one comes back.
REPLY=""
tries=0
while [ $tries -lt 10 ]; do
	tries=$((tries + 1))
	sleep 2
	REPLY=$(echo "$PAYLOAD" | timeout 20 socat -T8 - UDP4:127.0.0.1:$CLIENT_PORT 2>/dev/null || true)
	[ "$REPLY" = "$PAYLOAD" ] && break
done

if [ "$REPLY" != "$PAYLOAD" ]; then
	echo "payload did not survive the tunnel"
	echo "  sent:     $PAYLOAD"
	echo "  received: $REPLY"
	echo "server log:"
	tail -n 5 /tmp/udpspeeder-server.log 2>/dev/null
	echo "client log:"
	tail -n 5 /tmp/udpspeeder-client.log 2>/dev/null
	exit 1
fi

echo "payload made the round trip through the tunnel"
