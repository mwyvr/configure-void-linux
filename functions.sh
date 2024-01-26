#!/bin/bash
# functions for the configuration script(s)

shopt -s nocasematch
set +e

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
HOSTNAME=""
TRUSTED_USER=""

CPUTYPE=""
AMDGPU=""
INTELGPU=""
NVIDIAGPU=""
DO_DESKTOP=""
DO_LAPTOP=""
DO_XORG=""
DO_WAYLAND=""
DO_BLUETOOTH=""
DO_LIBVIRT=""

initial_update() {
	echo -e "\n# Updating existing system packages #"
	# update xbps
	xbps-install -Suy xbps
	# Enable non-free for Intel and other drivers, and ensure we have tools for the configuration
	xbps-install -y void-repo-nonfree wget curl unzip
}

# functions in this file that start with an underscore i.e. "_configure_os" are
# called from within configuration()
configuration() {
	local packages=""
	_configure_os
	_configure_hardware

	# https://docs.voidlinux.org/config/index.html
	# Firmware already done

	# Cron -https://docs.voidlinux.org/config/cron.html
	xbps-install -y snooze
	# TODO - implement fstrim weekly if not on ZFS
	ln -svf /etc/sv/snooze-weekly /var/service

	# Power Management - https://docs.voidlinux.org/config/power-management.html
	# all machines will run dbus and elogind; if acpid integration with elogind
	# is desired, do that post-configure
	rm -f /var/service/acpid
	xbps-install -y dbus elogind
	ln -svf /etc/sv/dbus /var/service
	# elogind should not normally be started as a service; let dbus do it.

	if [ ! -z "$DO_LAPTOP" ]; then
		xbps-install -y tlp
		ln -svf /etc/sv/tlp /var/service
	fi

	# Network is done last, see below
	# Seat Management satisfied with dbus and elogind
	# Graphical Session

	if [ ! -z "$DO_DESKTOP" ]; then
		# Graphical Session
		_configure_graphics
		# XOrg, Wayland
		_install_desktop_support
		_install_fonts

		# Multimedia
		xbps-install -uy pipewire
		mkdir -p /etc/pipewire/pipewire.conf.d
		ln -svf /usr/share/examples/wireplumber/10-wireplumber.conf /etc/pipewire/pipewire.conf.d/
		ln -svf /usr/share/examples/pipewire/20-pipewire-pulse.conf /etc/pipewire/pipewire.conf.d/
		# autostart with Gnome (or add an .xprofile in ~/)
		# window managers will need to do this in their startup scripts.
		mkdir -p /etc/xdg/autostart
		ln -svf /usr/share/applications/pipewire.desktop /etc/xdg/autostart

		# bluetooth
		if [ ! -z "$DO_BLUETOOTH" ]; then
			xbps-install -uy bluez
			ln -svf /etc/sv/bluetoothd /var/service
		fi

		_install_applications
	fi

	# Virtualization
	if [ ! -z "$DO_LIBVIRT" ]; then
		xbps-install -y libvirt qemu
		if [ ! -z "$DO_DESKTOP" ]; then
			# insall gui tools
			xbps-install -y virt-manager virt-manager-tools qemu ddcutil
		fi
		ln -svf /etc/sv/libvirtd /var/service
		ln -svf /etc/sv/virtlockd /var/service
		ln -svf /etc/sv/virtlogd /var/service
	fi

	# Network - https://docs.voidlinux.org/config/network/index.html
	# Servers will run dhcpcd, all others NetworkManager
	if [ ! -z "$DO_DESKTOP" ]; then
		xbps-install -y NetworkManager
		ln -svf /etc/sv/NetworkManager /var/service
		rm -f /var/service/dhcpcd
	else
		# advertise hostname to upstream dhcpd service
		if ! grep -Fxq "hostname" /etc/dhcpcd.conf; then
			echo "hostname" | tee -a /etc/dhcpcd.conf
		fi
		# server doesn't need wifi
		rm -f /var/service/wpa_supplicant
	fi
}

_configure_os() {
	# make wheel group passwordless for sudo
	echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' | tee /etc/sudoers.d/wheel
	# void doesn't generate a machine-id
	hostname | md5sum | cut -d ' ' -f 1 | tee /etc/machine-id
}

