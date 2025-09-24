#!/bin/bash

# gcp-vps-master-control.sh - GCP VPS optimized master controller
# Designed to run 24/7 on Google Cloud VPS

VERSION="1.0.0-GCP"
SCRIPT_DIR="/opt/gomerai"
MASTER_LOG="/var/log/gomerai/master-control.log"
STATUS_FILE="/var/log/gomerai/system-status"

# Ensure log directory exists
mkdir -p /var/log/gomerai

echo "GomerAI Enterprise Master Control v${VERSION} (GCP VPS)"
echo "Hardened Core + Agentic Edge Architecture"
echo "Running on: $(hostname)"
echo "Date: $(date)"
echo ""

log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$(hostname)] $1" | tee -a "$MASTER_LOG"
}

update_status() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" > "$STATUS_FILE"
}

show_vps_menu() {
    echo "=== GOMERAI GCP VPS MASTER CONTROL ==="
    echo "Running on: $(hostname)"
    echo "1. Deploy All Silos (Full System)"
    echo "2. Deploy Single Silo"
    echo "3. Start Continuous Monitoring"
    echo "4. Check System Status"
    echo "5. View Architecture Directive"
    echo "6. Emergency Stop All"
    echo "7. View Logs"
    echo "8. System Health Report"
    echo "9. Daemon Mode (24/7 Operation)"
    echo "10. Exit"
    echo ""
    echo -n "Select option [1-10]: "
}

check_gcp_prerequisites() {
    log_action "Checking GCP VPS prerequisites..."
    
    # Check if we're running on GCP
    if curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name &>/dev/null; then
        local instance_name=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
        log_action "Running on GCP instance: $instance_name"
    else
        log_action "WARNING: Not running on GCP instance"
    fi
    
    # Check if required scripts exist
    local required_scripts=("deploy-silo.sh" "tmux-launcher.sh" "silo-watchdog.sh")
    for script in "${required_scripts[@]}"; do
        if [[ ! -x "$SCRIPT_DIR/$script" ]]; then
            log_action "ERROR: $script not found in $SCRIPT_DIR"
            return 1
        fi
    done
    
    # Check if gcloud is configured
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        log_action "ERROR: gcloud not authenticated. Run: gcloud auth login"
        return 1
    fi
    
    log_action "GCP VPS prerequisites check: PASSED"
    update_status "READY"
    return 0
}

deploy_all_silos_vps() {
    log_action "Starting full system deployment from GCP VPS"
    update_status "DEPLOYING_ALL_SILOS"
    
    if ! check_gcp_prerequisites; then
        update_status "ERROR_PREREQUISITES"
        return 1
    fi
    
    echo "VPS Deployment Mode: This will deploy 13 functions to each silo"
    echo "  Silo 1: gomerai-debugging-system (live system)"
    echo "  Silo 2: gomerai-silo-2 (new mirror)"
    echo "  Silo 3: gomerai-silo-3 (new mirror)"
    echo ""
    echo "Total: 39 Cloud Functions will be deployed from this GCP VPS"
    echo ""
    read -p "Continue with VPS deployment? [y/N]: " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        log_action "User confirmed VPS full deployment"
        cd "$SCRIPT_DIR"
        
        # Kill any existing sessions
        tmux kill-session -t gomerai-deployment 2>/dev/null
        
        # Start deployment in tmux
        ./tmux-launcher.sh
        update_status "DEPLOYMENT_ACTIVE"
        log_action "Tmux orchestration started from GCP VPS"
        
        echo ""
        echo "Deployment started in tmux session 'gomerai-overwatcher'"
        echo "To monitor: tmux attach-session -t gomerai-overwatcher"
        echo "Session will persist on this GCP VPS"
    else
        log_action "User cancelled VPS deployment"
        update_status "READY"
        echo "Deployment cancelled"
    fi
}

