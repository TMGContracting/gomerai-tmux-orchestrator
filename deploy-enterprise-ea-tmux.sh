#!/bin/bash
#
# Enterprise-Shell-EA tmux Deployment Script for Google Cloud VM
# Creates and manages tmux session for EA-Enterprise integration
#

set -e

# Configuration
SESSION_NAME="enterprise-ea"
GC_PROJECT="gomerai-debugging-system"
GC_REGION="us-central1"
EA_SOURCE_DIR="/home/mark/Documents/GomerAI"
DEPLOYMENT_DIR="/opt/gomerai-enterprise"
LOG_DIR="/var/log/gomerai"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}SUCCESS:${NC} $1"
}

warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

error() {
    echo -e "${RED}ERROR:${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root"
        exit 1
    fi
}

# Check if tmux is installed
check_tmux() {
    if ! command -v tmux &> /dev/null; then
        error "tmux is not installed. Installing..."
        sudo apt-get update && sudo apt-get install -y tmux
    fi
    success "tmux is available"
}

# Check if gcloud is installed and authenticated
check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "gcloud is not authenticated. Please run: gcloud auth login"
        exit 1
    fi
    
    success "gcloud is authenticated"
}

# Setup deployment directories
setup_directories() {
    log "Setting up deployment directories..."
    
    sudo mkdir -p "$DEPLOYMENT_DIR"
    sudo mkdir -p "$LOG_DIR"
    sudo chown -R $USER:$USER "$DEPLOYMENT_DIR"
    sudo chown -R $USER:$USER "$LOG_DIR"
    
    # Create subdirectories
    mkdir -p "$DEPLOYMENT_DIR/ea-source"
    mkdir -p "$DEPLOYMENT_DIR/enterprise-functions"
    mkdir -p "$DEPLOYMENT_DIR/scripts"
    mkdir -p "$DEPLOYMENT_DIR/data"
    mkdir -p "$DEPLOYMENT_DIR/persistence"
    
    success "Deployment directories created"
}

# Copy EA and related files
copy_ea_files() {
    log "Copying Enterprise-Shell-EA files..."
    
    if [[ -f "$EA_SOURCE_DIR/Enterprise-Shell-EA.mq5" ]]; then
        cp "$EA_SOURCE_DIR/Enterprise-Shell-EA.mq5" "$DEPLOYMENT_DIR/ea-source/"
        success "Enterprise-Shell-EA.mq5 copied"
    else
        error "Enterprise-Shell-EA.mq5 not found in $EA_SOURCE_DIR"
        exit 1
    fi
    
    # Copy setup guide
    if [[ -f "$EA_SOURCE_DIR/Enterprise-Shell-EA-Setup.md" ]]; then
        cp "$EA_SOURCE_DIR/Enterprise-Shell-EA-Setup.md" "$DEPLOYMENT_DIR/"
        success "Setup guide copied"
    fi
    
    # Copy AI Agent Orchestrator
    if [[ -f "$EA_SOURCE_DIR/ai-agent-orchestrator.py" ]]; then
        cp "$EA_SOURCE_DIR/ai-agent-orchestrator.py" "$DEPLOYMENT_DIR/"
        chmod +x "$DEPLOYMENT_DIR/ai-agent-orchestrator.py"
        success "AI Agent Orchestrator copied"
    fi
    
    # Copy MetaQuotes Forge Agent
    if [[ -f "$EA_SOURCE_DIR/metaquotes-forge-agent.py" ]]; then
        cp "$EA_SOURCE_DIR/metaquotes-forge-agent.py" "$DEPLOYMENT_DIR/"
        chmod +x "$DEPLOYMENT_DIR/metaquotes-forge-agent.py"
        success "MetaQuotes Forge Agent copied"
    fi
    
    # Copy any other relevant files
    if [[ -d "$EA_SOURCE_DIR/gomerai-iap-api-functions" ]]; then
        cp -r "$EA_SOURCE_DIR/gomerai-iap-api-functions" "$DEPLOYMENT_DIR/enterprise-functions/"
        success "Enterprise functions copied"
    fi
}