_configure_hardware() {
	local packages=""

	# FIRMWARE
	# https://docs.voidlinux.org/config/firmware.html
	echo -e "\n# Identifying CPU Type #"
	# firmware
	CPUTYPE=$(lscpu | grep '^Vendor' | awk '{print $NF}')
	if [ "$CPUTYPE" = "GenuineIntel" ]; then
		packages+=" intel-ucode "
		echo "- INTEL CPU detected"
	fi
	if [ "$CPUTYPE" = "AuthenticAMD" ]; then
		packages+=" linux-firmware-amd "
		echo "- AMD CPU detected"
	fi

	# JAN 2024 the ath12k module prevents clean reboot and suspend on recent kernels
	ATHWIFI=$(lsmod | grep ath12k)
	if [ ! -z "$ATHWIFI" ]; then
		echo "- Disabling ath12k wifi kernel module via /etc/modprobe.d/"
		cat <<EOF >/etc/modprobe.d/10-ath12k.conf
blacklist ath12k
EOF
	fi

	# my Varmilo keyboard firmware IDs as an Apple; the function keys act as
	# media keys unless pressed with Fn button, which is annoying.
	VARMILO=$(lsmod | grep hid_apple)
	if [ ! -z "$VARMILO" ]; then
		echo "- Forcing Varmilo/hid_apple function keys as default (2)"
		# real time
		echo 2 >/sys/module/hid_apple/parameters/fnmode
		# make fix permanent; when initramfs rebuilt
		echo "options hid_apple fnmode=2" | tee /etc/modprobe.d/00-keyboardfix.conf
	fi

	# Not strictly 'hardware' but caps lock doesn't deserve to live
	cd /usr/share/kbd/keymaps/i386/qwerty
	gunzip us.map.gz
	echo "keycode 58 = Control" | tee -a us.map
	gzip us.map
	cd $INSTALL_DIR

	# install and allow reconfiguration of linux if needed
	xbps-install -y $packages
	# finally update everything; likely that initramfs will be regenerated for a newer linux
	xbps-install -uy
}

_install_desktop_support() {
	local packages=""

	if [ ! -z "$DO_XORG" ]; then
		packages+=" xorg-minimal xf86-input-evdev libinput xinput xinit dwm st dmenu "
	fi
	if [ ! -z "$DO_WAYLAND" ]; then
		packages+=" foot alacritty wlroots wayland wl-clipboard xorg-server-xwayland fuzzel"
		# having to build a lot of components from source still
		packages+=" wayland-devel wlroots-devel wayland-protocols "
		packages+=" libinput libinput-devel meson cairo cairo-devel pango pango-devel  "
	fi
	# common to both
	packages+=" gtk+3 xdg-dbus-proxy xdg-user-dirs xdg-user-dirs-gtk xdg-utils "
	packages+=" xdg-desktop-portal xdg-desktop-portal-gtk "
	# gui things for occasional use
	packages+=" nautilus gnome-disk-utility evince "

	# used by some gui apps, notably Google Chrome warning on startup
	packages+=" upower "

	xbps-install -y $packages
}

_install_fonts() {
	local packages=""
	packages+=" font-adobe-source-code-pro font-adobe-source-sans-pro-v2 font-adobe-source-serif-pro \
			dejavu-fonts-ttf fonts-droid-ttf noto-fonts-emoji noto-fonts-ttf "
	# I prefer Roboto Mono. Current nvim config demands a patched Nerd Font
	if ! [ -f /usr/share/fonts/TTF/RobotoMonoNerdFont-Regular.ttf ]; then
		ZIPFILE=$(mktemp)
		wget "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/RobotoMono.zip" -O $ZIPFILE
		unzip -d /usr/share/fonts/TTF $ZIPFILE
		rm $ZIPFILE
		cat <<EOF >/etc/fonts/conf.d/local.conf
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <description>local.conf override for monospace only, adding RobotoMono Nerd Font</description>
	<alias>
		<family>monospace</family>
		<prefer>
			<family>RobotoMono Nerd Font</family>
			<family>Noto Sans Mono</family>
			<family>DejaVu Sans Mono</family>
			<family>Inconsolata</family>
			<family>Andale Mono</family>
			<family>Courier New</family>
			<family>Cumberland AMT</family>
			<family>Luxi Mono</family>
			<family>Nimbus Mono L</family>
			<family>Nimbus Mono</family>
			<family>Nimbus Mono PS</family>
			<family>Courier</family>
		</prefer>
	</alias>
</fontconfig>
EOF
		# force, really
		fc-cache -f -r
	fi
	# ensure bitmap fonts not available
	ln -svf /usr/share/fontconfig/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/
	xbps-reconfigure -f fontconfig
	xbps-install -y $packages
}

