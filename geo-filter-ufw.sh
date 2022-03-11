#!/bin/bash

# Tested on Debian Bullseye (11).
#shellcheck disable=SC2207,SC2086,SC2034

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

# Enable automatic CIDR blocking with ufw.
# Default no, because you need to setup ufw first yourself.
UFW_AUTO_BLOCK="no"

# If set to no, we only deny access to port 22.
# If set to yes, we block to the complete server.
UFW_BLOCK_ALLPORT="no"

# Default yes, set to no when your ready to run.
DEBUG="yes"

# Configured.. Did you configure the script?
CONFIGURED="no"

###### Best is not to change belower here. #########
# If you do, dont forget to ajust additional files manualy.
SCRIPT_NAME="$(basename "$0")"
SCRIPT_LOCATION="/usr/local/sbin"
###### CONFIGURATION-End

SCRIPT_VERSION="22020311-1.0"

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

function AutoBlockUFW(){
if [ "${UFW_AUTO_BLOCK}" = "yes" ]
then
    if [ ! "$(command -v netmask)" ]
    then
        apt install -y -q=2 netmask
    fi
    if [ ! "$(command -v whois)" ]
    then
        apt install -y -q=2 whois
    fi

    IFS=$'\n'
    GET_IP_INFO=( $(whois "${1}" |grep -viE "mnt-routes|descr" | grep -iE "inetnum|route|cidr") )
    unset IFS

    # Count the array's.
    array_count="${#GET_IP_INFO[@]}"
    for ((i = 0; i != array_count; i++))
    do
        if [ -n "${GET_IP_INFO[i]}" ]
        then
            INETNUM="$(echo "${GET_IP_INFO[i]}"|grep -i inetnum)"
            ROUTE="$(echo "${GET_IP_INFO[i]}"|grep -i route)"
            CIDR="$(echo "${GET_IP_INFO[i]}"|grep -i cidr)"
            if [ -n "${CIDR}" ]
            then
                USE_CIDR="$(echo "$CIDR"|awk '{ print $NF }')"
            elif [ -n "${ROUTE}" ]
            then
                USE_CIDR="$(echo "$ROUTE"|awk '{ print $NF }')"
            elif [ -n "${INETNUM}" ]
            then
                CALC_INETNUM1="$(echo $INETNUM|cut -d":" -f2 |cut -d" " -f2)"
                CALC_INETNUM2="$(echo $INETNUM|cut -d":" -f2 |cut -d" " -f4)"
                USE_CIDR="$(netmask -c $CALC_INETNUM1:$CALC_INETNUM2|awk '{ print $NF }')"
            fi
        fi
    done

    BLOCK_CIDR="${USE_CIDR}"
    if [ "${DEBUG}" = "yes" ]
    then
        if [ "${UFW_BLOCK_ALLPORT}" = "no" ]
        then
            echo "ufw prepend reject from ${BLOCK_CIDR} to any port 22 comment \"Automated CIDR block by ${SCRIPT_NAME} for country: ${COUNTRY}\""
        else
            echo "ufw prepend reject from ${BLOCK_CIDR} to any comment \"Automated CIDR block by ${SCRIPT_NAME} for country: ${COUNTRY}\""
        fi
    else
        if [ "${UFW_BLOCK_ALLPORT}" = "no" ]
        then
            ufw prepend reject from ${BLOCK_CIDR} to any port 22 comment "Automated CIDR block by ${SCRIPT_NAME} for country: ${COUNTRY}" >/dev/null
        else
            ufw prepend reject from ${BLOCK_CIDR} to any comment "Automated CIDR block by ${SCRIPT_NAME} for country: ${COUNTRY}" >/dev/null
        fi
    fi
fi
}

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
        {
        echo "#########" >> /etc/hosts.allow
        echo "# Allow sshd, when the script finds the IP in the (configured) allowed countries."
        echo "# Configure the script and set : ALLOW_COUNTRIES"
        echo "# By default we allow all hosts within the same domainname.tld."
        echo "# Make sure the aclexec line is always the last line."
        echo "#########"
        echo "sshd: .$(hostname -d)"
        echo "sshd: ALL: aclexec ${SCRIPT_LOCATION}/${SCRIPT_NAME} %a"
        echo ""
        } >> /etc/hosts.allow
    fi
    if [ ! -e /etc/hosts.deny.debian-geo-filter ]
    then
        cp /etc/hosts.deny{,.debian-geo-filter}
        {
        echo "#########"
        echo "# Deny ssh all hosts, /etc/hosts.allow overrides the deny."
        echo "#########"
        echo "sshd: ALL"
        echo ""
        } >> /etc/hosts.deny
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
        AutoBlockUFW "$1"
        exit 1
    fi
    logger -t ${SCRIPT_NAME} "${RESPONSE} connection from IP: ${1}, country: ${COUNTRY}"
    AutoBlockUFW "$1"
    exit 1
fi
