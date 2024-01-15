#!/bin/bash
# install Roboto Mono family of fonts


BASE_URL=https://github.com/googlefonts/RobotoMono/raw/main/fonts/ttf
FONTS="RobotoMono-Bold.ttf RobotoMono-BoldItalic.ttf RobotoMono-Italic.ttf RobotoMono-Light.ttf RobotoMono-LightItalic.ttf RobotoMono-Medium.ttf RobotoMono-MediumItalic.ttf \
    RobotoMono-Regular.ttf RobotoMono-Thin.ttf RobotoMono-ThinItalic.ttf"
. /etc/os-release
if  [[ $ID="void" ]]; then
	FONTDIR="TTF"
else
	FONTDIR="truetype"
fi

# Must be root
if [ "$(id -u)" -ne 0 ]; then
	echo 'ERROR: This script must be run by root, aborting.' >&2
	exit 1
fi

LOCATION=/usr/share/fonts/$FONTDIR
mkdir -p $LOCATION

for FONT in $FONTS; do
	wget "$BASE_URL/$FONT" -O "$LOCATION/$FONT"
done

fc-cache -frv
