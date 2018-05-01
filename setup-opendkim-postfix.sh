#!/bin/bash

# Asuming postfix is already setup and running.
# Tested on Debian Stretch

# Version 0.3. d.d 2018-05-01
# Changes, corrected typos

### CONFIGURATION
# The Primary email domain, ( Note: all other settings are defaults and are ok to use.)
# Changing the domain to your primary email domain is a must.
OPENDKIM_DOMAIN=""

# This folder is used to set/configure the KeyTable, SigningTable and TrustedHosts files.
OPENDKIM_DIR="/etc/postfix/dkim"

# The selector; this results in mail20180325 (mailYearMonthDay format)
OPENDKIM_SELECTOR="mail"

# Use 1024 or 2048, Note that 4096 wont work, its to big for DNS entrie
OPENDKIM_BITS="2048"

# The "default" opendkim port is used.
OPENDKIM_PORT="8892"

# ! Note. 
# some settings are set in /etc/defaults/opendkim.
# These settings are use to generate the correct opendkim.service file.
# see the link, differences between opendkim 2.9.2 2.10.x 2.11.x

### PROGRAM ####################################################################
set -e
DATE_NOW="$(date +%Y%m%d)"
### Sources to read.
GoReadThis(){
echo "# Very Usefull info to read."
echo "# My used sources to make this script:"
echo "# https://wiki.debian.org/opendkim and/or (yes its a different page) https://wiki.debian.org/OpenDKIM"
echo "# https://terminal28.com/how-to-install-and-configure-opendkim-postfix-dns-debian-9-stretch/"
echo "# https://jschumacher.info/2017/06/upgrading-to-debian-stretch-with-dovecot-postfix-opendkim/  ! know the difference between opendkim 2.9.2 2.10.x and 2.11.x"
echo "# https://linode.com/docs/email/postfix/configure-spf-and-dkim-in-postfix-on-debian-8/ ! some usefull info for stretch also."
echo "# https://blog.thisispedro.com/index.php/2016/08/21/opendkim-and-restricted-dns/"
echo "# http://www.postfix.org/MILTER_README.html  what is a milter?"
echo "#"
echo "# ! These three are very good to read to understand SPF DKIM DMARC setups."
echo "# http://www.tech-savvy.nl/2017/02/17/antispam-counter-measures-explained-part-1-how-the-sender-policy-framework-really-works/"
echo "# http://www.tech-savvy.nl/2017/03/09/antispam-counter-measures-explained-part-2-advanced-spf-records-best-practice-and-biggest-mistakes/"
echo "# http://www.tech-savvy.nl/2017/04/11/antispam-counter-measures-explained-part-3-dkim/"
echo "# https://elasticemail.com/dmarc/"
}

