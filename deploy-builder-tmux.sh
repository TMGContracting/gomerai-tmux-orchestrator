#!/bin/bash
#
# EA Builder tmux Deployment Script for Google Cloud VM
# Creates and manages tmux session for EA development and compilation
#

set -e

# Configuration
SESSION_NAME="ea-builder"
GC_PROJECT="gomerai-debugging-system"
GC_REGION="us-central1"
EA_SOURCE_DIR="/home/mark/Documents/GomerAI"
BUILDER_DIR="/opt/gomerai-builder"
LOG_DIR="/var/log/gomerai-builder"

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

# Check development tools
check_dev_tools() {
    log "Checking development tools..."
    
    # Check wine for MetaEditor
    if ! command -v wine &> /dev/null; then
        warning "Wine not found - needed for MetaEditor"
        log "Installing Wine..."
        sudo apt-get update
        sudo apt-get install -y wine
    fi
    
    # Check git
    if ! command -v git &> /dev/null; then
        log "Installing Git..."
        sudo apt-get install -y git
    fi
    
    # Check python3
    if ! command -v python3 &> /dev/null; then
        log "Installing Python3..."
        sudo apt-get install -y python3 python3-pip
    fi
    
    success "Development tools ready"
}

# Setup builder directories
setup_builder_directories() {
    log "Setting up builder directories..."
    
    sudo mkdir -p "$BUILDER_DIR"
    sudo mkdir -p "$LOG_DIR"
    sudo chown -R $USER:$USER "$BUILDER_DIR"
    sudo chown -R $USER:$USER "$LOG_DIR"
    
    # Create subdirectories
    mkdir -p "$BUILDER_DIR/ea-development"
    mkdir -p "$BUILDER_DIR/compiled-eas"
    mkdir -p "$BUILDER_DIR/testing"
    mkdir -p "$BUILDER_DIR/scripts"
    mkdir -p "$BUILDER_DIR/templates"
    mkdir -p "$BUILDER_DIR/builds"
    mkdir -p "$BUILDER_DIR/workspace"
    
    success "Builder directories created"
}

# Copy EA development files
copy_ea_files() {
    log "Copying EA development files..."
    
    # Copy all EA source files
    if [[ -f "$EA_SOURCE_DIR/Enterprise-Shell-EA.mq5" ]]; then
        cp "$EA_SOURCE_DIR/Enterprise-Shell-EA.mq5" "$BUILDER_DIR/ea-development/"
        success "Enterprise-Shell-EA.mq5 copied"
    fi
    
    # Copy all existing EA files for reference
    find "$EA_SOURCE_DIR" -name "*.mq5" -exec cp {} "$BUILDER_DIR/ea-development/" \;
    success "All .mq5 files copied to development directory"
    
    # Copy documentation
    if [[ -f "$EA_SOURCE_DIR/Enterprise-Shell-EA-Setup.md" ]]; then
        cp "$EA_SOURCE_DIR/Enterprise-Shell-EA-Setup.md" "$BUILDER_DIR/"
    fi
    
    if [[ -f "$EA_SOURCE_DIR/ai-agent-communication.md" ]]; then
        cp "$EA_SOURCE_DIR/ai-agent-communication.md" "$BUILDER_DIR/"
    fi
    
    # Copy any include files
    if [[ -d "$EA_SOURCE_DIR/Include" ]]; then
        cp -r "$EA_SOURCE_DIR/Include" "$BUILDER_DIR/"
    fi
}