start_continuous_monitoring() {
    log_action "Starting continuous monitoring from GCP VPS"
    update_status "MONITORING_ACTIVE"
    
    if tmux has-session -t gomerai-watchdog 2>/dev/null; then
        echo "Continuous monitoring already running"
        echo "Session: gomerai-watchdog"
    else
        cd "$SCRIPT_DIR"
        tmux new-session -d -s gomerai-watchdog "./silo-watchdog.sh"
        log_action "Continuous watchdog started on GCP VPS"
        echo "Continuous monitoring started on GCP VPS"
        echo "Session: gomerai-watchdog"
        echo "The watchdog will run 24/7 and monitor all silos"
    fi
}

check_gcp_system_status() {
    log_action "Checking GCP VPS system status"
    
    echo "=== GOMERAI GCP VPS SYSTEM STATUS ==="
    echo ""
    
    # Instance information
    if curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name &>/dev/null; then
        echo "GCP Instance: $(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)"
        echo "Zone: $(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)"
        echo "Machine Type: $(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/machine-type | cut -d/ -f4)"
    fi
    
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime)"
    echo ""
    
    # Current status
    if [[ -f "$STATUS_FILE" ]]; then
        echo "System Status: $(cat $STATUS_FILE)"
    else
        echo "System Status: Unknown"
    fi
    echo ""
    
    # GCP Authentication
    if gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        echo "GCP Authentication: ACTIVE"
        current_project=$(gcloud config get-value project 2>/dev/null)
        echo "Current Project: $current_project"
    else
        echo "GCP Authentication: NOT AUTHENTICATED"
    fi
    
    echo ""
    echo "=== ACTIVE TMUX SESSIONS ==="
    tmux list-sessions 2>/dev/null || echo "No active tmux sessions"
    
    echo ""
    echo "=== DEPLOYMENT STATUS ==="
    if ls /tmp/silo-*-deployment.log 1> /dev/null 2>&1; then
        for log in /tmp/silo-*-deployment.log; do
            echo "$(basename $log): $(tail -n 1 $log)"
        done
    else
        echo "No deployment logs found"
    fi
}

daemon_mode() {
    log_action "Entering daemon mode (24/7 operation)"
    update_status "DAEMON_MODE_ACTIVE"
    
    echo "Entering 24/7 Daemon Mode"
    echo "The system will:"
    echo "  - Monitor all silos continuously"
    echo "  - Auto-restart failed functions"
    echo "  - Log all activities"
    echo "  - Maintain system health"
    echo ""
    echo "To exit daemon mode: tmux attach-session -t gomerai-daemon"
    echo "Then press Ctrl+C"
    echo ""
    read -p "Start daemon mode? [y/N]: " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # Start in detached tmux session
        tmux new-session -d -s gomerai-daemon
        tmux send-keys -t gomerai-daemon "cd $SCRIPT_DIR" C-m
        tmux send-keys -t gomerai-daemon "./silo-watchdog.sh" C-m
        
        log_action "Daemon mode started in tmux session 'gomerai-daemon'"
        echo "Daemon mode active. System running 24/7."
        echo "To monitor: tmux attach-session -t gomerai-daemon"
    fi
}

# Modified main function for GCP VPS operation
main_vps() {
    log_action "GomerAI GCP VPS Master Control started"
    update_status "STARTING"
    
    # Initial prerequisite check
    if ! check_gcp_prerequisites; then
        echo "Prerequisites check failed. Please resolve issues before continuing."
        update_status "ERROR"
        exit 1
    fi
    
    while true; do
        echo ""
        show_vps_menu
        read choice
        
        case $choice in
            1) deploy_all_silos_vps ;;
            2) deploy_single_silo ;;
            3) start_continuous_monitoring ;;
            4) check_gcp_system_status ;;
            5) view_architecture_directive ;;
            6) emergency_stop ;;
            7) view_logs ;;
            8) system_health_report ;;
            9) daemon_mode ;;
            10) 
                log_action "GCP VPS Master Control session ended"
                update_status "STOPPED"
                echo "Goodbye!"
                exit 0
                ;;
            *) 
                echo "Invalid option. Please try again."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Additional functions for GCP VPS operation
