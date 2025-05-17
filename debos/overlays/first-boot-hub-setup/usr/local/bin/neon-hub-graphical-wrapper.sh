#!/bin/bash

# This script runs the Neon Hub first boot setup for graphical KDE sessions.
# Verbose debug mode
set -x

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

SETUP_SCRIPT="/usr/local/bin/neon-hub-first-boot-setup.sh"
LOG_FILE="/var/log/neon-hub-first-boot-setup.log"
TITLE="Neon Hub Setup"

# Check if setup script exists
if [ ! -f "$SETUP_SCRIPT" ]; then
    echo "ERROR: Setup script $SETUP_SCRIPT not found!" >> "$WRAPPER_DEBUG_LOG"
    exit 1
fi

# Check if setup script is executable
if [ ! -x "$SETUP_SCRIPT" ]; then
    echo "ERROR: Setup script $SETUP_SCRIPT is not executable!" >> "$WRAPPER_DEBUG_LOG"
    chmod +x "$SETUP_SCRIPT" 2>> "$WRAPPER_DEBUG_LOG" || true
fi

# Define KDE notification functions with fallbacks
show_kde_notification() {
    local title="$1"
    local message="$2"
    local icon="$3"
    
    echo "Attempting to show notification: $title - $message" >> "$WRAPPER_DEBUG_LOG"
    
    # Try kdialog for notification
    if command -v kdialog >/dev/null 2>&1; then
        echo "Using kdialog" >> "$WRAPPER_DEBUG_LOG"
        kdialog --title "$title" --$icon "$message" 2>> "$WRAPPER_DEBUG_LOG" &
    # Fall back to qdbus for KNotify
    elif command -v qdbus >/dev/null 2>&1; then
        echo "Using qdbus" >> "$WRAPPER_DEBUG_LOG"
        qdbus org.kde.knotify /Notify eventId 'kde' '' "$title" "$message" "" "" 0 0 2>> "$WRAPPER_DEBUG_LOG" &
    # Fallback to zenity
    elif command -v zenity >/dev/null 2>&1; then
        echo "Using zenity" >> "$WRAPPER_DEBUG_LOG"
        zenity --$icon --title="$title" --text="$message" 2>> "$WRAPPER_DEBUG_LOG" &
    # Final fallback to console notification
    else
        echo "No notification tool found" >> "$WRAPPER_DEBUG_LOG"
        echo "$title: $message" >&2
    fi
}

# Check if we're in a KDE session
if [ -z "$KDE_FULL_SESSION" ] && [ -z "$XDG_CURRENT_DESKTOP" ]; then
    echo "WARNING: Not in a KDE session, attempting anyway" >> "$WRAPPER_DEBUG_LOG"
elif ! echo "$XDG_CURRENT_DESKTOP" | grep -q "KDE"; then
    echo "WARNING: XDG_CURRENT_DESKTOP doesn't include KDE, attempting anyway: $XDG_CURRENT_DESKTOP" >> "$WRAPPER_DEBUG_LOG"
fi

# Check if kstart5 is available for a systray icon (KDE specific)
if command -v kstart5 >/dev/null 2>&1; then
    # Show a systray icon while setup is running
    echo "Starting systray icon with kstart5" >> "$WRAPPER_DEBUG_LOG"
    kstart5 --quiet --windowclass "neon-hub-setup" \
        --icon "neon" --text "Setting up Neon Hub" \
        bash -c "sleep 2; echo 'Setup in progress'" >> "$WRAPPER_DEBUG_LOG" 2>&1 &
    KSTART_PID=$!
    # Make sure to kill the systray icon when we exit
    trap "kill $KSTART_PID 2>/dev/null" EXIT
else
    echo "kstart5 not found, skipping systray icon" >> "$WRAPPER_DEBUG_LOG"
fi

echo "Running setup script: $SETUP_SCRIPT" >> "$WRAPPER_DEBUG_LOG"

# Run the setup script, capturing the exit code and stderr for detailed error reporting
STDERR_OUTPUT=$("$SETUP_SCRIPT" 2>&1)
EXIT_CODE=$?