# Create tmux configuration
create_tmux_config() {
    log "Creating tmux configuration..."
    
    cat > "$DEPLOYMENT_DIR/.tmux.conf" << 'EOF'
# Enterprise-Shell-EA tmux configuration
set -g default-terminal "screen-256color"
set -g history-limit 10000
set -g base-index 1
setw -g pane-base-index 1

# Status bar
set -g status-bg colour234
set -g status-fg colour137
set -g status-left '#[fg=colour233,bg=colour245,bold] GomerAI Enterprise '
set -g status-right '#[fg=colour233,bg=colour245,bold] %d/%m %H:%M:%S '
set -g status-right-length 50
set -g status-left-length 30

# Window status
setw -g window-status-current-format ' #I#[fg=colour250]:#[fg=colour255]#W#[fg=colour50]#F '
setw -g window-status-format ' #I#[fg=colour237]:#[fg=colour250]#W#[fg=colour244]#F '

# Pane borders
set -g pane-border-fg colour238
set -g pane-active-border-fg colour51

# Key bindings
bind r source-file ~/.tmux.conf \; display-message "Config reloaded!"
bind | split-window -h
bind - split-window -v
EOF

    success "tmux configuration created"
}

# Create Enterprise monitoring script
create_monitoring_script() {
    log "Creating Enterprise monitoring script..."
    
    cat > "$DEPLOYMENT_DIR/scripts/monitor-enterprise.sh" << 'EOF'
#!/bin/bash
#
# Enterprise-Shell-EA Monitoring Script
#

LOG_FILE="/var/log/gomerai/enterprise-monitor.log"
FUNCTIONS_TO_MONITOR=(
    "ea-ingest-publisher"
    "token-broker" 
    "customer-dashboard"
    "email-automation"
    "ea-file-delivery"
    "customer-verification"
)

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_function_health() {
    local function_name=$1
    local url="https://us-central1-gomerai-debugging-system.cloudfunctions.net/$function_name"
    
    if [[ "$function_name" == "customer-dashboard" ]]; then
        url="$url/health"
    fi
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$url" --max-time 10)
    
    if [[ "$response" == "200" ]]; then
        echo "SUCCESS $function_name: HEALTHY"
        return 0
    else
        echo "ERROR $function_name: UNHEALTHY (HTTP $response)"
        return 1
    fi
}

# Main monitoring loop
log_message "Starting Enterprise monitoring..."

while true; do
    echo "=== Enterprise Health Check - $(date) ==="
    
    healthy_count=0
    total_count=${#FUNCTIONS_TO_MONITOR[@]}
    
    for func in "${FUNCTIONS_TO_MONITOR[@]}"; do
        if check_function_health "$func"; then
            ((healthy_count++))
        fi
    done
    
    echo "Health Status: $healthy_count/$total_count functions healthy"
    
    if [[ $healthy_count -eq $total_count ]]; then
        log_message "All Enterprise functions healthy ($healthy_count/$total_count)"
    else
        log_message "WARNING: $((total_count - healthy_count)) functions unhealthy"
    fi
    
    echo "----------------------------------------"
    sleep 60  # Check every minute
done
EOF

    chmod +x "$DEPLOYMENT_DIR/scripts/monitor-enterprise.sh"
    success "Enterprise monitoring script created"
}

# Create data persistence script
create_persistence_script() {
    log "Creating data persistence script..."
    
    cat > "$DEPLOYMENT_DIR/scripts/manage-persistence.sh" << 'EOF'
#!/bin/bash
#
# Enterprise-Shell-EA Data Persistence Management
#

PERSISTENCE_DIR="/opt/gomerai-enterprise/persistence"
GCS_BUCKET="gomerai-customer-data"
LOG_FILE="/var/log/gomerai/persistence.log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Backup local persistence data to GCS
backup_to_gcs() {
    log_message "Starting backup to GCS..."
    
    if [[ -d "$PERSISTENCE_DIR" ]]; then
        # Create timestamp
        timestamp=$(date +"%Y%m%d_%H%M%S")
        
        # Create tar archive
        tar -czf "/tmp/persistence_backup_$timestamp.tar.gz" -C "$PERSISTENCE_DIR" .
        
        # Upload to GCS
        if gsutil cp "/tmp/persistence_backup_$timestamp.tar.gz" "gs://$GCS_BUCKET/backups/"; then
            log_message "Backup successful: persistence_backup_$timestamp.tar.gz"
            rm "/tmp/persistence_backup_$timestamp.tar.gz"
        else
            log_message "ERROR: Backup failed"
        fi
    else
        log_message "WARNING: Persistence directory not found"
    fi
}

# Restore persistence data from GCS
restore_from_gcs() {
    local backup_file=$1
    
    if [[ -z "$backup_file" ]]; then
        log_message "ERROR: No backup file specified"
        return 1
    fi
    
    log_message "Restoring from GCS: $backup_file"
    
    # Download from GCS
    if gsutil cp "gs://$GCS_BUCKET/backups/$backup_file" "/tmp/"; then
        # Extract to persistence directory
        mkdir -p "$PERSISTENCE_DIR"
        tar -xzf "/tmp/$backup_file" -C "$PERSISTENCE_DIR"
        log_message "Restore successful: $backup_file"
        rm "/tmp/$backup_file"
    else
        log_message "ERROR: Restore failed"
    fi
}

# Clean old backups (keep last 10)
clean_old_backups() {
    log_message "Cleaning old backups..."
    gsutil ls -l "gs://$GCS_BUCKET/backups/" | sort -k2 | head -n -10 | awk '{print $3}' | while read file; do
        if [[ -n "$file" ]]; then
            gsutil rm "$file"
            log_message "Deleted old backup: $(basename $file)"
        fi
    done
}

case "$1" in
    backup)
        backup_to_gcs
        ;;
    restore)
        restore_from_gcs "$2"
        ;;
    clean)
        clean_old_backups
        ;;
    *)
        echo "Usage: $0 {backup|restore <file>|clean}"
        exit 1
        ;;
