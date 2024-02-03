#!/bin/bash
# functions for the configuration script(s)

shopt -s nocasematch
set +e

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
	# set fastly mirrors
	# Enable non-free for Intel and other drivers, and ensure we have tools for the configuration
	cat <<EOF >/etc/xbps.d/00-repository-main.conf
repository=https://repo-fastly.voidlinux.org/current
repository=https://repo-fastly.voidlinux.org/current/nonfree
EOF
	# update xbps
	xbps-install -Suy xbps
	# add a few tools for the install and xtools for convenience always
	xbps-install -y xtools wget curl unzip
}

# functions in this file that start with an underscore i.e. "_configure_os" are
# called from within configuration()
configuration() {
	# Convention: directly install and enable packages that are services. The
	# rest are appended to "packages" and installed at the end of each
	# function.
	local packages=""
	_configure_os
	_configure_hardware

	# https://docs.voidlinux.org/config/index.html
	# Firmware already done

	# logging
	xbps-install -y socklog-void
	ln -sv /etc/sv/socklog-unix /var/service
	ln -sv /etc/sv/nanoklogd /var/service

	# Cron -https://docs.voidlinux.org/config/cron.html
	xbps-install -y snooze
	echo "TODO - implement fstrim weekly if not on ZFS"
	ln -svf /etc/sv/snooze-daily /var/service
	ln -svf /etc/sv/snooze-weekly /var/service

	# contribute usage info to Void Linux project
	xbps-install -y PopCorn
	ln -sv /etc/sv/popcorn /var/service

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
		# it's a server
		# advertise hostname to upstream dhcpd service
		if ! grep -Fxq "hostname" /etc/dhcpcd.conf; then
			echo "hostname" | tee -a /etc/dhcpcd.conf
		fi
		# server doesn't need wifi
		rm -f /var/service/wpa_supplicant
		# being a server, add terminfo for the two terminals I use, and tmux
		packages+=" alacritty-terminfo foot-terminfo tmux "
	fi
}

_configure_os() {
	# make wheel group passwordless for sudo
	echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' | tee /etc/sudoers.d/wheel
	# void doesn't generate a machine-id
	hostname | md5sum | cut -d ' ' -f 1 | tee /etc/machine-id

	# Not a fan of the caps lock key
	MAPFILE="/usr/share/kbd/keymaps/i386/qwerty/us.map"
	FIXMAPS="keycode  58 = Control"
	if ! zcat $MAPFILE | grep "$FIXMAPS"; then
		gunzip "$MAPFILE.gz"
		echo "$FIXMAPS" | tee -a $MAPFILE
		gzip $MAPFILE
		# in case this was a chroot install
		if ! grep -e "^KEYMAP=\"us\"" /etc/rc.conf; then
			echo "KEYMAP=\"us\"" | tee -a /etc/rc.conf
		fi
	fi
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

	# install and allow reconfiguration of linux if needed
	xbps-install -y $packages
	# finally update everything; likely that initramfs will be regenerated for a newer linux
	xbps-install -uy
}

_install_desktop_support() {
	local packages=""

	# text based display manager for all; enable after
	packages+=" emptty "
	if [ ! -z "$DO_XORG" ]; then
		# dwm on XOrg, dwl on Wayland. Notice a theme?
		packages+=" xorg-minimal xf86-input-evdev libinput xinit dwm st dmenu alacritty "
		# to build dwm
		packages+=" libXinerama libXinerama-devel "
		# and convenience tools for .xinitrc
		packages+=" xinput setxkbmap xss-lock slock xset feh dunst picom "
	fi
	if [ ! -z "$DO_WAYLAND" ]; then
		packages+=" foot wbg wlroots wayland wl-clipboard wlr-randr xorg-server-xwayland fuzzel wlsunset "
		# dwl not in Void packages as of Jan 2024
		# having to build a lot of components from source still (dwl, somebar)
		packages+=" wayland-devel wlroots-devel wayland-protocols "
		packages+=" libinput libinput-devel meson cairo cairo-devel pango pango-devel  "
	fi
	# common to both
	packages+=" gtk+3 xdg-dbus-proxy xdg-user-dirs xdg-user-dirs-gtk xdg-utils "
	packages+=" xdg-desktop-portal xdg-desktop-portal-gtk "
	# control brightness on laptops
	packages+=" brillo "
	# gui things for occasional use
	packages+=" nautilus gnome-disk-utility evince "

	# used by some gui apps, notably Google Chrome warning on startup
	packages+=" upower "

	xbps-install -y $packages
}

