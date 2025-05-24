#!/bin/bash
AUTOSTART_FILE="$HOME/.config/autostart/set-wallpaper.desktop"

/usr/bin/plasma-apply-wallpaperimage /opt/neon/splashscreen.png
rm -f "$AUTOSTART_FILE"