_install_applications() {
	# must haves
	local packages=""
	packages+=" firefox Signal-Desktop thunderbird rsync chezmoi neofetch go python3 htop glances "
	packages+=" git lazygit chezmoi base-devel"
	# TODO add the LazyVim toolset
	# for neovim
	packages+=" fd python3-pip tree-sitter "
	xbps-install -y neovim
	# update alternatives
	xbps-alternatives -s neovim -g vi
	xbps-install -y $packages
}

configure_graphics() {

	local packages=""

	echo -e "\n# Graphics Setup #"
	echo -e "\nThis script installs graphics drivers to support XOrg and Wayland."

	# common to all graphics systems
	packages+=" mesa-dri vulkan-loader "

	echo -e "\nDetecting graphics cards:\n"

	AMDGPU="$(lspci | grep -i 'vga.*amd')"
	INTELGPU="$(lspci | grep -i 'vga.*intel')"
	NVIDIAGPU="$(lspci | grep -i 'vga.*nvidia')"
	if [ ! -z "$AMDGPU" ]; then
		echo "- $AMDGPU"
		if ask "Add driver for this card?" Y; then
			packages+=" linux-firmware-amd mesa-vulkan-radeon mesa-vaapi mesa-vdpau "
			if [ ! -z "$DO_XORG" ]; then
				packages+=" xf86-video-amdgpu "
			fi
		fi
	fi
	if [ ! -z "$INTELGPU" ]; then
		echo "- $INTELGPU"
		if ask "Add driver for this card?" Y; then
			packages+=" linux-firmware-intel intel-video-accel mesa-vulkan-intel "
			if [ ! -z "$DO_XORG" ]; then
				packages+=" xf86-video-intel "
			fi
		fi
	fi
	if [ ! -z "$NVIDIAGPU" ]; then
		echo "- $NVIDIAGPU"
		if ask "Add driver for this card? Warning: NVIDIA drivers problematic with Wayland" N; then
			packages+=" nvidia "
		fi
		# we blacklist nouveau anyway because until kernel 6.7 there's no support
		# for our 4060ti
		cat <<EOF >/usr/lib/modprobe.d/10-nouveau.conf
blacklist nouveau
EOF
	fi
	xbps-install -y $packages
}

setup_trusted_user() {
	local groups=""
	echo "# Adding trusted (sudo) user to groups #"
	getent passwd $TRUSTED_USER >/dev/null
	if [ $? -eq 0 ]; then
		# standard Void Linux groups in case was a chroot install
		groups+="audio,video,cdrom,floppy,optical,kvm,xbuilder"
		getent group libvirt >/dev/null
		if [ $? -eq 0 ]; then
			groups+=",libvirt"
		fi
		getent group bluetooth >/dev/null
		if [ $? -eq 0 ]; then
			groups+=",bluetooth"
		fi
		# script uses elogind but in case seatd replaces it one day..
		getent group _seatd >/dev/null
		if [ $? -eq 0 ]; then
			groups+=",_seatd"
		fi
		# getent group _flatpak >/dev/null
		# if [ $? -eq 0 ]; then
		# 	echo "Installing flatpak software repository for $USER (see gnome-software)"
		# fi
		usermod -aG $groups $TRUSTED_USER
		echo "$TRUSTED_USER added to: $groups"
	fi
}

ask() {
	#https://gist.github.com/karancode/f43bc93f9e47f53e71fa29eed638243c#file-ask-sh
	local prompt default reply

	if [[ ${2:-} = 'Y' ]]; then
		prompt='Y/n'
		default='Y'
	elif [[ ${2:-} = 'N' ]]; then
		prompt='y/N'
		default='N'
	else
		prompt='y/n'
		default=''
	fi

	while true; do
		echo -n "$1 [$prompt] "
		read -r reply </dev/tty
		# Default?
		if [[ -z $reply ]]; then
			reply=$default
		fi
		case "$reply" in
		Y* | y*) return 0 ;;
		N* | n*) return 1 ;;
		esac
	done
}