_install_fonts() {
	local packages=""
	packages+=" font-adobe-source-code-pro font-adobe-source-sans-pro-v2 font-adobe-source-serif-pro \
			cantarell-fonts font-crosextra-carlito-ttf dejavu-fonts-ttf fonts-droid-ttf \
            noto-fonts-emoji noto-fonts-ttf ttf-opensans fonts-roboto-ttf xorg-fonts "
	# I prefer Roboto Mono, which Void doesn't carry. Current nvim config demands a patched Nerd Font
	if ! [ -f /usr/share/fonts/TTF/nerd-fonts/RobotoMonoNerdFont-Regular.ttf ]; then
		ZIPFILE=$(mktemp)
		wget "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/RobotoMono.zip" -O $ZIPFILE
		mkdir -p /usr/share/fonts/TTF/nerdfonts
		unzip -d /usr/share/fonts/TTF/nerdfonts $ZIPFILE
		rm $ZIPFILE
		# higher order # overrides the dejavu files to follow
		cat <<EOF >/etc/fonts/conf.d/52-$HOSTNAME.conf
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <description>local overrides</description>
  <!-- Generic name assignment for RobotoMono-->
  <alias>
    <family>RobotoMono Nerd Font Mono</family>
    <default>
      <family>monospace</family>
    </default>
  </alias>

  <!-- monospace name aliasing for fonts we've installed on this machine -->
  <alias>
    <family>monospace</family>
    <prefer>
      <family>RobotoMono Nerd Font Mono</family>
      <family>Source Code Pro</family>
      <family>Noto Sans Mono</family>
      <family>DejaVu Sans Mono</family>
    </prefer>
  </alias>
</fontconfig>
EOF
		# force, really
		fc-cache -f -r
	fi
	xbps-install -y $packages
	ln -svf /usr/share/fontconfig/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/
	ln -svf /usr/share/fontconfig/conf.avail/10-hinting-slight.conf /etc/fonts/conf.d/
	xbps-reconfigure -f fontconfig
}

_install_applications() {
	# must haves
	local packages=""
	packages+=" firefox Signal-Desktop thunderbird rsync chezmoi neofetch go python3 htop glances "
	packages+=" git lazygit chezmoi base-devel"
	# TODO add the LazyVim toolset
	# for neovim
	packages+=" fd ripgrep python3-pip tree-sitter "
	xbps-install -y neovim
	# update alternatives
	xbps-alternatives -s neovim -g vi
	xbps-install -y $packages
}

configure_graphics() {

	local packages=""

	echo -e "\n# Graphics Setup #"
	echo -e "\nThis script installs graphics drivers to support XOrg and Wayland."

	echo -e "\nDetecting graphics cards:\n"

	AMDGPU="$(lspci | grep -i 'vga.*amd')"
	INTELGPU="$(lspci | grep -i 'vga.*intel')"
	NVIDIAGPU="$(lspci | grep -i 'vga.*nvidia')"
	if [ ! -z "$AMDGPU" ]; then
		echo "- $AMDGPU"
		if ask "Add driver for this card?" Y; then
			# common to all graphics systems
			packages+=" mesa-dri vulkan-loader "
			packages+=" linux-firmware-amd mesa-vulkan-radeon mesa-vaapi mesa-vdpau "
			if [ ! -z "$DO_XORG" ]; then
				packages+=" xf86-video-amdgpu "
			fi
		fi
	fi
	if [ ! -z "$INTELGPU" ]; then
		echo "- $INTELGPU"
		if ask "Add driver for this card?" Y; then
			# common to all graphics systems
			packages+=" mesa-dri vulkan-loader "
			packages+=" linux-firmware-intel intel-video-accel mesa-vulkan-intel "
			if [ ! -z "$DO_XORG" ]; then
				packages+=" xf86-video-intel "
			fi
		fi
	fi
	if [ ! -z "$NVIDIAGPU" ]; then
		echo "- $NVIDIAGPU"
		if ask "Add driver for this card? Warning: NVIDIA drivers problematic with Wayland" N; then
			# common to all graphics systems
			packages+=" mesa-dri vulkan-loader "
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
		getent group socklog >/dev/null
		if [ $? -eq 0 ]; then
			groups+=",socklog"
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
