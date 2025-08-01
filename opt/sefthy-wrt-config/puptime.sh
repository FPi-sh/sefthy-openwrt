#!/bin/sh
# 🐶

PID=$(pidof "$1")

if [ -z "$PID" ]; then
    exit 1
fi

uptime_seconds=$(cut -d. -f1 /proc/uptime)

start_ticks=$(awk '{print $22}' /proc/$PID/stat)

start_seconds=$(($start_ticks / 100))
etimes=$(($uptime_seconds - $start_seconds))

echo $etimes