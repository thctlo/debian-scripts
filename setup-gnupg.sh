#!/bin/bash

# Define your settings


# Set debian Frontent to noninteractive.
export DEBIAN_FRONTEND="noninteractive"

########CODE#################
# lsb-release and debconf-utils needs to be the first.
PACKAGE_BASE="lsb-release debconf-utils"

# Functions
CheckRootOrSudo(){
echo "Call function CheckRootOrSudo"
if [[ $UID -ge 1 ]]
then
    echo "Sorry, you need sudo or be 'root' to run this."
    echo "exiting now..."
    echo
    exit 1
fi
}
CheckPackageInstalled(){
#echo "Call function CheckPackageInstalled"
PACKAGE_INSTALLED=$(dpkg-query -W --showformat='${Status}\n' "${1}"|grep "install ok installed")
if [ "" == "${PACKAGE_INSTALLED}" ]
then
    echo "Package : ${1}, installing..."
    sudo apt-get -y install "${1}"
else
    echo "Package : ${1}, was already installed..."
fi
}
CheckPackageInstalledOk(){
echo "Call function CheckPackageInstalledOk"
## TODO-1, fix this, separate the debconf save function.
## fix save location
if true
then
    echo -n "Package : ${packageListed} : "
    if [ "${DEBCONF_SAVE_AUTO}" = true ]
    then
        sudo debconf-get-selections | grep "$packageListed" > debconf."$packageListed"
    else
        echo "Package : ${packageListed} : reported errors."
        echo "Exiting now, please check ${packageListed}"
        exit 1
    fi
fi
echo
}
InstallPackages(){
echo "Call function InstallPackages"
for packageListed in $PACKAGE_LIST
do
    CheckPackageInstalled "${packageListed}"
#FIX TODO-1 FIRST before enable.    CheckPackageInstalledOk
done
echo
}
RunAptUpdateQ(){
echo "Call function RunAptUpdateQ"
sudo apt-get update -q
}
CheckError(){
if [[ "$?" -eq 1 ]]
then
    echo "Error detected after package install.."
    exit 1
fi
}

Install_base() {
echo "Call function Install_base"
PACKAGE_LIST="${PACKAGE_BASE}"
InstallPackages
unset PACKAGE_LIST
}

Install_gnupg() {
echo "Call function Install_gnupg"
# Per Function packages.
PACKAGE_LIST="gnupg-agent gnupg pinentry-curses"
InstallPackages
unset PACKAGE_LIST
#
if [ ! -e ~/.gnupg/gpg.conf ]
then
cat << EOF >> ~/.gnupg/gpg.conf
# Default gpg.conf
# when outputting certificates, view user IDs distinctly from keys:
#fixed-list-mode

# long keyids are more collision-resistant than short keyids (it's trivial to make a key with any desired short keyid)
#keyid-format 0xlong

# when multiple digests are supported by all recipients, choose the strongest one:
personal-digest-preferences SHA512 SHA384 SHA256 SHA224

# preferences chosen for new keys should prioritize stronger algorithms:
default-preference-list SHA512 SHA384 SHA256 SHA224 AES256 AES192 AES CAST5 BZIP2 ZLIB ZIP Uncompressed

# when making an OpenPGP certification, use a stronger digest than the default SHA1:
cert-digest-algo SHA512

# If you use a graphical environment (and even if you don't) 
# you should be using an agent:
# (similar arguments as https://www.debian-administration.org/users/dkg/weblog/64)
use-agent

# You should always know at a glance which User IDs gpg thinks are legitimately
# bound to the keys in your keyring:
verify-options show-uid-validity
list-options show-uid-validity

# prevent version string from appearing in your signatures/public keys
no-emit-version

# All the keyservers periodically synchronize with each other, so you only need 
# to send your key to one of them.
#keyserver hkp://subkeys.pgp.net
keyserver hkp://pool.sks-keyservers.net
# Only for debian developerens/mentors/uploaders/packagers.
# gpg --keyserver hkp://keyring.debian.org --send-key YOURMASTERKEYID
# check the debian key server is your key is added to the debian keyring
# https://anonscm.debian.org/cgit/keyring/keyring.git/log/

# when useing pinentry, use or gpg --pinentry-mode loopback or enble the setting.
#pinentry-mode loopback
# Note: The upstream author indicates setting pinentry-mode loopback in gpg.conf.
# may break other usage, see gnupg-agent.conf

EOF
    echo "Please review the created ~/.gnupg/gpg.conf."
else
    echo "We detected an existing gpg.conf, no adjustment is done"
    echo "Please review if the following settings in ~/.gnupg/gpg.conf"
    echo
fi

if [ ! -e ~/.gnupg/gpg-agent.conf ]
then
cat << EOF >> ~/.gnupg/gpg-agent.conf
## Default gpg-agent.conf
##
## remember, after you made changes : gpg-connect-agent reloadagent /bye
## or logout and login again.

# Cache ttl for unused keys
default-cache-ttl 7200
# Tip: To cache your passphrase for the whole session, please run the following
# command: /usr/lib/gnupg/gpg-preset-passphrase --preset XXXXXX
# where XXXX is the keygrip. You can get its value when running gpg --with-keygrip -K.
# Passphrase will be stored until gpg-agent is restarted.
# If you set up default-cache-ttl value, it will take precedence.

# PIN entry program(s), you need one of these.
pinentry-program /usr/bin/pinentry-curses
# pinentry-program /usr/bin/pinentry-qt
# pinentry-program /usr/bin/pinentry-kwallet
# pinentry-program /usr/bin/pinentry-gtk-2
# pinentry-program /usr/bin/pinentry-tty

######## Unattended passphrase ########
##
# as of GnuPG 2.1.0 gpg-agent and pinentry is required,
# which may break backwards compatibility for passphrases piped in from STDIN using the --passphrase-fd 0
# to have the same type of functionality as the older releases two things must be done:
# allow loopback pinentry mode
# Restart the gpg-agent process if it is running to let the change take effect.
# Second, either the application needs to be updated to include a
# commandline parameter to use loopback mode like so: gpg --pinentry-mode loopback ...

# allow loopback pinentry mode
allow-loopback-pinentry

# gpg-agent has OpenSSH agent emulation
enable-ssh-support

# gpg-agent cache your keys for 3 hours:
default-cache-ttl-ssh 10800
EOF
else
    echo "We detected an existing gpg-agent.conf, no adjustment is done"
    echo "Please review if the following settings in ~/.gnupg/gnupg-agent.conf"
    echo "If needed add these if they are not there: "
    echo "pinentry-program /usr/bin/pinentry-curses # the Pin entry program use."
    echo "allow-loopback-pinentry # allow loopban pinentry mode"
    echo "enable-ssh-support # gpg-agent with openssh agent emulation"
    echo "default-cache-ttl-ssh 10800 # 3hour cache time."
    echo
fi
echo
echo "Please note the following."
echo "If you need X11 and/or X11 forwarding is enabled in ssh then you might need to set the following."
echo "type : unset DISPLAY"
echo
echo "Now gnupg is ready, you need to create keys if you dont have them."
echo "I suggest you start reading here, since it contains very good info."
echo "https://wiki.debian.org/GnuPG"
echo "https://wiki.debian.org/Keysigning"
echo "What the f... are SubKeys??? read:  https://wiki.debian.org/GnuPG/StubKeys"
echo "Using openPGP subkeys in Debian dev., https://wiki.debian.org/Subkeys"
echo
}

########################
#CheckRootOrSudo
RunAptUpdateQ
Install_base
Install_gnupg