esac
EOF

    chmod +x "$DEPLOYMENT_DIR/scripts/manage-persistence.sh"
    success "Data persistence script created"
}

# Create deployment script for GC Functions
create_function_deploy_script() {
    log "Creating GC Functions deployment script..."
    
    cat > "$DEPLOYMENT_DIR/scripts/deploy-functions.sh" << 'EOF'
#!/bin/bash
#
# Deploy Enterprise Functions to Google Cloud
#

set -e

PROJECT_ID="gomerai-debugging-system"
REGION="us-central1"
FUNCTIONS_DIR="/opt/gomerai-enterprise/enterprise-functions/gomerai-iap-api-functions"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

deploy_function() {
    local function_name=$1
    local trigger_type=$2
    local entry_point=$3
    
    log_message "Deploying function: $function_name"
    
    cd "$FUNCTIONS_DIR/$function_name"
    
    if [[ "$trigger_type" == "http" ]]; then
        gcloud functions deploy "$function_name" \
            --gen2 \
            --runtime=nodejs20 \
            --region="$REGION" \
            --source=. \
            --entry-point="$entry_point" \
            --trigger-http \
            --allow-unauthenticated \
            --memory=1GB \
            --timeout=60s \
            --project="$PROJECT_ID"
    elif [[ "$trigger_type" == "pubsub" ]]; then
        local topic_name=$4
        gcloud functions deploy "$function_name" \
            --gen2 \
            --runtime=nodejs20 \
            --region="$REGION" \
            --source=. \
            --entry-point="$entry_point" \
            --trigger-topic="$topic_name" \
            --memory=1GB \
            --timeout=60s \
            --project="$PROJECT_ID"
    fi
    
    log_message "SUCCESS $function_name deployed successfully"
}

# Deploy core functions
log_message "Starting Enterprise functions deployment..."

deploy_function "ea-ingest-publisher" "http" "eaIngestPublisher"
deploy_function "token-broker" "http" "tokenBroker"
deploy_function "customer-dashboard" "http" "customerDashboard"
deploy_function "email-automation" "http" "emailAutomation"
deploy_function "ea-file-delivery" "http" "eaFileDelivery"
deploy_function "customer-verification" "http" "customerVerification"

log_message "All Enterprise functions deployed successfully!"
EOF

    chmod +x "$DEPLOYMENT_DIR/scripts/deploy-functions.sh"
    success "Function deployment script created"
}

