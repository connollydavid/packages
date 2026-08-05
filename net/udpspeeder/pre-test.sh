#!/bin/sh

# socat gives the runtime test a UDP echo peer and a UDP client. BusyBox nc is
# built without NC_SERVER and NC_EXTRA, so it can neither listen nor exec.
if command -v apk >/dev/null 2>&1; then
	apk add socat
else
	opkg update && opkg install socat
fi
