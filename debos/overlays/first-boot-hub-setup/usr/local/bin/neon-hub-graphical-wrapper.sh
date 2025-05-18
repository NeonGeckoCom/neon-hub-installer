#!/bin/bash
# Create debug log directory
WRAPPER_DEBUG_DIR="/tmp/neon-hub-logs"
mkdir -p "$WRAPPER_DEBUG_DIR"
WRAPPER_DEBUG_LOG="$WRAPPER_DEBUG_DIR/graphical-wrapper.log"

# Log start time and environment
echo "===========================================" > "$WRAPPER_DEBUG_LOG"
echo "$(date): GRAPHICAL WRAPPER STARTED" >> "$WRAPPER_DEBUG_LOG"
echo "USER: $(whoami)" >> "$WRAPPER_DEBUG_LOG"
echo "PWD: $(pwd)" >> "$WRAPPER_DEBUG_LOG" 
echo "PATH: $PATH" >> "$WRAPPER_DEBUG_LOG"
echo "DISPLAY: $DISPLAY" >> "$WRAPPER_DEBUG_LOG"
echo "XDG_CURRENT_DESKTOP: $XDG_CURRENT_DESKTOP" >> "$WRAPPER_DEBUG_LOG"
echo "KDE_FULL_SESSION: $KDE_FULL_SESSION" >> "$WRAPPER_DEBUG_LOG"
echo "===========================================" >> "$WRAPPER_DEBUG_LOG"

DEFAULT_TITLE="Neon Hub Setup"

# Check for internet connection
while true; do
  if kdialog --title "$DEFAULT_TITLE" --yesno "Please connect to the internet to complete Neon Hub setup.\n\nIs your internet connection ready?"; then
    # Test connection
    if ping -c 1 google.com &>/dev/null; then
      break
    else
      kdialog --title "$DEFAULT_TITLE" --error "Internet connection test failed. Please check your connection."
    fi
  fi
done

kdialog --title "$DEFAULT_TITLE" --msgbox "Starting Neon Hub setup...\n\nThis will take some time. You will receive a notification when it is complete."
declare -i RESULT
RESULT=$(docker compose -f /home/neon/compose/neon-hub.yml up)

if [ "$RESULT" = "0" ]; then
  kdialog --title "Setup Complete" --msgbox "Your system has been successfully configured!\n\nWelcome to your new Neon Hub.\n\nMore information can be found at https://neongeckocom.github.io/neon-hub-installer/"
  mv /home/neon/.config/autostart/neon-hub-setup.desktop /home/neon/.config/autostart/neon-hub-setup.desktop.done
else
  kdialog --title "Setup Warning" --sorry "There was an issue completing setup.\n\nMore information available at $WRAPPER_DEBUG_LOG.\n\nSetup can be run again by restarting the system."
fi
