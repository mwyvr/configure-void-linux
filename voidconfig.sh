#!/bin/bash

. functions.sh
# set -e

main() {
	usage

	if ! ask "Proceed with configuration? " Y; then
		echo "Aborting."
		exit
	fi

	echo -e "\n# Hostname and sudo User #"
	HOSTNAME=$(hostname)
	NEWHOSTNAME=""
	if ! ask "The current hostname is: $HOSTNAME. Keep it?" Y; then
		read -p "New hostname: " NEWHOSTNAME
	fi
	if [ "$HOSTNAME" != "$NEWHOSTNAME" ]; then
		echo $NEWHOSTNAME | tee /etc/hostname
	fi

	while [ -z $TRUSTED_USER ]; do
		echo -e "\nProvide the username of your already created user for sudo."
		read -p "Username: " TRUSTED_USER
		getent passwd $TRUSTED_USER >/dev/null
		if [ $? -eq 0 ]; then
			break
		else
			echo "Username not found, try again."
			TRUSTED_USER=""
		fi
	done

	echo -e "\n# Installation Type #"
	if ask "Is this a desktop (workstation or laptop)? (no, for server)" Y; then
		DO_DESKTOP="desktop"
		if ask "Is this a laptop (requiring power management and other supports)" N; then
			DO_LAPTOP="yes"
		fi
		if ask "Configure for Bluetooth support?" N; then
			DO_BLUETOOTH="yes"
		fi
		if ask "Configure for Virtual Machine support?" N; then
			DO_LIBVIRT="yes"
		fi
	else
		SYSTEM_TYPE="server"
	fi

	if ! ask "Proceed with configuration? " Y; then
		echo "Aborting."
		exit
	fi
	initial_update
	configuration
	# run last as it tests for groups that may be created during package install
	setup_trusted_user
	echo -e "\n# Configuration complete #"
}

usage() {
	cat <<EOF

Void Linux Configuration 
------------------------

This configuration tool adds packages and configuration files where needed to
(nearly) complete a freshly installed system.

You'll be asked if it's a desktop (desktop workstation or laptop with a window
manager) or server (minimal installation).

Pre-requisites:

1. Void Linux installed on the target system.
2. This script copied to the target system.
3. Run this script as root.

EOF
	if [ "$(id -u)" -ne 0 ]; then
		echo 'ERROR: This script must be run by root, aborting.' >&2
		exit 1
	fi
}

main