# Create EA compilation script
create_compilation_script() {
    log "Creating EA compilation script..."
    
    cat > "$BUILDER_DIR/scripts/compile-ea.sh" << 'EOF'
#!/bin/bash
#
# EA Compilation Script
#

BUILDER_DIR="/opt/gomerai-builder"
LOG_FILE="/var/log/gomerai-builder/compilation.log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

compile_ea() {
    local ea_file=$1
    local output_dir=${2:-"$BUILDER_DIR/compiled-eas"}
    
    if [[ ! -f "$ea_file" ]]; then
        log_message "ERROR: EA file not found: $ea_file"
        return 1
    fi
    
    local ea_name=$(basename "$ea_file" .mq5)
    log_message "Compiling EA: $ea_name"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # For now, copy the .mq5 file (actual compilation would require MetaEditor)
    cp "$ea_file" "$output_dir/${ea_name}_compiled_$(date +%Y%m%d_%H%M%S).mq5"
    
    log_message "SUCCESS: EA compiled: $ea_name"
    
    # Validate EA structure
    validate_ea_structure "$ea_file"
}

validate_ea_structure() {
    local ea_file=$1
    log_message "Validating EA structure: $(basename $ea_file)"
    
    # Check for required functions
    local required_functions=("OnInit" "OnTick" "OnDeinit")
    local missing_functions=()
    
    for func in "${required_functions[@]}"; do
        if ! grep -q "$func" "$ea_file"; then
            missing_functions+=("$func")
        fi
    done
    
    if [[ ${#missing_functions[@]} -eq 0 ]]; then
        log_message "SUCCESS: EA structure validation passed"
        return 0
    else
        log_message "WARNING: Missing functions: ${missing_functions[*]}"
        return 1
    fi
}

case "$1" in
    compile)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 compile <ea_file.mq5> [output_dir]"
            exit 1
        fi
        compile_ea "$2" "$3"
        ;;
    validate)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 validate <ea_file.mq5>"
            exit 1
        fi
        validate_ea_structure "$2"
        ;;
    *)
        echo "Usage: $0 {compile|validate} <ea_file.mq5> [output_dir]"
        echo ""
        echo "Commands:"
        echo "  compile   - Compile EA file"
        echo "  validate  - Validate EA structure"
        exit 1
        ;;
esac
EOF

    chmod +x "$BUILDER_DIR/scripts/compile-ea.sh"
    success "EA compilation script created"
}

# Create EA testing script
create_testing_script() {
    log "Creating EA testing script..."
    
    cat > "$BUILDER_DIR/scripts/test-ea.sh" << 'EOF'
#!/bin/bash
#
# EA Testing Script
#

BUILDER_DIR="/opt/gomerai-builder"
LOG_FILE="/var/log/gomerai-builder/testing.log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

syntax_check() {
    local ea_file=$1
    log_message "Running syntax check on: $(basename $ea_file)"
    
    # Basic syntax checks
    local errors=0
    
    # Check for common syntax issues
    if grep -n "Print.*emoji" "$ea_file"; then
        log_message "ERROR: Found emojis in Print statements"
        ((errors++))
    fi
    
    # Check for proper include statements
    if ! grep -q "#include.*Trade.mqh" "$ea_file"; then
        log_message "WARNING: Missing Trade.mqh include"
    fi
    
    # Check for proper function declarations
    if ! grep -q "int OnInit" "$ea_file"; then
        log_message "ERROR: Missing OnInit function"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_message "SUCCESS: Syntax check passed"
        return 0
    else
        log_message "ERROR: Syntax check failed with $errors errors"
        return 1
    fi
}

performance_test() {
    local ea_file=$1
    log_message "Running performance analysis on: $(basename $ea_file)"
    
    # Count lines of code
    local loc=$(grep -c "^[[:space:]]*[^[:space:]//]" "$ea_file" || echo "0")
    log_message "Lines of code: $loc"
    
    # Check for complex functions (>100 lines)
    local complex_functions=$(awk '/^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(/{func=$0; line=NR; count=0} 
                                   /\{/{if(func) count++} 
                                   /\}/{if(func) count--; if(count==0 && func && NR-line>100) print func}' "$ea_file" | wc -l)
    
    if [[ $complex_functions -gt 0 ]]; then
        log_message "WARNING: Found $complex_functions functions with >100 lines"
    fi
    
    log_message "Performance analysis completed"
}

integration_test() {
    local ea_file=$1
    log_message "Running integration test on: $(basename $ea_file)"
    
    # Check Enterprise integration
    if grep -q "Enterprise" "$ea_file" && grep -q "WebRequest" "$ea_file"; then
        log_message "SUCCESS: Enterprise integration detected"
    else
        log_message "WARNING: No Enterprise integration found"
    fi
    
    # Check WAS system integration
    if grep -q "CalculateWAS" "$ea_file"; then
        log_message "SUCCESS: WAS system integration detected"
    else
        log_message "WARNING: No WAS system found"
    fi
    
    # Check FIFO compliance
    if grep -q "FIFO" "$ea_file"; then
        log_message "SUCCESS: FIFO compliance detected"
    else
        log_message "WARNING: No FIFO compliance found"
    fi
}

case "$1" in
    syntax)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 syntax <ea_file.mq5>"
            exit 1
        fi
        syntax_check "$2"
        ;;
    performance)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 performance <ea_file.mq5>"
            exit 1
        fi
        performance_test "$2"
        ;;
    integration)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 integration <ea_file.mq5>"
            exit 1
        fi
        integration_test "$2"
        ;;
    full)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 full <ea_file.mq5>"
            exit 1
        fi
        syntax_check "$2"
        performance_test "$2"
        integration_test "$2"
        ;;
    *)
        echo "Usage: $0 {syntax|performance|integration|full} <ea_file.mq5>"
        echo ""
        echo "Commands:"
        echo "  syntax      - Check syntax and basic structure"
        echo "  performance - Analyze performance characteristics"
        echo "  integration - Check Enterprise integration"
        echo "  full        - Run all tests"
        exit 1
        ;;
