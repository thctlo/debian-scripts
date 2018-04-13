#!/bin/bash

# Created : 2018-04-13 By Louis van Belle
# Apache2 (2.4) tested on Debian Stretch.
#
# This script creates the apache default for a clean server.
# You can use this on a already in production server.
# What...  What does this script do exactly. 
# - It lookup you running ipnumbers and it create vhosts based on the IP.
#   A normal visistor uses names not ips.
# - It makes sure your "default" vhosts are correctly set.
# - It creates, based on the primary domainname of the server, 
#   the www.domain.tld ( with alias domain.tld ) vhost
#   And it creates a mail.domain.tld vhost.
#
# - It setup ip and namebase vhost after running the script you should 
#   check this with : apache2ctl -S

### User Defined Variables
# Define your primary domain.
# The default is what you have set at install of your server.
PRIMARY_DOMAIN="$(hostname -d)"

# Define the wanted subdomains, redefined are www. and mail.
# (optional) We redirect all traffic for "domain.tld" do www.domain.tld.
SUB_DOMAIN="www mail"

# Enable default redirect.
# This add the line Redirect permanent / https://www.${PRIMARY_DOMAIN}/
# to the default IP domains, preffered yes for the internet ip's. 
# Default "no"
ENABLE_REDIRECT="yes"

################################################
# General Variables.
IPS_DOMAINS="$(hostname -I)"
COUNTER=0

# First we disable the Debian supplied defaults.
a2dissite 000-default
a2dissite default-ssl

IpNumberCounter(){
# count the total ipnumbers.
for ips in $IPS_DOMAINS
do
    IPNRCOUNTER="$(echo $IPS_DOMAINS | awk -F'[ \t]+' '{print NF}')"
done
}

setupDefaultVhostForIPnumbers(){
if [ -d /var/www/html ]
then
    if [ ! -f /var/www/html/index.html.debian ]
    then
	mv /var/www/html/index.html{,.debian}
	cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
<title>Site: IP</title>
</head>
<body>
<p>You should use a hostname and not an ipaddress to access this server!</p>
</body>
</html>
EOF
    fi
fi

local SUB_DOMAIN="default-vhost-ips"
# if not exists.
for ips in ${IPS_DOMAINS}
do
    if [ ! -f /etc/apache2/sites-available/00"${COUNTER}"-"${SUB_DOMAIN}".conf ]
    then
	# Create per IP a vhost config based on the 000-default.conf.
	# This is the PRIMARY (default) vhost for this ip. ( see apache2ctl -S )
	# Any misconfigured vhost, will end up in default and (optional) redirect to www.
	# The primary (default) domain does not use ServerAlias!

	sed "s/VirtualHost \*:80/VirtualHost ${ips}:80/g" < /etc/apache2/sites-available/000-default.conf | \
	sed "s/#ServerName www.example.com/ServerName ${ips}/g" | \
	sed "/#/d" | \
	sed "s/LOG_DIR}\//LOG_DIR}\/${SUB_DOMAIN}-${COUNTER}-/g" > /etc/apache2/sites-available/000-"${SUB_DOMAIN}"-"${COUNTER}".conf

	if [ "${ENABLE_REDIRECT}" = "yes" ]
	then
	    if [ "$(grep -c "Redirect permanent" /etc/apache2/sites-available/000-"${SUB_DOMAIN}"-"${COUNTER}".conf)" -eq 0 ]
	    then 
		sed -i "/DocumentRoot/a\\\n\\tRedirect permanent / https://www.${PRIMARY_DOMAIN}/" /etc/apache2/sites-available/000-"${SUB_DOMAIN}"-"${COUNTER}".conf
	    fi
	fi
	a2ensite 000-"${SUB_DOMAIN}"-"${COUNTER}"
    else
	echo "This config file already exists: /etc/apache2/sites-available/000-"${SUB_DOMAIN}"-"${COUNTER}".conf"
    fi

    COUNTER="$((COUNTER + 1))"
done
COUNTER=0
}

