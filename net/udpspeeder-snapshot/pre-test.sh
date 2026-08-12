#!/bin/sh

if command -v apk >/dev/null 2>&1; then
	apk add socat
else
	opkg update && opkg install socat
fi
