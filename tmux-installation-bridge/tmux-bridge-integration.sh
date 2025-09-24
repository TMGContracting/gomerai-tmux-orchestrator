#!/bin/bash
#
# GomerAI Tmux Bridge Integration Script
# =====================================
# 
# This script integrates the MT5 Bridge into the main tmux installation.exe
# Called from the main installation orchestrator
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_SESSION_NAME="${TMUX_SESSION_NAME:-gomerai-installation}"
BRIDGE_TMUX_WINDOW="mt5-bridge"
INSTALLATION_LOG="${INSTALLATION_LOG:-/tmp/gomerai-installation.log}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [MT5-BRIDGE] $1"
    echo -e "${GREEN}${message}${NC}"
    echo "$message" >> "$INSTALLATION_LOG"
}

warn() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [MT5-BRIDGE] WARNING: $1"
    echo -e "${YELLOW}${message}${NC}"
    echo "$message" >> "$INSTALLATION_LOG"
}

error() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [MT5-BRIDGE] ERROR: $1"
    echo -e "${RED}${message}${NC}"
    echo "$message" >> "$INSTALLATION_LOG"
}

info() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [MT5-BRIDGE] INFO: $1"
    echo -e "${BLUE}${message}${NC}"
    echo "$message" >> "$INSTALLATION_LOG"
}

# Check if we're running in tmux
check_tmux_session() {
    if [[ -z "$TMUX" ]]; then
        error "This script must be run within a tmux session"
        error "Expected to be called from main installation.exe orchestrator"
        exit 1
    fi
    
    local current_session=$(tmux display-message -p '#S')
    log "Running in tmux session: $current_session"
    
    # Set the session name for child processes
    export TMUX_INSTALL_SESSION="$current_session"
}

# Create dedicated tmux window for bridge installation
create_bridge_window() {
    log "Creating dedicated tmux window for MT5 Bridge installation..."
    
    # Check if window already exists
    if tmux list-windows -t "$TMUX_SESSION_NAME" | grep -q "$BRIDGE_TMUX_WINDOW"; then
        warn "Bridge window already exists, using existing window"
        tmux select-window -t "$TMUX_SESSION_NAME:$BRIDGE_TMUX_WINDOW"
    else
        # Create new window
        tmux new-window -t "$TMUX_SESSION_NAME" -n "$BRIDGE_TMUX_WINDOW" -c "$SCRIPT_DIR"
        log "Created tmux window: $BRIDGE_TMUX_WINDOW"
    fi
}

# Install bridge components in tmux window
install_bridge_in_tmux() {
    log "Installing MT5 Bridge components in tmux window..."
    
    # Send installation command to the bridge window
    local install_cmd="cd '$SCRIPT_DIR' && ./install-mt5-bridge.sh"
    
    tmux send-keys -t "$TMUX_SESSION_NAME:$BRIDGE_TMUX_WINDOW" "$install_cmd" C-m
    
    # Wait for installation to complete
    local max_wait=300  # 5 minutes
    local wait_count=0
    
    info "Waiting for bridge installation to complete (max ${max_wait}s)..."
    
    while [[ $wait_count -lt $max_wait ]]; do
        # Check if installation is complete by looking for success message
        local pane_content=$(tmux capture-pane -t "$TMUX_SESSION_NAME:$BRIDGE_TMUX_WINDOW" -p)
        
        if echo "$pane_content" | grep -q "MT5 Bridge installation completed successfully"; then
            log "Bridge installation completed successfully"
            return 0
        elif echo "$pane_content" | grep -q "ERROR\|FAILED"; then
            error "Bridge installation failed"
            return 1
        fi
        
        sleep 5
        wait_count=$((wait_count + 5))
        
        # Show progress every 30 seconds
        if [[ $((wait_count % 30)) -eq 0 ]]; then
            info "Still waiting for bridge installation... (${wait_count}s elapsed)"
        fi
    done
    
    error "Bridge installation timed out after ${max_wait} seconds"
    return 1
}

# Start bridge service in tmux window
start_bridge_service() {
    log "Starting MT5 Bridge service in tmux window..."
    
    # Create a new pane for the bridge service
    tmux split-window -t "$TMUX_SESSION_NAME:$BRIDGE_TMUX_WINDOW" -v -c "$HOME/.gomerai/mt5-bridge"
    
    # Start the bridge launcher in the new pane
    local start_cmd="node bridge-launcher.js"
    tmux send-keys -t "$TMUX_SESSION_NAME:$BRIDGE_TMUX_WINDOW.1" "$start_cmd" C-m
    
    # Wait for service to start
    sleep 10
    
    # Check if service is running
    if check_bridge_health; then
        log "Bridge service started successfully"
        return 0
    else
        error "Bridge service failed to start"
        return 1
    fi
}

