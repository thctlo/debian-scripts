#!/bin/bash

# Systemd failure notifier.
# This script installs and configures whats needed to get an e-mail notify when
# a systemd services fails. 
# It used postfix and the mail command, 
# if these are not installed the script installs them for you.

# Todo, add other options to set the notify email.

# Version 1.0, released 12-oct-2021
# Tested on Debian 10/11

# Howto use/configure it.
# Set the email address.. and.. your should be done. ;-)
# Then place this file on your system and run it.
# If you move this file later on, please run it once at least.
# it will rewrite 1 file to match with the new path.

# Email adres which want the e-mail messages.
ADDRESS_TO="change@my-email.tld"

# You can change things below here, but its not really needed.
ADDRESS_FROM="$(hostname -s)@$(hostname -d)"

# The mail subject
MAIL_SUBJECT="Warning: $(hostname -s): Systemd service failure detected"

# The variable %1 is the %n passed from systemd alterter service
MAIL_ALERT_MSG="Warning, systemd service : ${1} failed."

# The needed packages to send out the mail
NEEDED_PKG="postfix mailutils"

# Copyright (C) Louis van Belle 2021
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

###### program
SCRIPT_FILENAME="$(basename "$0")"
SCRIPT_DIRNAME="$(echo "${PWD##+/}")"

if [[ $EUID -ne 0 ]]
then
    echo "This script must be run as root"
    exit 1
fi

# Optional if the script isn't in /usr/(s)bin/
export PATH="$SCRIPT_DIRNAME:$PATH"

## check if we can mail.
if [ ! $(command -v mail >/dev/null 2>&1) ]
then
    for CheckPackage in $NEEDED_PKG
    do
        if [ "$(dpkg -s ${CheckPackage} &>/dev/null)" = "1" ]
        then
            echo "Package was not yet installed : ${CheckPackage}, please wait, installing now..."
            apt-get install -y -q=2 --no-install-recommends "${CheckPackage}"
        fi
    done
fi

# Create a top-level drop-in for services:
# This adds OnFailure=failure-notification@%n to every service file.
if [ ! -e "/etc/systemd/system/service.d/toplevel-override.conf" ]
then
    if [ ! -d "/etc/systemd/system/service.d/" ]
    then
        mkdir -p "/etc/systemd/system/service.d/"
    fi
# Txt block
{
    echo "[Unit]"
    echo "OnFailure=failure-notification@%n"
} > /etc/systemd/system/service.d/toplevel-override.conf

# The service itself.
    if [ ! -e "/etc/systemd/system/failure-notification@.service" ]
    then
# Txt block
{
    echo "[Unit]"
    echo "Description=Send a notification about a failed systemd unit"
    echo "After=network.target"
    echo ""
    echo "[Service]"
    echo "Type=simple"
    echo "# The %i will be the name of the failed service unit and will be passed as argument to the script."
    echo "ExecStart=${SCRIPT_DIRNAME}/${SCRIPT_FILENAME} %i"
} > /etc/systemd/system/failure-notification@.service
    fi

else
    # We re-write the file in case the path changed of this script.
# Txt block
{
    echo "[Unit]"
    echo "Description=Send a notification about a failed systemd unit"
    echo "After=network.target"
    echo ""
    echo "[Service]"
    echo "Type=simple"
    echo "# The %i will be the name of the failed service unit and will be passed as argument to the script."
    echo "ExecStart=${SCRIPT_DIRNAME}/${SCRIPT_FILENAME} %i"
} > /etc/systemd/system/failure-notification@.service
fi

if [ ! -e "/etc/systemd/system/failure-notification@.service.d/toplevel-override.conf" ]
then
    if [ ! -d "/etc/systemd/system/failure-notification@.service.d/" ]
    then
        mkdir -p "/etc/systemd/system/failure-notification@.service.d/"
    fi
    if [ ! -e "/etc/systemd/system/failure-notification@.service.d/toplevel-override.conf" ]
    then
# Txt block
{
        echo "# In order to prevent a regression for instances of failure-notification@.service,"
        echo "# We create an drop-in configuration file with an empty value on OnFailure, as the top-level drop-in."
        echo "[Unit]"
        echo "OnFailure="
} > "/etc/systemd/system/failure-notification@.service.d/toplevel-override.conf"
    fi
fi

# Reload the systemd configs.
systemctl daemon-reload

STATUS_CHECK="Current failed;\r $(systemctl --state=failed)"

# Send mail
mail -s "${MAIL_SUBJECT}" "${ADDRESS_TO}" <<< $(echo -e "${MAIL_ALERT_MSG}\n\r${STATUS_CHECK}")
