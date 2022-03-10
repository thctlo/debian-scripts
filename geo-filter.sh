#!/bin/bash

set -e

# Tested on Debian Bullseye 11.
# Verified with: shellcheck geo-filter.sh : verified: Ok.

# Needed : get a free account at maxmind.com
# https://www.maxmind.com/en/geolite2/signup?lang=en
# Create a Licence Key and update the info in /etc/GeoIp.conf

###### CONFIGURATION-Begin
# UPPERCASE space-separated country codes to ACCEPT/Allow connection from
ALLOW_COUNTRIES="NL GB EU"

# Beware that you configure ALLOW_COUNTRIES before you lock yourself out.
# To prevent this, add in /etc/hosts.allow, above the aclexec
# sshd : WAN_IP/CIDR
# sshd : LAN_IP/CIDR

# Autoconfigure /etc/hosts.allow/deny for ssh access per country.
# Default : yes
AUTO_CONFIGURE_SSH_HOSTS="yes"

# Default yes, set to no when your ready to run.
DEBUG="yes"

# Configured.. Did you configure the script?
CONFIGURED="no"

# Example line what you will get in syslog
# Mar 10 15:17:49 servername geo-filter.sh: DENY connection from IP: 112.85.42.73, country: CN


###### Best is not to change belower here. #########
# If you do, dont forget to ajust additional files manualy.
SCRIPT_NAME="$(basename "$0")"
SCRIPT_LOCATION="/usr/local/sbin"
###### CONFIGURATION-End

SCRIPT_VERSION="22020309-1.1"

####  Optional extra add fail2ban to this.
# apt install -y fail2ban sqlite3

# Lock down SSH (IPv4 Tested)
# The last things we need to do is tell the ssh daemon (sshd) to deny all connections (by default)
# and to run this script to determine whether the connection should be allowed or not.
#
# In /etc/hosts.deny add the line:
#
# sshd: ALL
# and in /etc/hosts.allow add the line
#
# sshd: ALL: aclexec /usr/local/sbin/geo-filter.sh %a
# Change path to the location where the filter program is.

# we need to be root or sudo
if [[ $EUID -ne 0 ]]
then
    echo "This script must be run as root or with sudo"
    exit 1
fi

if [ "${CONFIGURED}" = "no" ]
then
    echo "Please configure the script first, and rerun it with : ${SCRIPT_NAME} --install"
    echo "Exiting now. "
    exit 0
fi

if [ "${1}" = "--install" ]
then
    if [ ! -e "${SCRIPT_LOCATION}/${SCRIPT_NAME}" ]
    then
        cp "${SCRIPT_NAME}" "${SCRIPT_LOCATION}/"
        chmod +x "${SCRIPT_NAME}" "${SCRIPT_LOCATION}/"
        echo "This script is installed to : ${SCRIPT_LOCATION}/${SCRIPT_NAME}"
        echo
    fi
fi
if [ ! -e "${SCRIPT_LOCATION}/${SCRIPT_NAME}" ]
then
    echo "Your forgot to install the script with ${SCRIPT_NAME} --install"
    echo "Exiting now.. "
    exit 0
fi

# Setup minimal needed packages.
if [ ! -x /usr/bin/geoipupdate ]
then
    echo "Please wait, instaling geoipupdate."
    apt install -y -q=2 geoipupdate
fi
if [ ! -x /usr/bin/mmdblookup ]
then
    echo "Please wait, instaling mmdb-bin."
    apt install -y -q=2 mmdb-bin
fi