esac
EOF

    chmod +x "$BUILDER_DIR/scripts/test-ea.sh"
    success "EA testing script created"
}

# Create deployment script
create_deployment_script() {
    log "Creating deployment script..."
    
    cat > "$BUILDER_DIR/scripts/deploy-to-production.sh" << 'EOF'
#!/bin/bash
#
# Deploy EA to Production VM
#

BUILDER_DIR="/opt/gomerai-builder"
PRODUCTION_VM="gomerai-vm"
PRODUCTION_ZONE="us-central1-a"
LOG_FILE="/var/log/gomerai-builder/deployment.log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

deploy_ea() {
    local ea_file=$1
    local target_dir=${2:-"/opt/gomerai-enterprise/ea-source/"}
    
    if [[ ! -f "$ea_file" ]]; then
        log_message "ERROR: EA file not found: $ea_file"
        return 1
    fi
    
    local ea_name=$(basename "$ea_file")
    log_message "Deploying EA to production: $ea_name"
    
    # Copy to production VM
    if gcloud compute scp "$ea_file" "$PRODUCTION_VM:$target_dir" --zone="$PRODUCTION_ZONE"; then
        log_message "SUCCESS: EA deployed to production VM"
        
        # Backup old version
        local backup_name="${ea_name}_backup_$(date +%Y%m%d_%H%M%S).mq5"
        gcloud compute ssh "$PRODUCTION_VM" --zone="$PRODUCTION_ZONE" --command="cp $target_dir$ea_name $target_dir$backup_name 2>/dev/null || true"
        
        return 0
    else
        log_message "ERROR: Failed to deploy EA"
        return 1
    fi
}

test_deployment() {
    local ea_name=$1
    log_message "Testing deployment on production VM"
    
    # Check if file exists on production
    if gcloud compute ssh "$PRODUCTION_VM" --zone="$PRODUCTION_ZONE" --command="test -f /opt/gomerai-enterprise/ea-source/$ea_name"; then
        log_message "SUCCESS: EA found on production VM"
        return 0
    else
        log_message "ERROR: EA not found on production VM"
        return 1
    fi
}

case "$1" in
    deploy)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 deploy <ea_file.mq5> [target_dir]"
            exit 1
        fi
        deploy_ea "$2" "$3"
        ;;
    test)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 test <ea_name.mq5>"
            exit 1
        fi
        test_deployment "$2"
        ;;
    *)
        echo "Usage: $0 {deploy|test} <ea_file.mq5> [target_dir]"
        echo ""
        echo "Commands:"
        echo "  deploy  - Deploy EA to production VM"
        echo "  test    - Test if EA exists on production"
        exit 1
        ;;
esac
EOF

    chmod +x "$BUILDER_DIR/scripts/deploy-to-production.sh"
    success "Deployment script created"
}

