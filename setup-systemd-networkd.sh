#!/usr/bin/env bash

# VERSION : 1.0
# Updated : 2020-05-18
#

# Intro.
# This script create the needed systemd network files (ipv4 only for now),
# for an AD-DC of Domain Member setup.
# You need to review the file and execute the instructions after.
# The script itself does NOT change anything to a running server.


if [ -z $1 ]
then
    echo "Usage $(basename $0) dc/member"
    exit 0
fi

INSTRUCTIONS="
# Verify your file: lan-${1}-dev-$(ip route | grep default |awk '{ print $5 }').network
#  file: (cat lan-${1}-dev-$(ip route | grep default |awk '{ print $5 }').network)
#  edit it : editor lan-${1}-dev-$(ip route | grep default |awk '{ print $5 }').network
# Then when its correct run the following:
#  mv /etc/network/interfaces{,.backup}
#  cp lan-${1}-dev-$(ip route | grep default |awk '{ print $5 }').network /etc/systemd/network/
#  systemctl daemon-reload
#  mv /etc/resolv.conf{,.backup} && ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
#  systemctl enable systemd-networkd
#  systemctl restart systemd-networkd
#  systemctl enable  systemd-timesyncd
#  systemctl restart systemd-timesyncd
#  systemctl enable  systemd-resolved
#  systemctl restart systemd-resolved
#
# And now check you setup with these commands:
#  timedatectl status
#  networkctl status
#  networkctl status $(ip route | grep default |awk '{ print $5 }')
"

BASICINFO="
# These settings are a 'PER INTERFACE' settings.
# You can use /etc/systemd/resolved.conf and timesyncd.conf for GLOBAL settings.
# If GLOBAL settings are used, then you can remove the dns and time parts from the .network file.
# Or mix it with per interface, then you should read also :
# https://www.freedesktop.org/software/systemd/man/systemd.network.html
"

if [ "$1" = "member" ]
then
echo "#### This setup is for a Domain MEMBER server, IPV4 only. ###"
echo
echo "#
# This setup is for a Domain MEMBER server.
# IPV4 only.
[Match]
Name=$(ip route | grep default |awk '{ print $5 }')

[Network]
DHCP=no
DNSSEC=allow-downgrade
DNSSECNegativeTrustAnchors=lan
IPv6PrivacyExtensions=no
IPv6AcceptRouterAdvertisements=no
LinkLocalAddressing=no
LLMNR=no

# make use of systemd resolved and its setup, setup the 'search dnsdomain.tld.'
Domains=$(grep search /etc/resolv.conf |awk '{ print $2 }')

# lets make use of systemd-timedate and timesyncd for the member servers.
# we assume the DNS are also the NTP servers.
NTP=$(host $(grep search /etc/resolv.conf | awk '{ print $2 }')| grep address | awk '{ print $NF }'|tr '\n' ' ')

# DNS resolvers (its safe to mix IPv4 and IPv6)
# Max 3 DNS entries. ::1 or 127.0.0.1 if you use a cacheing dns.
# If you use systemd-resolved stub (caching) dns, use 127.0.0.53 (only)
# Defaults to the AD-DC servers found in the dns.
DNS=$(host $(grep search /etc/resolv.conf | awk '{ print $2 }')| grep address | awk '{ print $NF }'|tr '\n' ' ')

# IPv4 gateway and primary IP address.
Gateway=$(ip -4 route | grep default | awk '{ print $3 }')
Address=$(hostname -I|awk '{ print $1 }')/24
" > lan-${1}-dev-"$(ip route | grep default |awk '{ print $5 }')".network

echo "# Config assumes the following:
# This server has 1 ip, 1 search domain and AD-DC's are also the DNS and TIME servers.
# This server is in a LAN and no ipv6 is used."
echo "${BASICINFO}"
echo "# Time wil be handled by systemd-timedate and systemd-timesyncd
# Resolv.conf wil be handled by systemd-resolved
# NTP and resolv.conf settings are using network setting from systemd-networkd as shown in the config."
echo "${INSTRUCTIONS}"
echo
echo "### This setup is for a Domain MEMBER server. ###"

fi

if [ "$1" = "dc" ]
then
echo "#### This setup is for a Domain AD-DC server, IPv4 only. ###"
echo
echo "#
# This setup is for a Domain AD-DC server.
# IPV4 only.
[Match]
Name=$(ip route | grep default |awk '{ print $5 }')

[Network]
DHCP=no
DNSSEC=allow-downgrade
DNSSECNegativeTrustAnchors=lan
IPv6PrivacyExtensions=no
IPv6AcceptRouterAdvertisements=no
LinkLocalAddressing=no
LLMNR=no

# make use of systemd resolved and its setup, setup the 'search domain.'
# this MUST be set to your primary.DNSdomain.tld
Domains=$(grep search /etc/resolv.conf |awk '{ print $2 }')

# Members
# lets make use of systemd-timedate, no need anymore to install ntp.
#NTP=$(host $(grep search /etc/resolv.conf | awk '{ print $2 }')| grep address | awk '{ print $NF }'|tr '\n' ' ')
# For an AD-DC this is not used, you must setup the time(NTP) daemon.
# see: https://wiki.samba.org/index.php/Time_Synchronisation
# Which is not in this script.

# DNS resolvers (safe to mix IPv4 and IPv6)
# Max 3 DNS entries. ::1 or 127.0.0.1 if you use a cacheing dns.
# if you use systemd-resolved stub (caching) dns, use 127.0.0.53 (only)
DNS=$(hostname -I|awk '{ print $1 }') 8.8.8.8 8.8.4.4
# We resolve first through the primary IP of this AD-DC.
# The google dns is use as fallback, replace these if you have more DC's
# I suggest here 2 x DNS AD-DC, 1 x DNS internet.

# IPv4 gateway and primary address.
Gateway=$(ip route | grep default | awk '{ print $3 }')
Address=$(hostname -I|awk '{ print $1 }')/24
" > lan-${1}-dev-"$(ip route | grep default |awk '{ print $5 }')".network

echo "# Config assumes the following:
# This AD-DC server has 1 ip, 1 search domain and also the DNS and TIME servers.
# This AD-DC server is in a LAN and no ipv6 is used."
echo "${BASICINFO}"
echo "#
# For an AD-DC this is not used, you must setup the time(NTP) daemon.
# see: https://wiki.samba.org/index.php/Time_Synchronisation
# resolv.conf should be set with the ip of this server as first resolver (nameserver ip)
#  ! Note, this is automaticly done through the systemd-networkd settings.
# NTP MUST be setup with ntp: https://wiki.samba.org/index.php/Time_Synchronisation
# The Must is due to TimeSync over AD"
echo "${INSTRUCTIONS}"
echo
echo "### This setup is for a Domain AD-DC server. ### "
fi