# Check bridge health
check_bridge_health() {
    local health_url="http://127.0.0.1:9876/health"
    local max_attempts=6
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if command -v curl &> /dev/null; then
            if curl -s -f "$health_url" > /dev/null 2>&1; then
                info "Bridge health check passed (attempt $attempt)"
                return 0
            fi
        elif command -v wget &> /dev/null; then
            if wget -q --spider "$health_url" 2>/dev/null; then
                info "Bridge health check passed (attempt $attempt)"
                return 0
            fi
        fi
        
        info "Bridge health check failed (attempt $attempt/$max_attempts)"
        sleep 5
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Setup bridge monitoring in tmux
setup_bridge_monitoring() {
    log "Setting up bridge monitoring in tmux..."
    
    # Create monitoring pane
    tmux split-window -t "$TMUX_SESSION_NAME:$BRIDGE_TMUX_WINDOW" -h -c "$HOME/.gomerai/mt5-bridge"
    
    # Start monitoring command
    local monitor_cmd="watch -n 30 'curl -s http://127.0.0.1:9876/status | jq . 2>/dev/null || echo \"Bridge Status: Checking...\"'"
    tmux send-keys -t "$TMUX_SESSION_NAME:$BRIDGE_TMUX_WINDOW.2" "$monitor_cmd" C-m
    
    # Set pane titles
    tmux select-pane -t "$TMUX_SESSION_NAME:$BRIDGE_TMUX_WINDOW.0" -T "Installation"
    tmux select-pane -t "$TMUX_SESSION_NAME:$BRIDGE_TMUX_WINDOW.1" -T "Bridge Service"
    tmux select-pane -t "$TMUX_SESSION_NAME:$BRIDGE_TMUX_WINDOW.2" -T "Monitoring"
    
    log "Bridge monitoring setup complete"
}

# Create bridge status summary for main installation
create_bridge_status_summary() {
    local status_file="/tmp/gomerai-bridge-status.json"
    
    log "Creating bridge status summary..."
    
    # Get bridge status
    local bridge_status="unknown"
    local bridge_port="9876"
    local bridge_endpoints=""
    
    if check_bridge_health; then
        bridge_status="healthy"
        bridge_endpoints=$(cat << EOF
{
    "ingest": "http://127.0.0.1:9876/ingest",
    "token": "http://127.0.0.1:9876/token",
    "dashboard": "http://127.0.0.1:9876/dashboard",
    "ml_snapshot": "http://127.0.0.1:9876/ml-snapshot",
    "health": "http://127.0.0.1:9876/health",
    "status": "http://127.0.0.1:9876/status"
}
EOF
        )
    else
        bridge_status="unhealthy"
        bridge_endpoints="{}"
    fi
    
    # Create status JSON
    cat > "$status_file" << EOF
{
    "component": "mt5-bridge",
    "status": "$bridge_status",
    "installation_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "version": "1.0.0",
    "port": $bridge_port,
    "endpoints": $bridge_endpoints,
    "install_directory": "$HOME/.gomerai/mt5-bridge",
    "log_directory": "$HOME/.gomerai/logs",
    "tmux_window": "$BRIDGE_TMUX_WINDOW",
    "service_type": "tmux-managed"
}
EOF
    
    log "Bridge status summary created: $status_file"
    
    # Also create a human-readable summary
    local summary_file="/tmp/gomerai-bridge-summary.txt"
    cat > "$summary_file" << EOF
GomerAI MT5 Bridge Installation Summary
======================================

Status: $bridge_status
Installation Time: $(date)
Version: 1.0.0

Bridge Endpoints:
- Health Check: http://127.0.0.1:9876/health
- Status: http://127.0.0.1:9876/status
- EA Ingest: http://127.0.0.1:9876/ingest
- Token Broker: http://127.0.0.1:9876/token
- Dashboard: http://127.0.0.1:9876/dashboard
- ML Snapshot: http://127.0.0.1:9876/ml-snapshot

Installation Directory: $HOME/.gomerai/mt5-bridge
Log Directory: $HOME/.gomerai/logs
Tmux Window: $BRIDGE_TMUX_WINDOW

Next Steps:
1. Copy mt5-bridge-config.mqh to MT5 Include directory
2. Update EA to use SmartWebRequest function
3. Test connectivity using bridge endpoints
4. Monitor bridge status in tmux window

EOF
    
    log "Bridge summary created: $summary_file"
}

# Display installation results
display_results() {
    log "MT5 Bridge tmux integration completed!"
    
    echo ""
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║              GomerAI MT5 Bridge - Tmux Integration           ║${NC}"
    echo -e "${PURPLE}║                        COMPLETED                             ║${NC}"
    echo -e "${PURPLE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${PURPLE}║ Tmux Session: ${TMUX_SESSION_NAME}${NC}"
    echo -e "${PURPLE}║ Bridge Window: ${BRIDGE_TMUX_WINDOW}${NC}"
    echo -e "${PURPLE}║ Service Status: $(check_bridge_health && echo "✅ Healthy" || echo "❌ Unhealthy")${NC}"
    echo -e "${PURPLE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${PURPLE}║ Bridge running at: http://127.0.0.1:9876${NC}"
    echo -e "${PURPLE}║ Health check: http://127.0.0.1:9876/health${NC}"
    echo -e "${PURPLE}║ Status: http://127.0.0.1:9876/status${NC}"
    echo -e "${PURPLE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${PURPLE}║ View bridge window: tmux select-window -t $BRIDGE_TMUX_WINDOW${NC}"
    echo -e "${PURPLE}║ Monitor logs: tail -f ~/.gomerai/logs/mt5-bridge.log${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Main integration function
main() {
    log "Starting MT5 Bridge tmux integration..."
    
    # Validate tmux environment
    check_tmux_session
    
    # Create dedicated window for bridge
    create_bridge_window
    
    # Install bridge components
    if ! install_bridge_in_tmux; then
        error "Bridge installation failed"
        exit 1
    fi
    
    # Start bridge service
    if ! start_bridge_service; then
        error "Bridge service startup failed"
        exit 1
    fi
    
    # Setup monitoring
    setup_bridge_monitoring
    
    # Create status summary
    create_bridge_status_summary
    
    # Display results
    display_results
    
    log "MT5 Bridge tmux integration completed successfully!"
    
    # Return to main installation window
    tmux select-window -t "$TMUX_SESSION_NAME:0" 2>/dev/null || true
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
