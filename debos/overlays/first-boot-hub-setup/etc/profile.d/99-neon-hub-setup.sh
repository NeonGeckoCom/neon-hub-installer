#!/bin/sh

# This script runs the Neon Hub first boot setup for interactive non-GUI shells.

FLAG_FILE="/etc/neon-hub-setup-complete"
SETUP_SCRIPT="/usr/local/bin/neon-hub-first-boot-setup.sh"

# Check if setup already completed
if [ -f "$FLAG_FILE" ]; then
    return 0
fi

# Check if interactive shell
case $- in
    *i*) ;;
      *) return 0;;
esac

# Check if not a graphical session (heuristic: no $DISPLAY and not on tty1)
# Adjust tty check if your primary console login is different
if [ -n "$DISPLAY" ] || [ "$(tty)" = "/dev/tty1" ]; then
    return 0
fi

echo "------------------------------------"
echo "Checking Neon Hub first boot setup..."
echo "------------------------------------"

# Run the setup script, capturing the exit code
if ! "$SETUP_SCRIPT"; then
    EXIT_CODE=$?
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
    echo "Neon Hub setup completed successfully."
    echo "------------------------------------"
fi 