echo "Setup script completed with exit code: $EXIT_CODE" >> "$WRAPPER_DEBUG_LOG"
echo "Setup script output:" >> "$WRAPPER_DEBUG_LOG"
echo "$STDERR_OUTPUT" >> "$WRAPPER_DEBUG_LOG"

# Append stderr from the script itself to the main log file
echo "$STDERR_OUTPUT" | sudo tee -a "$LOG_FILE" >/dev/null

case $EXIT_CODE in
    0)
        # Success - show non-obtrusive notification with kdialog passive popup
        echo "SUCCESS: Setup completed" >> "$WRAPPER_DEBUG_LOG"
        if command -v kdialog >/dev/null 2>&1; then
            kdialog --passivepopup "Neon Hub services have been successfully started." 5 "Neon Hub Setup" 2>> "$WRAPPER_DEBUG_LOG" &
        else
            show_kde_notification "$TITLE" "Neon Hub services have been successfully started." "information"
        fi
        # Create marker file to prevent future notifications on success
        touch "$HOME/.config/neon-hub-setup-success" 2>> "$WRAPPER_DEBUG_LOG" || true
        exit 0
        ;;
    1)
        # No network
        echo "ERROR: No network connection" >> "$WRAPPER_DEBUG_LOG"
        show_kde_notification "$TITLE" "Network connection required for setup.\n\nPlease connect to the network using the panel applet.\nSetup will automatically retry on the next login." "sorry"
        
        # If kcmshell6 is available, offer to open network settings
        if command -v kcmshell6 >/dev/null 2>&1; then
            if kdialog --title "$TITLE" --yesno "Would you like to open network settings?" --yes-label "Open Settings" --no-label "Not Now" 2>> "$WRAPPER_DEBUG_LOG"; then
                kcmshell6 kcm_networkmanagement 2>> "$WRAPPER_DEBUG_LOG" &
            fi
        fi
        exit 1
        ;;
    2)
        # Docker error
        echo "ERROR: Docker error" >> "$WRAPPER_DEBUG_LOG"
        ERROR_DETAILS=$(echo "$STDERR_OUTPUT" | tail -n 10) # Get last few lines from stderr
        show_kde_notification "$TITLE" "Failed to start Neon Hub services (Docker error).\n\nDetails:\n${ERROR_DETAILS}\n\nFull details in ${LOG_FILE}.\nSetup will retry on the next login." "error"
        
        # Offer to show logs
        if command -v kdialog >/dev/null 2>&1 && command -v konsole >/dev/null 2>&1; then
            if kdialog --title "$TITLE" --yesno "Would you like to view the detailed logs?" --yes-label "View Logs" --no-label "Not Now" 2>> "$WRAPPER_DEBUG_LOG"; then
                konsole --hide-menubar --hide-tabbar -e bash -c "echo 'Neon Hub Setup Logs'; echo '================='; cat $LOG_FILE; echo; echo 'Press Enter to close'; read" 2>> "$WRAPPER_DEBUG_LOG" &
            fi
        fi
        exit 2
        ;;
    3)
        # Other error
        echo "ERROR: Unexpected error" >> "$WRAPPER_DEBUG_LOG"
        ERROR_DETAILS=$(echo "$STDERR_OUTPUT" | tail -n 10)
        show_kde_notification "$TITLE" "An unexpected error occurred during setup.\n\nDetails:\n${ERROR_DETAILS}\n\nFull details in ${LOG_FILE}.\nSetup will retry on the next login." "error"
        exit 3
        ;;
    *)
        # Unknown error
        echo "ERROR: Unknown error code: $EXIT_CODE" >> "$WRAPPER_DEBUG_LOG"
        ERROR_DETAILS=$(echo "$STDERR_OUTPUT" | tail -n 10)
        show_kde_notification "$TITLE" "An unknown error occurred during setup (Exit code: $EXIT_CODE).\n\nDetails:\n${ERROR_DETAILS}\n\nFull details in ${LOG_FILE}.\nSetup will retry on the next login." "error"
        exit $EXIT_CODE
        ;;
esac 