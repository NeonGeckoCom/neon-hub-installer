#!/bin/sh

# This script runs the Neon Hub first boot setup for graphical KDE sessions.

SETUP_SCRIPT="/usr/local/bin/neon-hub-first-boot-setup.sh"
LOG_FILE="/var/log/neon-hub-first-boot-setup.log"
TITLE="Neon Hub First Boot Setup"

# Run the setup script, capturing the exit code and stderr for detailed error reporting
STDERR_OUTPUT=$("$SETUP_SCRIPT" 2>&1)
EXIT_CODE=$?

# Append stderr from the script itself to the main log file
echo "$STDERR_OUTPUT" | sudo tee -a "$LOG_FILE" > /dev/null

case $EXIT_CODE in
    0)
        # Success or already done - do nothing visual
        exit 0
        ;;
    1)
        # No network
        kdialog --title "$TITLE" --sorry "Network connection required for setup.\n\nPlease connect to the network using the panel applet.\nSetup will automatically retry on the next login." || zenity --error --title="$TITLE" --text="Network connection required for setup.\nPlease connect to the network.\nSetup will automatically retry on the next login."
        exit 1
        ;;
    2)
        # Docker error
        ERROR_DETAILS=$(echo "$STDERR_OUTPUT" | tail -n 10) # Get last few lines from stderr
        kdialog --title "$TITLE" --error "Failed to start Neon Hub services (Docker error).\n\nDetails:\n${ERROR_DETAILS}\n\nFull details in ${LOG_FILE}. Please resolve the issue.\nSetup will retry on the next login." || zenity --error --title="$TITLE" --text="Failed to start Neon Hub services (Docker error).\nSee ${LOG_FILE} for details. Please resolve the issue.\nSetup will retry on the next login."
        exit 2
        ;;
    3)
        # Other error
        ERROR_DETAILS=$(echo "$STDERR_OUTPUT" | tail -n 10)
        kdialog --title "$TITLE" --error "An unexpected error occurred during setup.\n\nDetails:\n${ERROR_DETAILS}\n\nFull details in ${LOG_FILE}.\nSetup will retry on the next login." || zenity --error --title="$TITLE" --text="An unexpected error occurred during setup.\nSee ${LOG_FILE} for details.\nSetup will retry on the next login."
        exit 3
        ;;
    *)
        # Unknown error
        ERROR_DETAILS=$(echo "$STDERR_OUTPUT" | tail -n 10)
        kdialog --title "$TITLE" --error "An unknown error occurred during setup (Exit code: $EXIT_CODE).\n\nDetails:\n${ERROR_DETAILS}\n\nFull details in ${LOG_FILE}.\nSetup will retry on the next login." || zenity --error --title="$TITLE" --text="An unknown error occurred during setup (Exit code: $EXIT_CODE).\nSee ${LOG_FILE} for details.\nSetup will retry on the next login."
        exit $EXIT_CODE
        ;;
esac 