## setup minimal SSHD for hosts.allow/deny
if [ "${AUTO_CONFIGURE_SSH_HOSTS}" = "yes" ]
then
    # Runs only 1 time untill /etc/hosts.allow.debian-geo-filter exits
    if [ ! -e /etc/hosts.allow.debian-geo-filter ]
    then
        cp /etc/hosts.allow{,.debian-geo-filter}
        echo "#########" >> /etc/hosts.allow
        echo "# Allow sshd, when the script finds the IP in the (configured) allowed countries." >> /etc/hosts.allow
        echo "# Configure the script and set : ALLOW_COUNTRIES" >> /etc/hosts.allow
        echo "# By default we allow all hosts within the same domainname.tld." >> /etc/hosts.allow
        echo "# Make sure the aclexec line is always the last line." >> /etc/hosts.allow
        echo "#########" >> /etc/hosts.allow
        echo "sshd: .$(hostname -d)" >> /etc/hosts.allow
        echo "sshd: ALL: aclexec ${SCRIPT_LOCATION}/${SCRIPT_NAME} %a" >> /etc/hosts.allow
        echo "" >> /etc/hosts.allow
    fi
    if [ ! -e /etc/hosts.deny.debian-geo-filter ]
    then
        cp /etc/hosts.deny{,.debian-geo-filter}
        echo "#########" >> /etc/hosts.deny
        echo "# Deny ssh all hosts, /etc/hosts.allow overrides the deny." >> /etc/hosts.deny
        echo "#########" >> /etc/hosts.deny
        echo "sshd: ALL" >> /etc/hosts.deny
        echo "" >> /etc/hosts.deny
    fi
fi

GET_ACCOUNT_ID="$(grep AccountID < /etc/GeoIP.conf|grep -v YOUR_ACCOUNT_ID_HERE | awk -F" " '{ print $NF }')"
if [ -z "${GET_ACCOUNT_ID}" ]
then
    echo "The file: /etc/GeoIP.conf."
    echo "Is not configured yet with an (free) account from maxmind."
    echo " please register and configure /etc/GeoIP.conf first."
    echo "Go here: https://www.maxmind.com/en/geolite2/signup?lang=en"
    echo "Exiting now.."
    exit 0
fi

if [ ! -e /var/lib/GeoIP/GeoLite2-Country.mmdb ]
then
    echo "geoipupdate has not run yet, we didn't detect the file /var/lib/GeoIP/GeoLite2-Country.mmdb"
    echo "running it now for you, please wait."
    geoipupdate -v
fi

if [ "$#" -ne 1 ]
then
    echo "Usage:      $(basename "$0") <ip>" 1>&2
    exit 0 # return true in case of config issue
fi

COUNTRY="$(/usr/bin/mmdblookup -f /var/lib/GeoIP/GeoLite2-Country.mmdb -i "$1" country iso_code 2>&1| awk -F '"' '{ print $2 }'|head -n 2|tail -n 1)"
COUNTRY="${COUNTRY:=IP Address not found}"
if [ "${COUNTRY}" = "IP Address not found" ] || [[ "$ALLOW_COUNTRIES" =~ $COUNTRY ]]
then
    RESPONSE="ALLOW"
else
    RESPONSE="DENY"
fi

if [ "${RESPONSE}" = "ALLOW" ]
then
    if [ "${DEBUG}" = "yes" ]
    then
        echo "${SCRIPT_NAME}: Warning: Debugging enabled!!"
        echo "${SCRIPT_NAME}: Please dont forget to disable DEBUG in ${SCRIPT_LOCATION}/${SCRIPT_NAME}"
        echo " "
        echo "${SCRIPT_NAME}: ${RESPONSE} connection from IP: ${1}, country: ${COUNTRY}"
        exit 0
    fi
  exit 0
else
    if [ "${DEBUG}" = "yes" ]
    then
        echo "${SCRIPT_NAME}: Warning: Debugging enabled!!!"
        echo "${SCRIPT_NAME}: Please dont forget to disable DEBUG in ${SCRIPT_LOCATION}/${SCRIPT_NAME}"
        echo " "
        echo "${SCRIPT_NAME}: ${RESPONSE} connection from IP: ${1}, country: ${COUNTRY}"
        exit 1
    fi
    logger -t ${SCRIPT_NAME} "${RESPONSE} connection from IP: ${1}, country: ${COUNTRY}"
  exit 1
fi