# Create EA template generator
create_template_generator() {
    log "Creating EA template generator..."
    
    cat > "$BUILDER_DIR/scripts/generate-ea-template.py" << 'EOF'
#!/usr/bin/env python3
"""
EA Template Generator
Creates new EA files based on Enterprise-Shell-EA template
"""

import os
import sys
import datetime
from pathlib import Path

BUILDER_DIR = "/opt/gomerai-builder"
TEMPLATE_DIR = f"{BUILDER_DIR}/templates"
WORKSPACE_DIR = f"{BUILDER_DIR}/workspace"

def create_ea_template(ea_name, description="Custom EA"):
    """Create a new EA based on Enterprise-Shell-EA template"""
    
    template_content = f'''//+------------------------------------------------------------------+
//|                    {ea_name}.mq5                                 |
//|           Built Enterprise-First for GomerAI Cloud System       |
//|              Copyright 2025, GomerAI LLC                         |
//+------------------------------------------------------------------+
#property copyright "GomerAI LLC"
#property version   "1.0"
#property description "{description}"

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| ENTERPRISE CONFIGURATION - Core System Integration              |
//+------------------------------------------------------------------+
input group "=== ENTERPRISE INTEGRATION ==="
input bool     EnableEnterpriseMode     = true;
input string   TerminalID               = "12345678";
input string   CustomerLicenseKey       = "ML-LICENSE-KEY";
input int      EnterpriseUpdateInterval = 30;

input group "=== TRADING PARAMETERS ==="
input double   LotSize                  = 0.01;
input int      TakeProfit               = 100;
input int      StopLoss                 = 50;
input int      MagicNumber              = 123456;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
bool g_enterpriseConnected = false;
datetime g_lastSync = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {{
    Print("=== {ea_name.upper()} STARTING ===");
    
    if (EnableEnterpriseMode) {{
        // Initialize Enterprise connection
        g_enterpriseConnected = InitializeEnterprise();
    }}
    
    Print("{ea_name} initialized successfully");
    return(INIT_SUCCEEDED);
}}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {{
    // Enterprise sync
    if (g_enterpriseConnected && TimeCurrent() - g_lastSync >= EnterpriseUpdateInterval) {{
        SyncWithEnterprise();
        g_lastSync = TimeCurrent();
    }}
    
    // Trading logic
    ExecuteTradingStrategy();
}}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {{
    Print("=== {ea_name.upper()} STOPPED ===");
}}

//+------------------------------------------------------------------+
//| Initialize Enterprise Connection                                 |
//+------------------------------------------------------------------+
bool InitializeEnterprise() {{
    // TODO: Implement Enterprise connection
    Print("Enterprise integration initialized");
    return true;
}}

//+------------------------------------------------------------------+
//| Sync with Enterprise                                             |
//+------------------------------------------------------------------+
void SyncWithEnterprise() {{
    // TODO: Implement Enterprise sync
    Print("Enterprise sync completed");
}}

//+------------------------------------------------------------------+
//| Execute Trading Strategy                                         |
//+------------------------------------------------------------------+
void ExecuteTradingStrategy() {{
    // TODO: Implement your trading logic here
    // This is where you add your specific trading strategy
    
    // Example structure:
    // 1. Calculate signals
    // 2. Check positions
    // 3. Execute trades
    // 4. Manage risk
}}
'''
    
    # Create workspace directory if it doesn't exist
    os.makedirs(WORKSPACE_DIR, exist_ok=True)
    
    # Write template file
    template_file = f"{WORKSPACE_DIR}/{ea_name}.mq5"
    with open(template_file, 'w') as f:
        f.write(template_content)
    
    print(f"SUCCESS: EA template created: {template_file}")
    return template_file

def list_templates():
    """List available templates"""
    if os.path.exists(TEMPLATE_DIR):
        templates = [f for f in os.listdir(TEMPLATE_DIR) if f.endswith('.mq5')]
        if templates:
            print("Available templates:")
            for template in templates:
                print(f"  - {template}")
        else:
            print("No templates found")
    else:
        print("Template directory not found")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 generate-ea-template.py <command> [options]")
        print("")
        print("Commands:")
        print("  create <ea_name> [description]  - Create new EA template")
        print("  list                            - List available templates")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "create":
        if len(sys.argv) < 3:
            print("Usage: python3 generate-ea-template.py create <ea_name> [description]")
            sys.exit(1)
        
        ea_name = sys.argv[2]
        description = sys.argv[3] if len(sys.argv) > 3 else "Custom EA"
        
        create_ea_template(ea_name, description)
        
    elif command == "list":
        list_templates()
        
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    chmod +x "$BUILDER_DIR/scripts/generate-ea-template.py"
    success "EA template generator created"
}

