#!/bin/bash

# This script runs the Neon Hub first boot setup for interactive non-GUI shells.

# Debug log to track execution of this profile script
PROFILE_DEBUG_LOG="/tmp/neon-hub-profile-debug.log"
echo "$(date): PROFILE SCRIPT EXECUTED" > "$PROFILE_DEBUG_LOG" 2>&1

FLAG_FILE="/etc/neon-hub-setup-complete"
SETUP_SCRIPT="/usr/local/bin/neon-hub-first-boot-setup.sh"

# Log environment for debugging
echo "Shell: $SHELL" >> "$PROFILE_DEBUG_LOG"
echo "User: $(whoami)" >> "$PROFILE_DEBUG_LOG"
echo "HOME: $HOME" >> "$PROFILE_DEBUG_LOG"
echo "PWD: $(pwd)" >> "$PROFILE_DEBUG_LOG"
echo "PATH: $PATH" >> "$PROFILE_DEBUG_LOG"

# Determine if we're being sourced or executed
(return 0 2>/dev/null) && SOURCED=1 || SOURCED=0
echo "SOURCED=$SOURCED" >> "$PROFILE_DEBUG_LOG"

# Check if setup already completed
if [ -f "$FLAG_FILE" ]; then
    echo "Setup already completed." >> "$PROFILE_DEBUG_LOG"
    [ "$SOURCED" -eq 1 ] && return 0 || exit 0
fi

# Check if script exists and is executable
if [ ! -x "$SETUP_SCRIPT" ]; then
    echo "Setup script $SETUP_SCRIPT not found or not executable." >> "$PROFILE_DEBUG_LOG"
    [ "$SOURCED" -eq 1 ] && return 0 || exit 0
fi

# Check if interactive shell
case $- in
    *i*) echo "Interactive shell detected." >> "$PROFILE_DEBUG_LOG" ;;
    *) echo "Non-interactive shell, exiting." >> "$PROFILE_DEBUG_LOG"
       [ "$SOURCED" -eq 1 ] && return 0 || exit 0 ;;
esac

# Check if not a graphical session (heuristic: no $DISPLAY and not on tty1)
# Adjust tty check if your primary console login is different
if [ -n "$DISPLAY" ]; then
    echo "Display detected: $DISPLAY, exiting." >> "$PROFILE_DEBUG_LOG"
    [ "$SOURCED" -eq 1 ] && return 0 || exit 0
fi

# Try to get TTY information 
TTY=$(tty 2>/dev/null || echo "unknown")
echo "TTY: $TTY" >> "$PROFILE_DEBUG_LOG"

# Skip if this is tty1, as KDE will start there
if [ "$TTY" = "/dev/tty1" ]; then
    echo "On tty1, skipping to avoid conflict with GUI setup." >> "$PROFILE_DEBUG_LOG"
    [ "$SOURCED" -eq 1 ] && return 0 || exit 0
fi

echo "------------------------------------"
echo "Checking Neon Hub first boot setup..."
echo "------------------------------------"

# Run the setup script with full path, capturing the exit code
if ! "$SETUP_SCRIPT"; then
    EXIT_CODE=$?
    echo "Setup script exited with code $EXIT_CODE" >> "$PROFILE_DEBUG_LOG"
    echo
    case $EXIT_CODE in
        1)
            echo "Network connection is required for setup."
            echo "Please connect to the network (e.g., using 'sudo nmtui')"
            echo "and then log out and log back in to complete the setup."
            ;;
        2)
            echo "Error: Failed to start Docker services. Details logged to /var/log/neon-hub-first-boot-setup.log"
            echo "Please check the log file, resolve the issue, and then log out and log back in."
            ;;
        3)
            echo "Error: An unexpected error occurred during setup. Details logged to /var/log/neon-hub-first-boot-setup.log"
            echo "Please check the log file."
            ;;
        *)
            echo "Error: An unknown error occurred (exit code $EXIT_CODE). Check /var/log/neon-hub-first-boot-setup.log"
            ;;
    esac
    echo "------------------------------------"

else
    echo "Setup script completed successfully." >> "$PROFILE_DEBUG_LOG"
    echo "Neon Hub setup completed successfully."
    echo "------------------------------------"
fi

# Ensure proper exit
[ "$SOURCED" -eq 1 ] && return 0 || exit 0 