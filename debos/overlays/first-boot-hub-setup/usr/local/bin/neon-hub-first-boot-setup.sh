#!/bin/sh

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

# Check if setup already completed
if [ -f "$FLAG_FILE" ]; then
    echo "First boot setup already completed." | tee -a "$LOG_FILE"
    exit 0
fi

# Ensure log directory exists and set permissions
sudo mkdir -p "$(dirname "$LOG_FILE")"
sudo touch "$LOG_FILE"
sudo chown "$USER_NAME":"$USER_NAME" "$LOG_FILE"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_FILE" >&2
}

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
if ! sudo -u "$USER_NAME" [ -f "$COMPOSE_FILE" ]; then
    log "Error: Compose file ${COMPOSE_FILE} not found or not accessible by user ${USER_NAME}."
    exit 3
fi
log "Docker Compose file found."

# --- Run Docker Compose ---
log "Attempting to start services using Docker Compose..."

# Run docker compose as the specified user, capturing output
DOCKER_CMD="docker compose -f \"${COMPOSE_FILE}\" up -d"
if sudo -u "$USER_NAME" sh -c "cd \"$COMPOSE_DIR\" && ${DOCKER_CMD}" >> "$LOG_FILE" 2>&1; then
    log "Docker Compose command executed successfully."
else
    DOCKER_EXIT_CODE=$?
    log "Error: Docker Compose command failed with exit code ${DOCKER_EXIT_CODE}. Check log ${LOG_FILE} for details."
    # Log the last few lines of the log file for easier debugging in wrapper scripts
    tail -n 10 "$LOG_FILE" >&2
    exit 2
fi

# --- Create Flag File ---
log "Creating completion flag file: ${FLAG_FILE}"
if sudo touch "$FLAG_FILE"; then
    log "Flag file created successfully."
else
    log "Error: Failed to create flag file ${FLAG_FILE}."
    exit 3
fi

log "Neon Hub first boot setup completed successfully."
exit 0 