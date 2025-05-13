#!/bin/sh

# This script checks if the Neon Hub first boot setup still needs to run.
# It exits 0 if setup is needed, 1 otherwise.
# Used by neon-hub-setup.desktop X-KDE-Autostart-Condition

FLAG_FILE="/etc/neon-hub-setup-complete"

if [ -f "$FLAG_FILE" ]; then
    # Setup is complete, condition is false (exit 1)
    exit 1
else
    # Setup is needed, condition is true (exit 0)
    exit 0
fi 