# Create main tmux session
create_tmux_session() {
    log "Creating tmux session: $SESSION_NAME"
    
    # Kill existing session if it exists
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    
    # Create new session with first window
    tmux new-session -d -s "$SESSION_NAME" -c "$DEPLOYMENT_DIR"
    
    # Rename first window to 'main'
    tmux rename-window -t "$SESSION_NAME:0" 'main'
    
    # Window 1: AI Agent Orchestrator
    tmux new-window -t "$SESSION_NAME" -n 'orchestrator' -c "$DEPLOYMENT_DIR"
    tmux send-keys -t "$SESSION_NAME:orchestrator" 'python3 ai-agent-orchestrator.py' Enter
    
    # Window 2: Enterprise Monitoring
    tmux new-window -t "$SESSION_NAME" -n 'monitor' -c "$DEPLOYMENT_DIR"
    tmux send-keys -t "$SESSION_NAME:monitor" './scripts/monitor-enterprise.sh' Enter
    
    # Window 3: GC Functions Logs
    tmux new-window -t "$SESSION_NAME" -n 'logs' -c "$DEPLOYMENT_DIR"
    tmux send-keys -t "$SESSION_NAME:logs" 'gcloud functions logs tail ea-ingest-publisher --region=us-central1' Enter
    
    # Window 4: Data Persistence
    tmux new-window -t "$SESSION_NAME" -n 'persistence' -c "$DEPLOYMENT_DIR"
    tmux send-keys -t "$SESSION_NAME:persistence" 'watch -n 300 ./scripts/manage-persistence.sh backup' Enter
    
    # Window 5: System Stats
    tmux new-window -t "$SESSION_NAME" -n 'stats' -c "$DEPLOYMENT_DIR"
    tmux send-keys -t "$SESSION_NAME:stats" 'htop' Enter
    
    # Window 6: Deploy & Control
    tmux new-window -t "$SESSION_NAME" -n 'deploy' -c "$DEPLOYMENT_DIR"
    
    # Create split panes in deploy window
    tmux split-window -h -t "$SESSION_NAME:deploy"
    tmux split-window -v -t "$SESSION_NAME:deploy.0"
    tmux split-window -v -t "$SESSION_NAME:deploy.2"
    
    # Label the panes
    tmux send-keys -t "$SESSION_NAME:deploy.0" 'echo "=== GC Functions Deployment ===" && echo "Run: ./scripts/deploy-functions.sh"' Enter
    tmux send-keys -t "$SESSION_NAME:deploy.1" 'echo "=== Enterprise Status ===" && gcloud functions list --region=us-central1 --filter="name~gomerai"' Enter
    tmux send-keys -t "$SESSION_NAME:deploy.2" 'echo "=== Data Persistence ===" && echo "backup: ./scripts/manage-persistence.sh backup"' Enter
    tmux send-keys -t "$SESSION_NAME:deploy.3" 'echo "=== System Control ===" && echo "EA Source: /opt/gomerai-enterprise/ea-source/"' Enter
    
    # Window 7: EA Development
    tmux new-window -t "$SESSION_NAME" -n 'ea-dev' -c "$DEPLOYMENT_DIR/ea-source"
    tmux send-keys -t "$SESSION_NAME:ea-dev" 'ls -la && echo "Enterprise-Shell-EA development workspace"' Enter
    
    # Window 8: MetaQuotes Forge Integration
    tmux new-window -t "$SESSION_NAME" -n 'forge' -c "$DEPLOYMENT_DIR"
    tmux send-keys -t "$SESSION_NAME:forge" 'python3 metaquotes-forge-agent.py' Enter
    
    # Create split panes in forge window for forge management
    tmux split-window -h -t "$SESSION_NAME:forge"
    tmux split-window -v -t "$SESSION_NAME:forge.0"
    
    # Label the forge panes
    tmux send-keys -t "$SESSION_NAME:forge.1" 'echo "=== MetaQuotes Market Status ===" && echo "Monitoring EA submissions and market distribution"' Enter
    tmux send-keys -t "$SESSION_NAME:forge.2" 'echo "=== Forge Commands ===" && echo "validate: python3 -c \"import metaquotes_forge_agent; agent.validate_ea_for_forge(ea_path)\"" && echo "submit: Auto-submission enabled for new EAs"' Enter
    
    # Go back to main window
    tmux select-window -t "$SESSION_NAME:main"
    
    success "tmux session '$SESSION_NAME' created with 8 windows + AI Agent Orchestrator + MetaQuotes Forge Agent"
}

