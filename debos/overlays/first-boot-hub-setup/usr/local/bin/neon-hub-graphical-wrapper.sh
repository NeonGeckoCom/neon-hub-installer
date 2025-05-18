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

docker compose -f /home/neon/compose/neon-hub.yml up -d

# Wait for containers to start, keep waiting until they are running
SLEEP_INCREMENT=10 # Sleep duration in seconds per check
# Calculate how many sleep increments make up 5 minutes (300 seconds)
UPDATE_INTERVAL_COUNT=$(( (5 * 60) / SLEEP_INCREMENT ))
sleep_cycles_elapsed=0

while true; do
  if docker ps | grep -q "neon"; then
    RESULT=0
    break
  else
    sleep $SLEEP_INCREMENT
    sleep_cycles_elapsed=$((sleep_cycles_elapsed + 1))

    if [ "$sleep_cycles_elapsed" -ge "$UPDATE_INTERVAL_COUNT" ]; then
      kdialog --title "Neon Hub Setup" --passivepopup "Still waiting for Neon Hub services to start...\n\nThis can take up to an hour or more depending on your internet connection." 60
      sleep_cycles_elapsed=0 # Reset counter for the next 5-minute interval
    fi
  fi
done

if [ "$RESULT" = "0" ]; then
  kdialog --title "Setup Complete" --msgbox "Your system has been successfully configured!\n\nWelcome to your new Neon Hub.\n\nMore information can be found at https://neongeckocom.github.io/neon-hub-installer/"
  mv /home/neon/.config/autostart/neon-hub-setup.desktop /home/neon/.config/autostart/neon-hub-setup.desktop.done
fi
