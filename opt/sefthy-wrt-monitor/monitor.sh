#!/bin/bash

API="https://console.sefthy.cloud"
CONFIRM_EP="7a7c505b-8e17-4c3c-9fd2-8b6307685df2/set-mac-address"
GRAYLOG_IP=
BR=$(uci get sefthy.config.selected_br)

cd /opt/sefthy-wrt-monitor

TOKEN=$(uci get sefthy.config.token)
if [[ -z "$TOKEN" || ! "$TOKEN" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  exit
fi

function monitor_delete() {
    local RMIP=$1
    IPS=( `uci get sefthy.monitor.ips` )
    NEW_IPS=()
 
    for ip in "${IPS[@]}"; do
        [[ $ip != "$RMIP" ]] && NEW_IPS+=("$ip") && echo -e "$ip"
    done

    uci delete sefthy.monitor.ips

    if [ ${#NEW_IPS[@]} -eq 0 ]; then
        uci commit sefthy
        exit 0
    fi

    for ip in "${NEW_IPS[@]}"; do
      uci add_list sefthy.monitor.ips="$ip"
    done

    uci commit sefthy
}

function check_arping() {
    local ip="$1"
    local result=$(arping -s 0.0.0.0 -c 4 -I $BR "$ip" 2>/dev/null)

    local mac=$(echo "$result" | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
    local received=$(echo "$result" | grep -Eo "Received [0-4] response" | awk '{print $2}')
    local packet_loss=$(( (4 - received) * 100 / 4 ))

    local latencies=$(echo "$result" | grep -oE '[0-9]+\.[0-9]+ms' | cut -d' ' -f1)
    local avg_latency=0

    if [[ $received -gt 0 ]]; then
        avg_latency=$(echo "$latencies" | awk '{sum+=$1} END {printf "%.3f", sum/NR}')
    fi

    formatted_time=$(date "+%Y-%m-%d %H:%M:%S")
    curl --connect-timeout 5 -X POST "http://${GRAYLOG_IP}:12202/gelf" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "version": "1.1",
  "host": "cpe-${TOKEN}",
  "short_message": "AVG LATENCY",
  "_ip": "${ip}",
  "_mac_address": "${mac}",
  "_avg_latency": "${avg_latency}",
  "_packet_loss": "${packet_loss}",
}
EOF
}

if [[ "$2" == "remove" ]]; then
  monitor_delete $1
  exit 0
fi

if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  mac=$(arping -s 0.0.0.0 -c 1 -I $BR "$1" | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}')

  uci get sefthy.monitor.ips | grep -E "${1} | ${1}$" || uci add_list sefthy.monitor.ips="$1" && uci commit sefthy
  curl -X POST -s "$API/$CONFIRM_EP" -d "{\"token\":\"$TOKEN\",\"ip\":\"$1\",\"mac_address\":\"$mac\"}" -H "Content-Type: application/json" \
  -H 'X-DR-AUTH-INT: pCWOWbqPIIB1Qmmd9Z3OvDKSMZ7QtoBMjcPhpv3UzKnNdze2D8OX2SgO1NtyLPQDxXPqYpv0QVt0HbAALCLOac4EF9HgOYmu58btSOecTFgfZy'
  grep "sefthy-wrt-monitor" /etc/crontabs/root || {
    echo "* * * * * /opt/sefthy-wrt-monitor/monitor.sh" >> /etc/crontabs/root
    /etc/init.d/cron reload
  }
  exit
fi

uci get sefthy.monitor.ips >/dev/null
rc=$?

if [[ $rc -eq 1 ]]; then
  exit
else
  IPS=( `uci get sefthy.monitor.ips` )
  for ip in "${IPS[@]}"; do
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && \
    check_arping $ip
  done
fi