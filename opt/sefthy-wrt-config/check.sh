#!/bin/bash

cd /opt/sefthy-wrt-config

STATUS="status_wait"
VPN=""

check_config(){
    [ $(uci -q get sefthy.config.config_complete) -eq 1 ] && {
        STATUS=status_ok
    } || {
        [ $(tail -n40 /var/log/messages | grep "SefthyConfig" | grep "ERR:" | tail -n1 | wc -l) -eq 1 ] && {
            STATUS=status_err
        }
        [ $(tail -n40 /var/log/messages | grep "SefthyConfig" | grep "ERR:Token not found" | tail -n1 | wc -l) -eq 1 ] && {
            STATUS=status_notfound
        }
    }
}

check_vpn(){
    ip a show dev sefthy-wg >/dev/null 2>&1 && remote=$(sipcalc `ip a show dev sefthy-wg | grep 'inet' | cut -d: -f2 | awk '{print substr($2, 1, length($2)-3)}'`/31 | grep range | cut -d' ' -f3)
    ping -c 1 $remote >/dev/null 2>&1
    [ $? -eq 0 ] && {
        VPN=UP
    } || {
        VPN=DOWN
    }
}

check_config
check_vpn

echo -e "{\n    \"status\": \"$STATUS\",\n    \"vpn\": \"$VPN\"\n}"