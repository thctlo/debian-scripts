#!/bin/bash

# Systemd Service Failure Notifier.
# This script installs and configures whats needed to get an e-mail notify when
# a systemd services fails.
# It used postfix and the mail command,
# if these are not installed the script installs them for you.

# Version 1.0.1, released 25-oct-2021
# Tested on Debian 10/11
# Note, if you used version 1.0, please manually deleted the file created with it.

# Sources used:
# https://www.freedesktop.org/software/systemd/man/systemd.unit.html

# Howto use/configure it.
# Set the email address.. and.. your should be done. ;-)
# Then place this file on your system and run it.
# If you move this file later on, please run it once at least.
# it will rewrite some file to match with the new path.

# Email adres which want the e-mail messages.
ADDRESS_TO="emailaddress@example.com"

# You can change things below here, but its not really needed.
# Do note, make sure that you can mail from the domain $(hostname -d)
ADDRESS_FROM="$(hostname -s)@$(hostname -d)"

# The mail subject
MAIL_SUBJECT="Warning: ${1} service on $(hostname -s) failure detected"

# The variable %1 is the %n passed from systemd alert service
MAIL_ALERT_MSG="Warning: ${1} systemd service failed on $(hostname -s)."

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
# This adds OnFailure=failure-notification@%N to every service file.
if [ ! -e "/etc/systemd/system/service.d/10-toplevel-override-all.conf" ]
then
    if [ ! -d "/etc/systemd/system/service.d/" ]
    then
        mkdir -p "/etc/systemd/system/service.d/"
    fi
    # Txt block new
    {
    echo "# Part of the failure-notification service to recieve email on failures in systemd"
    echo "[Unit]"
    echo "OnFailure=failure-notification@%N.service"
    } > /etc/systemd/system/service.d/10-toplevel-override-all.conf
else
    # Txt block re-write.
    {
    echo "# Part of the failure-notification service to recieve email on failures in systemd"
    echo "[Unit]"
    echo "OnFailure=failure-notification@%N.service"
    } > /etc/systemd/system/service.d/10-toplevel-override-all.conf
fi

# The service itself.
if [ ! -e "/etc/systemd/system/failure-notification@.service" ]
then
    # Txt block new
    {
    echo "# Part of the failure-notification service to recieve email on failures in systemd"
    echo "[Unit]"
    echo "Description=Send a notification about a failed systemd unit"
    echo "# Optional, Enable if you need it."
    echo "#After=network.target"
    echo ""
    echo "[Service]"
    echo "Type=oneshot"
    echo "# Enable below, if you enable above (network.target) also and disable the oneshot."
    echo ""
    echo "#Type=simple"
    echo "# The %i will be the name of the failed service unit and will be passed as argument to the script."
    echo "ExecStart=${SCRIPT_DIRNAME}/${SCRIPT_FILENAME} %i"
    } > /etc/systemd/system/failure-notification@.service
else
    # Txt block re-write
    {
    echo "# Part of the failure-notification service to recieve email on failures in systemd"
    echo "[Unit]"
    echo "Description=Send a notification about a failed systemd unit"
    echo "# Optional, Enable if you need it."
    echo "#After=network.target"
    echo ""
    echo "[Service]"
    echo "Type=oneshot"
    echo "# Enable below, if you enable above (network.target) also and disable the oneshot."
    echo "#Type=simple"
    echo ""
    echo "# The %i will be the name of the failed service unit and will be passed as argument to the script."
    echo "ExecStart=${SCRIPT_DIRNAME}/${SCRIPT_FILENAME} %i"
    } > /etc/systemd/system/failure-notification@.service
fi

# Prevent failure regression on failure service.
if [ ! -e "/etc/systemd/system/failure-notification@.service.d/toplevel-override.conf" ]
then
    if [ ! -d "/etc/systemd/system/failure-notification@.service.d/" ]
    then
        mkdir -p "/etc/systemd/system/failure-notification@.service.d/"
    fi

    # Txt block new
    {
    echo "# In order to prevent a regression for instances of failure-notification@%N.service,"
    echo "# We create an drop-in configuration file with an empty value on OnFailure, as the top-level drop-in."
    echo "# Option2 is : ln -s /dev/null /etc/systemd/system/failure-notification@.service.d/10-toplevel-override-all.conf"
    echo "# and remove this file.
    echo "[Unit]"
    echo "OnFailure="
    } > "/etc/systemd/system/failure-notification@.service.d/10-toplevel-override-all.conf"
else
    # Txt block re-write
    {
    echo "# In order to prevent a regression for instances of failure-notification@%N.service,"
    echo "# We create an drop-in configuration file with an empty value on OnFailure, as the top-level drop-in."
    echo "# Option2 is : ln -s /dev/null /etc/systemd/system/failure-notification@.service.d/10-toplevel-override-all.conf"
    echo "# and remove this file.
    echo "[Unit]"
    echo "OnFailure="
    } > "/etc/systemd/system/failure-notification@.service.d/10-toplevel-override-all.conf"
fi

# Reload the systemd configs.
systemctl daemon-reload

STATUS_CHECK="Current failed;\r $(systemctl --state=failed)"

# Send mail
mail -r "${ADDRESS_FROM}" -s "${MAIL_SUBJECT}" "${ADDRESS_TO}" <<< $(echo -e "${MAIL_ALERT_MSG}\n\r${STATUS_CHECK}")
