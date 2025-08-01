#!/bin/bash

BR=$(uci get sefthy.config.selected_br)
DEV=$(uci show network | grep "name='$BR'" | cut -d "." -f2)
ALL=("`uci get network.$DEV.ports` $BR")

while true ; do
  for i in ${ALL[@]}; do
    [[ `cat /sys/class/net/$i/mtu` -eq 1362 ]] || {
      ip link set dev $i mtu 1362;
    }
  done
  sleep 90
done