deploy_single_silo() {
    echo "Select silo to deploy:"
    echo "1. Silo 1 (gomerai-debugging-system)"
    echo "2. Silo 2 (gomerai-silo-2)"
    echo "3. Silo 3 (gomerai-silo-3)"
    echo -n "Select [1-3]: "
    
    read silo_choice
    case $silo_choice in
        1) silo="silo1" ;;
        2) silo="silo2" ;;
        3) silo="silo3" ;;
        *) echo "Invalid choice"; return ;;
    esac
    
    log_action "Starting single silo deployment for $silo from GCP VPS"
    update_status "DEPLOYING_${silo^^}"
    cd "$SCRIPT_DIR"
    ./deploy-silo.sh "$silo"
    update_status "READY"
}

view_architecture_directive() {
    if [[ -f "$SCRIPT_DIR/GomerAI_Architecture_Directive.md" ]]; then
        less "$SCRIPT_DIR/GomerAI_Architecture_Directive.md"
    else
        echo "Architecture directive not found in $SCRIPT_DIR"
    fi
}

emergency_stop() {
    log_action "EMERGENCY STOP initiated from GCP VPS"
    update_status "EMERGENCY_STOP"
    
    echo "GCP VPS Emergency Stop - This will terminate:"
    echo "  - All tmux sessions"
    echo "  - All deployment processes"
    echo "  - All monitoring processes"
    echo ""
    read -p "Are you sure? [y/N]: " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        tmux kill-session -t gomerai-overwatcher 2>/dev/null
        tmux kill-session -t gomerai-watchdog 2>/dev/null
        tmux kill-session -t gomerai-daemon 2>/dev/null
        pkill -f "deploy-silo.sh" 2>/dev/null
        pkill -f "silo-watchdog.sh" 2>/dev/null
        log_action "Emergency stop completed on GCP VPS"
        update_status "STOPPED"
        echo "All processes stopped on GCP VPS"
    else
        echo "Emergency stop cancelled"
        update_status "READY"
    fi
}

view_logs() {
    echo "=== GCP VPS LOGS ==="
    echo "1. Master Control Log"
    echo "2. Silo Deployment Logs"
    echo "3. Watchdog Log"
    echo "4. System Status"
    echo -n "Select [1-4]: "
    
    read log_choice
    case $log_choice in
        1) 
            if [[ -f "$MASTER_LOG" ]]; then
                tail -f "$MASTER_LOG"
            else
                echo "No master log found"
            fi
            ;;
        2)
            if ls /tmp/silo-*-deployment.log 1> /dev/null 2>&1; then
                tail -f /tmp/silo-*-deployment.log
            else
                echo "No deployment logs found"
            fi
            ;;
        3)
            if [[ -f "/tmp/silo-watchdog.log" ]]; then
                tail -f /tmp/silo-watchdog.log
            else
                echo "No watchdog log found"
            fi
            ;;
        4)
            if [[ -f "$STATUS_FILE" ]]; then
                cat "$STATUS_FILE"
            else
                echo "No status file found"
            fi
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
}

system_health_report() {
    log_action "Generating system health report"
    
    echo "=== GOMERAI SYSTEM HEALTH REPORT ==="
    echo "Generated: $(date)"
    echo "Host: $(hostname)"
    echo ""
    
    # CPU and Memory
    echo "=== SYSTEM RESOURCES ==="
    echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')"
    echo "Memory Usage: $(free | grep Mem | awk '{printf("%.2f%%"), $3/$2 * 100.0}')"
    echo "Disk Usage: $(df -h / | awk 'NR==2{printf "%s", $5}')"
    echo ""
    
    # Network connectivity
    echo "=== NETWORK CONNECTIVITY ==="
    if ping -c 1 google.com &>/dev/null; then
        echo "Internet: CONNECTED"
    else
        echo "Internet: DISCONNECTED"
    fi
    
    if curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name &>/dev/null; then
        echo "GCP Metadata: ACCESSIBLE"
    else
        echo "GCP Metadata: NOT ACCESSIBLE"
    fi
    echo ""
    
    # Process status
    echo "=== PROCESS STATUS ==="
    echo "Active tmux sessions: $(tmux list-sessions 2>/dev/null | wc -l)"
    echo "GomerAI processes: $(pgrep -f gomerai | wc -l)"
    echo ""
    
    update_status "HEALTH_CHECK_COMPLETED"
}

# Start the GCP VPS master control
main_vps
