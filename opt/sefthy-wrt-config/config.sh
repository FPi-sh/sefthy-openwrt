#!/bin/bash

cd /opt/sefthy-wrt-config

LOCKFILE="/tmp/sefthy.lock"
API="https://console.sefthy.cloud"
VALIDATE_EP="0b5c66f4-40fe-4fe7-9391-f7d2d7f59974/validate-connector"
CONFIRM_EP="03ae5cb6-a229-4492-b390-ed8280c77f26/confirm-connector"
N=60
HOST="$(uci get system.@system[0].hostname)"

if [ -e "$LOCKFILE" ]; then
  exit 1
fi

touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"; exit' INT TERM EXIT

TOKEN=$(uci get sefthy.config.token)
if [[ -z "$TOKEN" || ! "$TOKEN" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  exit 1
fi

BR=$(uci -q get sefthy.config.selected_br)
DEV=$(uci show network | grep "name='$BR'" | cut -d "." -f2)
CC=$(uci -q get sefthy.config.config_complete)

config(){
  local PARAMS=$1
  [[ $CC -eq 1 && "$(echo $PARAMS | jq .active)" -eq "1" ]]  && {
    return 0
  } || {
    network=$(echo $PARAMS | jq .wireguard.network | tr -d '"')
    ptp_l=$(sipcalc $network | grep range | cut -d ' ' -f5)
    ptp_r=$(sipcalc $network | grep range | cut -d ' ' -f3)
    endpoint=$(echo $PARAMS | jq .wireguard.server.endpoint | tr -d '"')
    privkey=$(echo $PARAMS | jq .wireguard.peer.private_key | tr -d '"')
    pubkey=$(echo $PARAMS | jq .wireguard.server.public_key | tr -d '"')
    vniid=$(echo $PARAMS | jq .vxlan.vni)
    vxport=$(echo $PARAMS | jq .vxlan.port)
    graylog=$(echo $PARAMS | jq .graylog.ip | tr -d '"')
    monitor_ips=( `echo $PARAMS | jq .monitor_ips[]` )
    add_bridge=( `echo $PARAMS | jq .add_bridge` )

    mkdir -p /usr/share/nftables.d/chain-pre/input
    echo -e "iifname \"sefthy\" accept\niifname \"sefthy_wg\" ip saddr $ptp_r/32 accept" > /usr/share/nftables.d/chain-pre/input/sefthy.nft
    /etc/init.d/firewall reload

    /etc/init.d/sefthy-wrt-velch restart
    /etc/init.d/sefthy-wrt-velch enable

    uci -q delete network.sefthy_wg
    uci set network.sefthy_wg=interface
    uci set network.sefthy_wg.proto="wireguard"
    uci set network.sefthy_wg.mtu="1412"
    uci set network.sefthy_wg.private_key="$privkey"
    uci add_list network.sefthy_wg.addresses="$ptp_l"
    
    uci -q delete network.sefthy_wg_srv
    uci set network.sefthy_wg_srv=wireguard_sefthy_wg
    uci set network.sefthy_wg_srv.public_key="$pubkey"
    uci set network.sefthy_wg_srv.endpoint_host="$(echo $endpoint | cut -d':' -f1)"
    uci set network.sefthy_wg_srv.endpoint_port="$(echo $endpoint | cut -d':' -f2)"
    uci set network.sefthy_wg_srv.persistent_keepalive="30"
    uci set network.sefthy_wg_srv.route_allowed_ips="1"
    uci add_list network.sefthy_wg_srv.allowed_ips="$network"
    uci add_list network.sefthy_wg_srv.allowed_ips="$graylog"
    uci commit network
    service network reload

    uci -q delete network.sefthy
    uci set network.sefthy=interface
    uci set network.sefthy.proto="vxlan"
    uci set network.sefthy.mtu="1362"
    uci set network.sefthy.dst="$ptp_r"
    uci set network.sefthy.port="$vxport"
    uci set network.sefthy.vni="$vniid"

    sed -Ei "s/^GRAYLOG_IP.*$/GRAYLOG_IP=\"$graylog\"/g" /opt/sefthy-wrt-monitor/monitor.sh

    if [ "${#monitor_ips[@]}" -ge 1 ]; then
      for ip in ${monitor_ips[@]}; do
        bash /opt/sefthy-wrt-monitor/monitor.sh ${ip//\"}
        sleep 1
      done      
    fi

    if [ "$add_bridge" == "true" ]; then
      uci set network.$DEV.ports="`uci get network.$DEV.ports` sefthy"
      uci commit network && /etc/init.d/network reload

      /etc/init.d/sefthy-dr-bridge enable
      /etc/init.d/sefthy-dr-bridge start
    fi

    /etc/init.d/sefthy-wrt-velch enable
    /etc/init.d/sefthy-wrt-velch start

    grep "sshx" /etc/crontabs/root || {
      echo "*/5 * * * * /bin/pidof sshx && { RS=\$(/opt/sefthy-wrt-config/puptime.sh sshx); if [ \$RS -ge 2999 ]; then kill -9 \`/bin/pidof sshx\`; fi }" >> /etc/crontabs/root
      /etc/init.d/cron reload
    }
    

    uci -q set sefthy.config.config_complete=1 && uci -q commit sefthy && \
    curl -X POST -s "$API/$CONFIRM_EP" -d "{\"token\":\"$TOKEN\"}" -H "Content-Type: application/json" >/dev/null
  }
}

[[ ! -z $1 ]] && {
  case $1 in
  "enable")
    uci set network.$DEV.ports="`uci get network.$DEV.ports` sefthy"
    uci commit network && /etc/init.d/network reload

    /etc/init.d/sefthy-dr-bridge enable
    /etc/init.d/sefthy-dr-bridge start
    ;;
  "disable")
    uci set network.$DEV.ports="`uci get network.$DEV.ports | sed 's/ sefthy//g'`"
    uci commit network && /etc/init.d/network reload
    ifup sefthy

    /etc/init.d/sefthy-dr-bridge stop
    /etc/init.d/sefthy-dr-bridge disable
    ;;
  esac
  exit 0
}

response=$(curl -X POST -s "$API/$VALIDATE_EP" -d "{\"token\":\"$TOKEN\"}" -H "Content-Type: application/json")

if echo "$response" | jq . >/dev/null 2>&1; then
  if [[ "$(echo $response | jq .message)" == "null" ]]; then
    config $response
  else
    logger -t "SefthyConfig" ERR:Token not found
    logger -t "SefthyConfig" $response
  fi
else
  logger -t "SefthyConfig" ERR:Invalid JSON
  logger -t "SefthyConfig" $response
fi