CheckPackageIsInstalled() {
if [ "$(dpkg-query -W --showformat='${db:Status-Status}\n' "${1}")" == "installed" ]; then
    echo "Package was already installed : ${1}."
else
    apt-get -qy install "${1}"
fi
}
GenerateKeyOpenDKIM(){
    echo "Generating new key, please wait."
    # ! Note, by most show -h rsa-sha256, this is incorrect.
    opendkim-genkey -r -D /etc/dkimkeys/ -d ${OPENDKIM_DOMAIN} -s ${OPENDKIM_SELECTOR}${DATE_NOW} -b ${OPENDKIM_BITS} -h sha256
}
FixRightsOpenDKIM() {
    echo "Setting rights again on dkim files/folders."
    chgrp opendkim ${OPENDKIM_DIR}/*
    chmod u=+rw,g=+r,o=-rwx ${OPENDKIM_DIR}/*
    chown opendkim /etc/dkimkeys/*
    chmod u=+rw,g=-rwx,o=-rwx /etc/dkimkeys/*
}

CheckOpenDKIMdnsKey(){
echo "# If the DNS is setup you can run the following to check the key."
echo "opendkim-testkey -d ${OPENDKIM_DOMAIN} -s ${OPENDKIM_SELECTOR}${DATE_NOW} -vvv"
echo
echo "The expected result should look like this :"
echo "# opendkim-testkey: using default configfile /etc/opendkim.conf"
echo "# opendkim-testkey: checking key '${OPENDKIM_SELECTOR}${DATE_NOW}._domainkey.${OPENDKIM_DOMAIN}'"
echo "# opendkim-testkey: key secure ( or opendkim-testkey: key not secure)"
echo "# opendkim-testkey: key OK"
echo
echo "# If you are using OpenDKIM behind a restrictive network that doesn’t allow all outgoing UDP connections,"
echo "# you may find some issues when checking authoritative responses for public keys:"
echo "# ...  query timed out ... or unexpected reply class/type (-1/-1)"
echo "# Check firewall setting also. ( allow port 53 (tcp+udp)"
echo
echo "# The workaround is to set static DNS servers (whatever is allowed in your network/firewall)"
echo "# in /etc/opendkim.conf using the directive Nameservers"
echo "# example, add : Nameservers 208.67.222.222,208.67.220.220 for openDNS"
echo "# example, add : Nameservers 8.8.8.8,8.8.4.4 for Google"
echo "# If you use bind or any other caching dns server with forwarding, add the forwarder DNS servers!"
}

echo
#
CheckPackageIsInstalled opendkim
CheckPackageIsInstalled opendkim-tools
echo

if [ ! -d ${OPENDKIM_DIR} ]; then
    install -d ${OPENDKIM_DIR} -o root -g opendkim -m 750

    # -D Save2Folder -d domainnaam.tld -s selecter
    # !Note, update dkim, then change the selector
    GenerateKeyOpenDKIM
    touch ${OPENDKIM_DIR}/KeyTable
    touch ${OPENDKIM_DIR}/SigningTable
    touch ${OPENDKIM_DIR}/TrustedHosts
    # change group to opendkim and set the rights to 750
    FixRightsOpenDKIM

    # 
    # Commonly-used options; the commented-out versions show the defaults.
    #Canonicalization       simple
    #Mode                   sv
    #SubDomains             no
    #	sed -i 's/#Mode/Mode/g' /etc/opendkim.conf
    # Not needed its the default.
else
    echo "The opendkim key is generated and placed already in /etc/dkimkeys (debian default)"
    echo "Please note, keep you rights correct here. "
    echo "Use: "
    echo "chgrp opendkim ${OPENDKIM_DIR}/* " 
    echo "chown opendkim /etc/dkimkeys/* " 
    echo "chmod u=+rw,g=+r,o=-rwx ${OPENDKIM_DIR}/*"
    echo "chmod u=+rw,g=-rwx,o=-rwx /etc/dkimkeys/*"
    echo "To correct it."
    echo
fi

if [ $(grep ${OPENDKIM_PORT} < /etc/default/opendkim | wc -l) -eq 0 ]; then
    # Disable unix socket
    sed -i 's/SOCKET=local:\$RUNDIR\/opendkim.sock/#SOCKET=local:\$RUNDIR\/opendkim.sock/g' /etc/default/opendkim

    # Enable TCP socket. ( defaults in this script to port 8892, its used in opendkim defaults )
    sed -i 's/#SOCKET=inet:12345\@localhost/SOCKET=inet:${OPENDKIM_PORT}\@localhost/g' /etc/default/opendkim
    sed -i 's/# listen on loopback on port 12345/# listen on loopback on port ${OPENDKIM_PORT}/g' /etc/default/opendkim

    # or via Postfix SOCKET below sed lines.
    #sed -i 's/#RUNDIR=\/var\/spool\/postfix/RUNDIR=\/var\/spool\/postfix/g' /etc/default/opendkim
    #sed -i 's/RUNDIR=\/var\/run\/opendkim/#RUNDIR=\/var\/run\/opendkim/g' /etc/default/opendkim
    # ! Note, not everything is setup for unix sockets, that needs more work. 

    # Generate the correct service file.
    /lib/opendkim/opendkim.service.generate
    systemctl daemon-reload
    systemctl restart opendkim
else
    echo "File /etc/default/opendkim was already modified."
    echo "The port was already modified to ${OPENDKIM_PORT}@localhost"
fi

if [ $(grep SigningTable < /etc/opendkim.conf | wc -l) -eq 0 ]; then
cat << EOF >> /etc/opendkim.conf

###### Added for OpenDKIM by script
# Specify the list of keys
KeyTable            file:${OPENDKIM_DIR}/KeyTable

# Match keys and domains
SigningTable        file:${OPENDKIM_DIR}/SigningTable 

# Host/IP trusts.
ExternalIgnoreList  file:${OPENDKIM_DIR}/TrustedHosts
InternalHosts       file:${OPENDKIM_DIR}/TrustedHosts
EOF
else
    echo 
    echo "Keytable was already done, asumming SigningTable and InternalHosts ExternalIgnoreList also done."
    echo "This modification was already done in : /etc/opendkim.conf."
fi

# KeyTable
if [ $(grep ${OPENDKIM_DOMAIN} < ${OPENDKIM_DIR}/KeyTable | wc -l) -eq 0 ]; then
    echo "Detected clean ${OPENDKIM_DIR}/KeyTable"
    cat << EOF >>  ${OPENDKIM_DIR}/KeyTable
###### Added for OpenDKIM by script
${OPENDKIM_SELECTOR}${DATE_NOW}._domainkey.${OPENDKIM_DOMAIN} ${OPENDKIM_DOMAIN}:${OPENDKIM_SELECTOR}${DATE_NOW}:/etc/dkimkeys/${OPENDKIM_SELECTOR}${DATE_NOW}.private
EOF
echo
echo "Added some defaults, please review this yourself also"
echo
elif [ $(grep "${OPENDKIM_SELECTOR}${DATE_NOW}" < ${OPENDKIM_DIR}/KeyTable | wc -l) -eq 0 ]; then
    echo "Adding a new key to KeyTable file".
    echo "${OPENDKIM_SELECTOR}${DATE_NOW}._domainkey.${OPENDKIM_DOMAIN} ${OPENDKIM_DOMAIN}:${OPENDKIM_SELECTOR}${DATE_NOW}:/etc/dkimkeys/${OPENDKIM_SELECTOR}${DATE_NOW}.private" >> ${OPENDKIM_DIR}/KeyTable
    KEY_UPDATED="yes"
else
    echo "A Keytable key was already added today, review it or remove it to generate a new one."
fi

# SigningTable
if [ $(grep ${OPENDKIM_DOMAIN} < ${OPENDKIM_DIR}/SigningTable | wc -l) -eq 0 ]; then
    echo "Detected clean ${OPENDKIM_DIR}/SigningTable"
    cat << EOF >>  ${OPENDKIM_DIR}/SigningTable
###### Added for OpenDKIM by script
# You can specify multiple domains
# Example.net SelectorDate._domainkey.example.net
#
${OPENDKIM_DOMAIN} ${OPENDKIM_SELECTOR}${DATE_NOW}._domainkey.${OPENDKIM_DOMAIN}
EOF
echo
echo "Added some defaults, please review this yourself also"
echo
elif [ $(grep "${OPENDKIM_SELECTOR}${DATE_NOW}" < ${OPENDKIM_DIR}/SigningTable | wc -l) -eq 0 ]; then
    echo "Adding new key to SigningTable file".
    echo "${OPENDKIM_SELECTOR}${DATE_NOW}._domainkey.${OPENDKIM_DOMAIN} ${OPENDKIM_DOMAIN}:${OPENDKIM_SELECTOR}${DATE_NOW}:/etc/dkimkeys/${OPENDKIM_SELECTOR}${DATE_NOW}.private" >> ${OPENDKIM_DIR}/SigningTable
    KEY_UPDATED="yes"
else
    echo "A SigningTable key was already added today, review it or remove it to generate a new one."
fi

if [ "${KEY_UPDATE}" = "yes" ]; then 
    systemctl restart opendkim postfix
    if [ "$?" -ne 0 ]; then
	echo "ERROR, Something is wrong, unable to restart opendkim and/or postfix correctly."
	echo "ERROR, Please check you config NOW !!!! "
	echo "use : systemctl restart opendkim postfix  when your done."
	echo "Exiting now....."
	exit 1
    fi
fi

# TrustedHosts
if [ $(grep $(hostname -f) < ${OPENDKIM_DIR}/TrustedHosts | wc -l) -eq 0 ]; then
    echo "Detected clean ${OPENDKIM_DIR}/TrustedHosts"
    cat << EOF >>  ${OPENDKIM_DIR}/TrustedHosts
###### Added for OpenDKIM by script
127.0.0.1
::1
localhost
$(hostname -s)
$(hostname -d)
${OPENDKIM_DOMAIN}
EOF
for y in $(hostname -A); do 
    echo $y >> /etc/postfix/dkim/TrustedHosts
done
for x in $(hostname -I); do 
    echo $x >> /etc/postfix/dkim/TrustedHosts
done
echo "###### Manual added below here." >>  ${OPENDKIM_DIR}/TrustedHosts
echo
echo "Added some defaults, please review this yourself also, look in ${OPENDKIM_DIR}/"
echo
fi
unset x
unset y


if [ $(grep "inet:localhost:${OPENDKIM_PORT}" < /etc/postfix/main.cf | wc -l) -eq 0 ]; then
cat << EOF >> /etc/postfix/main.cf

###### Added for OpenDKIM by script
milter_default_action = accept
milter_protocol = 6
smtpd_milters = inet:localhost:${OPENDKIM_PORT}
non_smtpd_milters = inet:localhost:${OPENDKIM_PORT}
EOF
else
    echo "Postfix was already setup for dkim on localhost:${OPENDKIM_PORT}"
    echo "The modification is done in : /etc/postfix/main.cf"
    echo 
fi

# for the dns.
echo 
echo "Folder /etc/dkimkeys/ is the private key folder."
cat /etc/dkimkeys/README.PrivateKeys
echo
echo

echo "Use this for the DNS TXT record: "
if [ ! -f /etc/dkimkeys/${OPENDKIM_SELECTOR}${DATE_NOW}.txt ]; then
    GenerateKeyOpenDKIM
else
    echo "Already generated the dkimkey with selector : ${OPENDKIM_SELECTOR}${DATE_NOW}"
fi
FixRightsOpenDKIM

cat /etc/dkimkeys/${OPENDKIM_SELECTOR}${DATE_NOW}.txt
echo
GoReadThis
echo
CheckOpenDKIMdnsKey