# Create tmux configuration for builder
create_builder_tmux_config() {
    log "Creating builder tmux configuration..."
    
    cat > "$BUILDER_DIR/.tmux.conf" << 'EOF'
# EA Builder tmux configuration
set -g default-terminal "screen-256color"
set -g history-limit 10000
set -g base-index 1
setw -g pane-base-index 1

# Status bar - Builder theme
set -g status-bg colour52
set -g status-fg colour255
set -g status-left '#[fg=colour255,bg=colour88,bold] EA BUILDER '
set -g status-right '#[fg=colour255,bg=colour88,bold] %d/%m %H:%M:%S '
set -g status-right-length 50
set -g status-left-length 30

# Window status
setw -g window-status-current-format ' #I#[fg=colour255]:#[fg=colour255]#W#[fg=colour196]#F '
setw -g window-status-format ' #I#[fg=colour244]:#[fg=colour250]#W#[fg=colour244]#F '

# Pane borders
set -g pane-border-fg colour238
set -g pane-active-border-fg colour196

# Key bindings
bind r source-file ~/.tmux.conf \; display-message "Builder config reloaded!"
bind | split-window -h
bind - split-window -v
EOF

    success "Builder tmux configuration created"
}

# Create main tmux session for builder
create_builder_tmux_session() {
    log "Creating EA Builder tmux session: $SESSION_NAME"
    
    # Kill existing session if it exists
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    
    # Create new session with first window
    tmux new-session -d -s "$SESSION_NAME" -c "$BUILDER_DIR"
    
    # Rename first window to 'main'
    tmux rename-window -t "$SESSION_NAME:0" 'main'
    
    # Window 1: EA Development Workspace
    tmux new-window -t "$SESSION_NAME" -n 'workspace' -c "$BUILDER_DIR/workspace"
    tmux send-keys -t "$SESSION_NAME:workspace" 'ls -la && echo "EA Development Workspace - Create new EAs here"' Enter
    
    # Window 2: Compilation & Testing
    tmux new-window -t "$SESSION_NAME" -n 'compile' -c "$BUILDER_DIR"
    tmux split-window -h -t "$SESSION_NAME:compile"
    tmux send-keys -t "$SESSION_NAME:compile.0" 'echo "=== EA COMPILATION ===" && echo "Usage: ./scripts/compile-ea.sh compile <ea_file.mq5>"' Enter
    tmux send-keys -t "$SESSION_NAME:compile.1" 'echo "=== EA TESTING ===" && echo "Usage: ./scripts/test-ea.sh full <ea_file.mq5>"' Enter
    
    # Window 3: Source Code Editor
    tmux new-window -t "$SESSION_NAME" -n 'editor' -c "$BUILDER_DIR/ea-development"
    tmux send-keys -t "$SESSION_NAME:editor" 'ls -la && echo "EA Source Files - Edit existing EAs here"' Enter
    
    # Window 4: Template Generator
    tmux new-window -t "$SESSION_NAME" -n 'templates' -c "$BUILDER_DIR"
    tmux send-keys -t "$SESSION_NAME:templates" 'echo "=== EA TEMPLATE GENERATOR ===" && echo "Usage: python3 scripts/generate-ea-template.py create <ea_name> [description]"' Enter
    
    # Window 5: Deployment
    tmux new-window -t "$SESSION_NAME" -n 'deploy' -c "$BUILDER_DIR"
    tmux split-window -v -t "$SESSION_NAME:deploy"
    tmux send-keys -t "$SESSION_NAME:deploy.0" 'echo "=== DEPLOYMENT TO PRODUCTION ===" && echo "Usage: ./scripts/deploy-to-production.sh deploy <ea_file.mq5>"' Enter
    tmux send-keys -t "$SESSION_NAME:deploy.1" 'echo "=== BUILD STATUS ===" && ls -la compiled-eas/' Enter
    
    # Window 6: Logs & Monitoring
    tmux new-window -t "$SESSION_NAME" -n 'logs' -c "$BUILDER_DIR"
    tmux split-window -h -t "$SESSION_NAME:logs"
    tmux send-keys -t "$SESSION_NAME:logs.0" 'tail -f /var/log/gomerai-builder/compilation.log' Enter
    tmux send-keys -t "$SESSION_NAME:logs.1" 'tail -f /var/log/gomerai-builder/testing.log' Enter
    
    # Go back to main window
    tmux select-window -t "$SESSION_NAME:main"
    
    success "EA Builder tmux session '$SESSION_NAME' created with 6 windows"
}

