#!/bin/bash

# Tested on Debian Bullseye (11)
# shellcheck disable=SC2207,SC2086

# This script catches and converts an ip adres to the full CIDR
# of the network its in.

# This script can be use with the geo-filter.sh to
# block countries and there ip's CIDR from whois info.

# This prevents for example lots of IP numbers in firewalls
# where hackers have control with the CIDR Range.

### 
VERSION=20220310-1.0

# we need to be root or sudo
if [[ $EUID -ne 0 ]]
then
    echo "This script must be run as root or with sudo"
    exit 1
fi

if [ "$#" -ne 1 ]
then
    echo "Usage:      $(basename "$0") <ip>" 1>&2
    exit 0 # return true in case of config issue
fi

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

        if [ -n "$CIDR" ]
        then
            USE_CIDR="$(echo "$CIDR"|awk '{ print $NF }')"
        #    break
        elif [ -n "$ROUTE" ]
        then
            USE_CIDR="$(echo "$ROUTE"|awk '{ print $NF }')"
        #    break
        elif [ -n "$INETNUM" ]
        then
            CALC_INETNUM1="$(echo $INETNUM|cut -d":" -f2 |cut -d" " -f2)"
            CALC_INETNUM2="$(echo $INETNUM|cut -d":" -f2 |cut -d" " -f4)"
            USE_CIDR="$(netmask -c $CALC_INETNUM1:$CALC_INETNUM2|awk '{ print $NF }')"
        #    break
        fi
    fi
done
BLOCK_CIDR="$USE_CIDR"
echo "$BLOCK_CIDR"
