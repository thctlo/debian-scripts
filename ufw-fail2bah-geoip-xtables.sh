#!/bin/bash
# updated 11-sept-2018
# fix bugs. tested on Debian Stretch
# 
# The script installes ufw and iptables with geoip support and fail2ban.
# It also setups a cron job so the geoip data is updated.
# After updated, we check if geoip modules is available and if so restart ufw.

set -e

#########################################################################
# DO NOT CHANGE ANYTHING BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING! #
#                    IF YOU BREAK IT, YOU FIX IT                        #
#########################################################################
Help_text () {
    echo "This script will install and setup ufw and xtable for country blocks"
    echo  "You can run it with cron, to autoupdate country database"
    echo  "usage:"
    echo  " '$0' this will result in a full configured setup."
    echo  " '$0' --check-install wil check and install needed packages"
    echo  " '$0' --debug' will echo messages to screen,"
    echo  " usually used when initially testing."
    echo  " '$0' -h or --help' will print this message."
    echo  " '$0' by itself will log to syslog,"
    echo  " usually used when run from cron."
    echo
}

if [ -z "$1" ]
then
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]
    then
	Help_text
       exit 0
     else
       Help_text
       exit 0
    fi
elif [ "$1" = "--debug" ]; then
    DEBUG="echo"
else
    DEBUG="logger -t $0"
fi

# make sure this is being run by root
if ! [[ $EUID -eq 0 ]]; then
    ${DEBUG} "This script should be run using sudo or by root."
    exit 1
fi

if [ "$1" = "--check-install" ]; then
    ## Install-setup section
    $DEBUG "Running apt-get update and checking for installed packages"
    apt-get update 2> /dev/null
    ## needed packages, ufw and xtables
    if [ "$(dpkg -l | grep ufw | tail -n1 | awk '{print $1}')" = "ii" ]; then
        $DEBUG "Installing missing package ufw."
         apt-get install ufw -y 2> /dev/null
    fi
    if [ "$(dpkg -l | grep linux-headers-amd64 | tail -n1 | awk '{print $1}')" = "ii" ]; then
         $DEBUG "Installing missing packages linux-headers-amd64."
         apt-get install linux-headers-amd64 -y 2> /dev/null
     fi
     if [ "$(dpkg -l | grep xtables-addons-dkms | tail -n1 | awk '{print $1}')" = "ii" ]; then
         $DEBUG "Installing missing packages xtables-addons-dkms."
         apt-get install xtables-addons-dkms -y 2> /dev/null
     fi
    if [ "$(dpkg -l | grep xtables-addons-common | tail -n1 | awk '{print $1}')" = "ii" ]; then
        $DEBUG "Installing missing packages xtables-addons-common libtext-csv-xs-perl."
         apt-get install xtables-addons-common libtext-csv-xs-perl -y 2> /dev/null
    fi
    if [ "$(dpkg -l | grep fail2ban | tail -n1 | awk '{print $1}')" = "ii" ]; then
        $DEBUG "Installing missing fail2ban package."
         apt-get install fail2ban -y 2> /dev/null
    fi
    if [ ! -f /etc/cron.d/maintainance-ufw ]; then
    $DEBUG "Installing /etc/cron.d/maintainance-ufw for auto-updates of countries"
        cat << EOF >> /etc/cron.d/maintainance-ufw
# minute (0-59),
# |     hour (0-23),
# |     |       day of the month (1-31),
# |     |       |       month of the year (1-12),
# |     |       |       |       day of the week (0-7 with 0=7=Sunday).
# |     |       |       |       |       user
# |     |       |       |       |       |       command
0      5     1,8,16,24  *       *      root     [ -x /etc/ufw/bin/xtable-update-geoip.sh ] && /etc/ufw/bin/xtable-update-geoip.sh > /dev/null 2>/dev/null
EOF
    fi

    if [ "$(grep -c "src-cc" < /etc/ufw/before.rules)" -eq 0 ]; then
        cp /etc/ufw/before.rules /etc/ufw/before.rules.original
        ${DEBUG} "setting /etc/ufw/before.rules for xtables "
        sed -i "/End required lines/a \\\n## only allow ssh from NL \n-A ufw-before-input -m conntrack --ctstate NEW -m geoip ! --src-cc NL -m tcp -p tcp --dport 22 -m comment --comment 'SSH%20Geoip' -j DROP" /etc/ufw/before.rules
        ${DEBUG} "Done, creating backup file of the before.rules ( added -date )"
        cp /etc/ufw/before.rules /etc/ufw/before.rules-"$(date +%Y-%m-%d)"
    fi

    if [ ! -f /etc/fail2ban/action.d/ufw-all.conf ]; then
        $DEBUG "Creating /etc/fail2ban/action.d/ufw-all.conf "
        cat << EOF >> /etc/fail2ban/action.d/ufw-all.conf
# Fail2Ban configuration file
#
# We add the rules to ufw for better control and management
#

[Definition]

# Option:  actionstart
# Notes.:  command executed once at the start of Fail2Ban.
# Values:  CMD
#
actionstart =

# Option:  actionstop
# Notes.:  command executed once at the end of Fail2Ban
# Values:  CMD
#
actionstop =

# Option:  actioncheck
# Notes.:  command executed once before each actionban command
# Values:  CMD
#
actioncheck =

# Option:  actionban
# Notes.:  command executed when banning an IP. Take care that the
#          command is executed with Fail2Ban user rights.
# Tags:    <ip>  IP address
#          <failures>  number of failures
#          <time>  unix timestamp of the ban time
# Values:  CMD
#
actionban = ufw insert 1 deny from <ip> to any

# Option:  actionunban
# Notes.:  command executed when unbanning an IP. Take care that the
#          command is executed with Fail2Ban user rights.
# Tags:    <ip>  IP address
#          <failures>  number of failures
#          <time>  unix timestamp of the ban time
# Values:  CMD
#
actionunban = ufw delete deny from <ip> to any
EOF
    fi
    if [ ! -f /etc/fail2ban/jail.d/zz99custom-ssh.conf ]; then
    $DEBUG "Installing : /etc/fail2ban/jail.d/zz99custom-ssh.conf, please adjust the maxretry and bantime to your needs"
    $DEBUG "Default, People blocked on port 22, get block for the complete server."
    cat << EOF > /etc/fail2ban/jail.d/zz99custom-ssh.conf
[sshd]
enabled = true
banaction = ufw-all
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 2
bantime  = 84600
EOF
    fi
    systemctl restart fail2ban
fi

## Update-section
if [ ! -d /usr/share/xt_geoip ]; then
    mkdir /usr/share/xt_geoip
fi

## change to tempdir
cd /tmp

## This will download the list to the current directory.
/usr/lib/xtables-addons/xt_geoip_dl >> /dev/null

## Convert the GeoIP list
/usr/lib/xtables-addons/xt_geoip_build -D /usr/share/xt_geoip ./*.csv  >> /dev/null

# Clean up
rm /tmp/GeoIP*

## Test
if [ "$(/sbin/iptables -m geoip --help | grep -c "geoip match options:")" -eq 0 ]; then
    ${DEBUG} "Error GeoIP iptables modules test failed.. GeoIP is disabled.."
else
    if [ -x /lib/ufw/ufw-init ]; then 
	/lib/ufw/ufw-init restart
    else
	$DEBUG "Error, /lib/ufw/ufw-init is not executable, please check."
	$DEBUG "Restarting with : sh /lib/ufw/ufw-init restart"
	sh /lib/ufw/ufw-init restart
	if [ $? -ge 1 ]; then
	    $DEBUG "Error, restarting, please check manualy"
	fi
    fi
fi