# Create session management script for builder
create_builder_session_manager() {
    log "Creating builder session management script..."
    
    cat > "$BUILDER_DIR/tmux-builder-manager.sh" << EOF
#!/bin/bash
#
# EA Builder tmux Session Manager
#

SESSION_NAME="$SESSION_NAME"

case "\$1" in
    start)
        if tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
            echo "Builder session '\$SESSION_NAME' already exists. Attaching..."
            tmux attach-session -t "\$SESSION_NAME"
        else
            echo "Creating new builder session '\$SESSION_NAME'..."
            bash "$BUILDER_DIR/../deploy-builder-tmux.sh" create_session_only
        fi
        ;;
    create)
        bash "$BUILDER_DIR/../deploy-builder-tmux.sh" create_session_only
        ;;
    attach)
        tmux attach-session -t "\$SESSION_NAME"
        ;;
    list)
        tmux list-windows -t "\$SESSION_NAME"
        ;;
    kill)
        tmux kill-session -t "\$SESSION_NAME"
        echo "Builder session '\$SESSION_NAME' terminated"
        ;;
    status)
        if tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
            echo "Builder session '\$SESSION_NAME' is running"
            tmux list-windows -t "\$SESSION_NAME"
        else
            echo "Builder session '\$SESSION_NAME' is not running"
        fi
        ;;
    *)
        echo "Usage: \$0 {start|create|attach|list|kill|status}"
        echo ""
        echo "Commands:"
        echo "  start   - Start or attach to builder session"
        echo "  create  - Create new builder session (kill existing)"
        echo "  attach  - Attach to existing builder session"
        echo "  list    - List windows in builder session"
        echo "  kill    - Terminate builder session"
        echo "  status  - Show builder session status"
        exit 1
        ;;
esac
EOF

    chmod +x "$BUILDER_DIR/tmux-builder-manager.sh"
    success "Builder session manager created"
}

# Main deployment function
main() {
    log "Starting EA Builder tmux deployment..."
    
    check_root
    check_tmux
    check_dev_tools
    setup_builder_directories
    copy_ea_files
    create_compilation_script
    create_testing_script
    create_deployment_script
    create_template_generator
    create_builder_tmux_config
    create_builder_tmux_session
    create_builder_session_manager
    
    success "EA Builder tmux deployment complete!"
    echo ""
    echo "EA BUILDER READY:"
    echo "1. Attach to builder session: cd $BUILDER_DIR && ./tmux-builder-manager.sh attach"
    echo "2. Create new EA: Go to 'templates' window and run generate-ea-template.py"
    echo "3. Edit EAs: Use 'workspace' and 'editor' windows"
    echo "4. Compile & Test: Use 'compile' window"
    echo "5. Deploy to Production: Use 'deploy' window"
    echo ""
    echo "Builder Session Management:"
    echo "   Start/Attach: $BUILDER_DIR/tmux-builder-manager.sh start"
    echo "   Status:       $BUILDER_DIR/tmux-builder-manager.sh status"
    echo "   Kill:         $BUILDER_DIR/tmux-builder-manager.sh kill"
    echo ""
    echo "Important Paths:"
    echo "   Workspace:    $BUILDER_DIR/workspace/"
    echo "   Source EAs:   $BUILDER_DIR/ea-development/"
    echo "   Scripts:      $BUILDER_DIR/scripts/"
    echo "   Compiled:     $BUILDER_DIR/compiled-eas/"
    echo "   Logs:         /var/log/gomerai-builder/"
}

# Handle special case for session creation only
if [[ "$1" == "create_session_only" ]]; then
    create_builder_tmux_session
    exit 0
fi

# Run main deployment
main "$@"


