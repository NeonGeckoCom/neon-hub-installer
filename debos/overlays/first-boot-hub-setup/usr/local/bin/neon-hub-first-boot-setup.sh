#!/bin/bash

# Debug mode - essential for troubleshooting first boot issues
set -x

# Log file for debugging startup issues
DEBUG_LOG="/tmp/neon-hub-setup-debug.log"

# Log initial execution with timestamp - critical for debugging
echo "$(date): SCRIPT STARTING" > "$DEBUG_LOG" 2>&1

# Exit codes:
# 0: Success or already completed
# 1: No network connection
# 2: Docker Compose command failed
# 3: Other error

FLAG_FILE="/etc/neon-hub-setup-complete"
COMPOSE_DIR="/home/neon/compose"
COMPOSE_FILE="${COMPOSE_DIR}/neon-hub.yml"
LOG_FILE="/var/log/neon-hub-first-boot-setup.log"
USER_NAME="neon"

# Ensure basic commands exist and are in PATH
which sudo >> "$DEBUG_LOG" 2>&1
which docker >> "$DEBUG_LOG" 2>&1
which nmcli >> "$DEBUG_LOG" 2>&1

# Function for logging with root privileges if needed
log() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$message" >&2
    echo "$message" >> "$DEBUG_LOG"
    
    # Try to write to log file, use sudo if not root
    if [ "$(id -u)" -eq 0 ]; then
        echo "$message" >> "$LOG_FILE"
    else
        echo "$message" | sudo tee -a "$LOG_FILE" >/dev/null
    fi
}

# Check if we can run with sudo (needed for some operations)
if [ "$(id -u)" -ne 0 ]; then
    if ! sudo -n true 2>/dev/null; then
        echo "This script needs sudo privileges for some operations." | tee -a "$DEBUG_LOG"
        echo "Please run with sudo or as root." | tee -a "$DEBUG_LOG"
        exit 3
    fi
fi

# Create log file if it doesn't exist
if [ ! -f "$LOG_FILE" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        touch "$LOG_FILE"
        chown "$USER_NAME":"$USER_NAME" "$LOG_FILE"
    else
        sudo mkdir -p "$(dirname "$LOG_FILE")"
        sudo touch "$LOG_FILE" 
        sudo chown "$USER_NAME":"$USER_NAME" "$LOG_FILE"
    fi
fi

# Check if setup already completed
if [ -f "$FLAG_FILE" ]; then
    log "First boot setup already completed."
    exit 0
fi

log "Starting Neon Hub first boot setup..."

# --- Check Network Connectivity ---
log "Checking network connectivity..."
# Use nmcli to check for a fully connected state
if ! nmcli general status | grep -q "connected"; then
    log "Error: Network connection not found or not fully connected."
    exit 1
fi
log "Network connection detected."

# --- Check Compose File ---
log "Checking for Docker Compose file at ${COMPOSE_FILE}..."
if [ ! -d "$COMPOSE_DIR" ]; then
    log "Error: Compose directory ${COMPOSE_DIR} not found."
    exit 3
fi

# Check file access as the correct user
if [ "$(id -un)" = "$USER_NAME" ]; then
    if [ ! -f "$COMPOSE_FILE" ]; then
        log "Error: Compose file ${COMPOSE_FILE} not found."
        exit 3
    fi
else
    if ! sudo -u "$USER_NAME" [ -f "$COMPOSE_FILE" ]; then
        log "Error: Compose file ${COMPOSE_FILE} not found or not accessible by user ${USER_NAME}."
        exit 3
    fi
fi
log "Docker Compose file found."

# --- Check Docker service ---
log "Checking Docker service status..."
if ! systemctl is-active --quiet docker; then
    log "Docker service is not running. Attempting to start it..."
    if ! sudo systemctl start docker; then
        log "Failed to start Docker service."
        exit 3
    fi
    log "Docker service started."
else
    log "Docker service is running."
fi

# --- Run Docker Compose ---
log "Attempting to start services using Docker Compose..."

# Run docker compose as the specified user
if [ "$(id -un)" = "$USER_NAME" ]; then
    # Already running as the correct user
    cd "$COMPOSE_DIR" && docker compose -f "$COMPOSE_FILE" up -d
    DOCKER_EXIT_CODE=$?
else
    # Need to run as the correct user with sudo
    sudo -u "$USER_NAME" sh -c "cd \"$COMPOSE_DIR\" && docker compose -f \"$COMPOSE_FILE\" up -d"
    DOCKER_EXIT_CODE=$?
fi

if [ $DOCKER_EXIT_CODE -eq 0 ]; then
    log "Docker Compose command executed successfully."
else
    log "Error: Docker Compose command failed with exit code ${DOCKER_EXIT_CODE}."
    if [ -f "$LOG_FILE" ]; then
        log "Last 10 lines of log:"
        tail -n 10 "$LOG_FILE" | while IFS= read -r line; do log "  $line"; done
    fi
    exit 2
fi

# --- Create Flag File ---
log "Creating completion flag file: ${FLAG_FILE}"
if [ "$(id -u)" -eq 0 ]; then
    touch "$FLAG_FILE"
else
    sudo touch "$FLAG_FILE"
fi

if [ -f "$FLAG_FILE" ]; then
    log "Flag file created successfully."
else
    log "Error: Failed to create flag file ${FLAG_FILE}."
    exit 3
fi

log "Neon Hub first boot setup completed successfully."
exit 0 