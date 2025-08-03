#!/bin/sh

version=$(cat /etc/openwrt_release | grep DISTRIB_RELEASE | cut -d"'" -f2)
supported_versions="24.10.0 24.10.1 24.10.2"

is_supported=0
for supported in $supported_versions; do
    if [ "$version" = "$supported" ]; then
        is_supported=1
        break
    fi
done

grep "NethSecurity" /etc/openwrt_release >/dev/null && is_supported=1

if [ $is_supported -eq 0 ]; then
    echo "WARNING: OpenWrt version $version has not been tested with SEFTHY."
    echo "Supported versions are: $supported_versions"
    echo "Installation may not work correctly on this version."
    echo "Do you want to continue anyway? (y/N)"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "Continuing installation..."
            ;;
        *)
            echo "Installation aborted."
            exit 1
            ;;
    esac
fi

wget https://static.sefthy.cloud/openwrt/sefthy.pub -O /tmp/sefthy.pub >/dev/null && 
opkg-key add /tmp/sefthy.pub && \
sed -i '/^src\/gz sefthy/d' /etc/opkg/customfeeds.conf && \
echo "src/gz sefthy https://static.sefthy.cloud/openwrt/x86_64" >> /etc/opkg/customfeeds.conf

opkg update >/dev/null && 
opkg install sefthy || exit 1

grep "NethSecurity" /etc/openwrt_release >/dev/null || {
  opkg install luci-lua-runtime
  cat <<EOF > /usr/share/luci/menu.d/luci-app-sefthy.json
{
  "admin/sefthy": {
    "title": "Sefthy GUI",
      "order": 60,
      "action": {
        "type": "template",
        "path": "sefthy/redirect"
      }
    }
}
EOF

  mkdir -p /usr/lib/lua/luci/view/sefthy

  cat <<EOF > /usr/lib/lua/luci/view/sefthy/redirect.htm
<%
local ip = luci.http.getenv("SERVER_NAME") or luci.http.getenv("HTTP_HOST") or "192.168.1.1"
ip = ip:match("([^:]+)")
local sefthy_url = "http://" .. ip .. ":81"

luci.http.redirect(sefthy_url)
%>
EOF

  rm -rf /tmp/luci* && /etc/init.d/uhttpd restart && /etc/init.d/rpcd restart
}