# Create session management script
create_session_manager() {
    log "Creating session management script..."
    
    cat > "$DEPLOYMENT_DIR/tmux-session-manager.sh" << EOF
#!/bin/bash
#
# Enterprise-Shell-EA tmux Session Manager
#

SESSION_NAME="$SESSION_NAME"

case "\$1" in
    start)
        if tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
            echo "Session '\$SESSION_NAME' already exists. Attaching..."
            tmux attach-session -t "\$SESSION_NAME"
        else
            echo "Creating new session '\$SESSION_NAME'..."
            $0 create
        fi
        ;;
    create)
        bash "$DEPLOYMENT_DIR/deploy-enterprise-ea-tmux.sh" create_session_only
        ;;
    attach)
        tmux attach-session -t "\$SESSION_NAME"
        ;;
    list)
        tmux list-windows -t "\$SESSION_NAME"
        ;;
    kill)
        tmux kill-session -t "\$SESSION_NAME"
        echo "Session '\$SESSION_NAME' terminated"
        ;;
    status)
        if tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
            echo "Session '\$SESSION_NAME' is running"
            tmux list-windows -t "\$SESSION_NAME"
        else
            echo "Session '\$SESSION_NAME' is not running"
        fi
        ;;
    *)
        echo "Usage: \$0 {start|create|attach|list|kill|status}"
        echo ""
        echo "Commands:"
        echo "  start   - Start or attach to session"
        echo "  create  - Create new session (kill existing)"
        echo "  attach  - Attach to existing session"
        echo "  list    - List windows in session"
        echo "  kill    - Terminate session"
        echo "  status  - Show session status"
        exit 1
        ;;
esac
EOF

    chmod +x "$DEPLOYMENT_DIR/tmux-session-manager.sh"
    success "Session manager created"
}

# Create startup script for system boot
create_startup_script() {
    log "Creating system startup script..."
    
    cat > "$DEPLOYMENT_DIR/startup-enterprise-ea.sh" << 'EOF'
#!/bin/bash
#
# Enterprise-Shell-EA System Startup Script
# Add to crontab: @reboot /opt/gomerai-enterprise/startup-enterprise-ea.sh
#

DEPLOYMENT_DIR="/opt/gomerai-enterprise"
LOG_FILE="/var/log/gomerai/startup.log"
USER="mark"  # Change to your username

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Wait for system to be ready
sleep 30

log_message "Starting Enterprise-Shell-EA system..."

# Ensure directories exist
mkdir -p /var/log/gomerai
chown $USER:$USER /var/log/gomerai

# Start tmux session as user
su - $USER -c "cd $DEPLOYMENT_DIR && ./tmux-session-manager.sh start" &

log_message "Enterprise-Shell-EA startup complete"
EOF

    chmod +x "$DEPLOYMENT_DIR/startup-enterprise-ea.sh"
    success "Startup script created"
}

# Main deployment function
main() {
    log "Starting Enterprise-Shell-EA tmux deployment..."
    
    check_root
    check_tmux
    check_gcloud
    setup_directories
    copy_ea_files
    create_tmux_config
    create_monitoring_script
    create_persistence_script
    create_function_deploy_script
    create_tmux_session
    create_session_manager
    create_startup_script
    
    success "Enterprise-Shell-EA tmux deployment complete!"
    echo ""
    echo "NEXT STEPS:"
    echo "1. Attach to tmux session: cd $DEPLOYMENT_DIR && ./tmux-session-manager.sh attach"
    echo "2. Check AI Orchestrator: 'orchestrator' window shows agent coordination"
    echo "3. Deploy GC Functions: Go to 'deploy' window and run ./scripts/deploy-functions.sh"
    echo "4. Monitor Enterprise: Check 'monitor' window for function health"
    echo "5. Configure EA: Edit Enterprise-Shell-EA.mq5 in 'ea-dev' window"
    echo "6. MetaQuotes Forge: 'forge' window handles EA market distribution"
    echo ""
    echo "📋 Session Management:"
    echo "   Start/Attach: $DEPLOYMENT_DIR/tmux-session-manager.sh start"
    echo "   Status:       $DEPLOYMENT_DIR/tmux-session-manager.sh status"
    echo "   Kill:         $DEPLOYMENT_DIR/tmux-session-manager.sh kill"
    echo ""
    echo "📁 Important Paths:"
    echo "   EA Source:    $DEPLOYMENT_DIR/ea-source/Enterprise-Shell-EA.mq5"
    echo "   Scripts:      $DEPLOYMENT_DIR/scripts/"
    echo "   Logs:         /var/log/gomerai/"
    echo "   Persistence:  $DEPLOYMENT_DIR/persistence/"
}

# Handle special case for session creation only
if [[ "$1" == "create_session_only" ]]; then
    create_tmux_session
    exit 0
fi

# Run main deployment
main "$@"
EOF

chmod +x deploy-enterprise-ea-tmux.sh
success "Enterprise-Shell-EA tmux deployment script created"