setupDefaultVhostForPrimaryDomain(){
for subDomains in ${SUB_DOMAIN}
do
    if [ ! -f /etc/apache2/sites-available/00"${COUNTER}"-"${subDomains}"."${PRIMARY_DOMAIN}".conf ]
    then
	sed "s/#ServerName www.example.com/ServerName ${subDomains}.${PRIMARY_DOMAIN}/g" < /etc/apache2/sites-available/000-default.conf | \
	sed "s/LOG_DIR}\//LOG_DIR}\/${subDomains}.${PRIMARY_DOMAIN}-/g" | \
	sed "/#/d" > /etc/apache2/sites-available/00"${COUNTER}"-"${subDomains}"."${PRIMARY_DOMAIN}".conf

	if [ "$(grep -c "${ips}:80}" /etc/apache2/sites-available/00"${COUNTER}"-"${subDomains}"."${PRIMARY_DOMAIN}".conf)" -eq 0 ]
	then
	    IpNumberCounter
	    for ips in $IPS_DOMAINS
	    do
		if [ "${IPNRCOUNTER}" -ge 2 ]
		then
		    sed -i "s/*:80/${ips}:80 *:80/g" /etc/apache2/sites-available/00"${COUNTER}"-"${subDomains}"."${PRIMARY_DOMAIN}".conf
		else
		    sed -i "s/*:80/${ips}:80/g" /etc/apache2/sites-available/00"${COUNTER}"-"${subDomains}"."${PRIMARY_DOMAIN}".conf
		fi
		IPNRCOUNTER="$(($IPNRCOUNTER - 1))"
	    done
	fi

	if [ "${subDomains}" = "www" ]
	then
	    # add domain alias
	    sed -i "/ServerName ${subDomains}.${PRIMARY_DOMAIN}/a\\\tServerAlias ${PRIMARY_DOMAIN}" /etc/apache2/sites-available/00"${COUNTER}"-"${subDomains}"."${PRIMARY_DOMAIN}".conf
	fi
        a2ensite 00"${COUNTER}"-"${subDomains}"."${PRIMARY_DOMAIN}"
    else
	echo "This config file already exists: /etc/apache2/sites-available/00${COUNTER}-${subDomains}.${PRIMARY_DOMAIN}".conf
    fi
    COUNTER="$((COUNTER + 1))"
done
}
setupDefaultVhostLocalHost(){
# Create Dir + index.html
if [ ! -d /var/www/localhost ];
then
    mkdir -p  /var/www/localhost
cat > /var/www/localhost/index.html << EOF
<!DOCTYPE html>
<html>
<head>
<title>Site: Localhost</title>
</head>
<body>
<p>This is the site running on localhost</p>
</body>
</html>
EOF
fi

#Create apache config
if [ ! -f /etc/apache2/sites-available/000-localhost.conf ]
    then
cat > /etc/apache2/sites-available/000-localhost.conf << EOF
# Default ipv4 localhost
<VirtualHost 127.0.0.1:80 [::1]:80>
# Default ip vhost for localhost ipv4 and ipv6
    ServerAdmin webmaster@localhost
    ServerName 127.0.0.1

    DocumentRoot /var/www/localhost

    ErrorLog  \${APACHE_LOG_DIR}/localhost-error.log
    CustomLog \${APACHE_LOG_DIR}/localhost-access.log combined

</VirtualHost>

#
# Vhost example for localhost.
#
# IP Based Virtual Host examples.
# Both ipv4 and ipv6 localhost
<VirtualHost 127.0.0.1:80 [::1]:80>
# or 
#<VirtualHost localhost:80>
#
# Only ipv6 localhost
#<VirtualHost ip6-localhost:80>
# or
#<VirtualHost [::1]:80>
#
# Only ipv4 localhost
#<VirtualHost 127.0.0.1:80>
#
# Name Based Virtual Host
#<VirtualHost *:80>

    ServerAdmin webmaster@localhost

    ServerName 127.0.0.1

    # For the Aliases, check you "/etc/hosts" file and make sure you have all in here.
    # Default ipv4+ipv6
    ServerAlias localhost [::1] localhost-ip6 ip6-loopback localhost.localdomain

    DocumentRoot /var/www/localhost

    ErrorLog  \${APACHE_LOG_DIR}/localhost-error.log
    CustomLog \${APACHE_LOG_DIR}/localhost-access.log combined

    <Directory />
        AllowOverride None
        Require all denied
    </Directory>

    <Directory /var/www/>
        AllowOverride None
        Require all denied
    </Directory>

    <Directory /var/www/localhost>
        AllowOverride None
        Require all granted
    </Directory>

    <Location "/server-status">
        SetHandler server-status
        Require host localhost
    </Location>

</VirtualHost>
EOF

else
    echo "This config file already exists: /etc/apache2/sites-available/000-localhost.conf"
fi
# enable localhost
a2ensite 000-localhost
}
setupDefaultVhostLocalHost
setupDefaultVhostForIPnumbers
setupDefaultVhostForPrimaryDomain
echo 
echo "Run apache2ctl -S to see you apache server structure"
echo "When it look ok, reload apache."
