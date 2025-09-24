#!/bin/bash
#
# GomerAI MT5 Bridge Installation Script
# =====================================
# 
# Installs MT5 Data Pipeline Bridge as part of tmux installation.exe
# This script is embedded in the customer installation package.
#

set -e

# Configuration
BRIDGE_VERSION="1.0.0"
INSTALL_DIR="$HOME/.gomerai/mt5-bridge"
SERVICE_NAME="gomerai-mt5-bridge"
LOG_DIR="$HOME/.gomerai/logs"
NODE_VERSION="20"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running as part of tmux installation
check_tmux_context() {
    if [[ -z "$TMUX_INSTALL_SESSION" ]]; then
        warn "Not running in tmux installation context"
        warn "This script is designed to be run as part of the GomerAI installation.exe"
    else
        log "Running in tmux installation session: $TMUX_INSTALL_SESSION"
    fi
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    # Check OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        info "Operating System: Linux (Supported)"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        info "Operating System: macOS (Supported)"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        info "Operating System: Windows (Supported via WSL/Cygwin)"
    else
        error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
    
    # Check Node.js
    if command -v node &> /dev/null; then
        NODE_CURRENT=$(node --version | sed 's/v//')
        info "Node.js found: v$NODE_CURRENT"
        
        # Check version (require Node 18+)
        if [[ $(echo "$NODE_CURRENT" | cut -d. -f1) -lt 18 ]]; then
            warn "Node.js version $NODE_CURRENT is too old (require 18+)"
            install_nodejs
        fi
    else
        warn "Node.js not found, installing..."
        install_nodejs
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        error "npm not found after Node.js installation"
        exit 1
    fi
    
    log "System requirements check completed"
}

# Install Node.js if needed
install_nodejs() {
    log "Installing Node.js v$NODE_VERSION..."
    
    if command -v curl &> /dev/null; then
        # Install using NodeSource repository
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS - use Homebrew if available, otherwise download binary
            if command -v brew &> /dev/null; then
                brew install node@${NODE_VERSION}
            else
                error "Please install Node.js manually from https://nodejs.org/"
                exit 1
            fi
        fi
    else
        error "curl not found. Please install Node.js manually from https://nodejs.org/"
        exit 1
    fi
    
    log "Node.js installation completed"
}

# Create installation directories
create_directories() {
    log "Creating installation directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$INSTALL_DIR/config"
    mkdir -p "$INSTALL_DIR/file-drops/inbound"
    mkdir -p "$INSTALL_DIR/file-drops/processing"
    mkdir -p "$INSTALL_DIR/file-drops/completed"
    mkdir -p "$INSTALL_DIR/file-drops/failed"
    mkdir -p "$INSTALL_DIR/queue-data"
    
    log "Directories created successfully"
}

# Install bridge components
install_bridge_components() {
    log "Installing MT5 Bridge components..."
    
    # Copy bridge files from installation package
    cp -r ./mt5-bridge/* "$INSTALL_DIR/"
    
    # Set executable permissions
    chmod +x "$INSTALL_DIR"/*.js
    chmod +x "$INSTALL_DIR"/*.sh
    
    # Install Node.js dependencies
    cd "$INSTALL_DIR"
    npm install --production --silent
    
    log "Bridge components installed successfully"
}

# Configure bridge service
configure_bridge() {
    log "Configuring MT5 Bridge service..."
    
    # Create configuration file
    cat > "$INSTALL_DIR/config/bridge-config.json" << EOF
{
    "version": "$BRIDGE_VERSION",
    "installDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "relay": {
        "port": 9876,
        "host": "127.0.0.1",
        "timeout": 30000
    },
    "gcpEndpoints": {
        "ingest": "https://us-central1-gomerai-silo-alpha.cloudfunctions.net/eaIngestPublisher",
        "token": "https://us-central1-gomerai-silo-alpha.cloudfunctions.net/token-broker",
        "dashboard": "https://us-central1-gomerai-silo-alpha.cloudfunctions.net/customerDashboard",
        "mlSnapshot": "https://us-central1-gomerai-silo-alpha.cloudfunctions.net/logMLSnapshot"
    },
    "apiKey": "68876163c86d98a59f045a6d9625d0349cc43ca8dab2bf39317b55c612a4c942",
    "retry": {
        "maxAttempts": 3,
        "baseDelay": 1000,
        "maxDelay": 10000
    },
    "logging": {
        "level": "info",
        "file": "$LOG_DIR/mt5-bridge.log",
        "maxFiles": 5,
        "maxSize": "10m"
    },
    "fileDrop": {
        "enabled": true,
        "watchPath": "$INSTALL_DIR/file-drops/inbound",
        "processInterval": 5000
    }
}
EOF
    
    log "Bridge configuration created"
}

# Create systemd service (Linux) or launchd service (macOS)
create_service() {
    log "Creating system service for MT5 Bridge..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        create_systemd_service
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        create_launchd_service
    else
        warn "System service creation not supported on this platform"
        warn "Bridge must be started manually"
        return
    fi
    
    log "System service created successfully"
}

# Create systemd service for Linux
create_systemd_service() {
    SERVICE_FILE="$HOME/.config/systemd/user/$SERVICE_NAME.service"
    
    mkdir -p "$HOME/.config/systemd/user"
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=GomerAI MT5 Bridge Service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=5
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node $INSTALL_DIR/bridge-launcher.js
Environment=NODE_ENV=production
Environment=GOMERAI_CONFIG_PATH=$INSTALL_DIR/config/bridge-config.json
StandardOutput=append:$LOG_DIR/mt5-bridge-service.log
StandardError=append:$LOG_DIR/mt5-bridge-service.error.log

[Install]
WantedBy=default.target
EOF
    
    # Enable and start service
    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE_NAME"
    
    info "Systemd service created: $SERVICE_FILE"
}

# Create launchd service for macOS
create_launchd_service() {
    PLIST_FILE="$HOME/Library/LaunchAgents/com.gomerai.mt5bridge.plist"
    
    mkdir -p "$HOME/Library/LaunchAgents"
    
    cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.gomerai.mt5bridge</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/node</string>
        <string>$INSTALL_DIR/bridge-launcher.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>NODE_ENV</key>
        <string>production</string>
        <key>GOMERAI_CONFIG_PATH</key>
        <string>$INSTALL_DIR/config/bridge-config.json</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/mt5-bridge-service.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/mt5-bridge-service.error.log</string>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
    
    # Load service
    launchctl load "$PLIST_FILE"
    
    info "Launchd service created: $PLIST_FILE"
}

# Start bridge service
start_bridge() {
    log "Starting MT5 Bridge service..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        systemctl --user start "$SERVICE_NAME"
        sleep 2
        if systemctl --user is-active --quiet "$SERVICE_NAME"; then
            log "Bridge service started successfully"
        else
            error "Failed to start bridge service"
            systemctl --user status "$SERVICE_NAME"
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # Service should start automatically via launchd
        sleep 3
        if pgrep -f "bridge-launcher.js" > /dev/null; then
            log "Bridge service started successfully"
        else
            error "Failed to start bridge service"
            exit 1
        fi
    else
        # Manual start for other platforms
        warn "Starting bridge manually (no system service support)"
        cd "$INSTALL_DIR"
        nohup node bridge-launcher.js > "$LOG_DIR/mt5-bridge-manual.log" 2>&1 &
        sleep 2
        if pgrep -f "bridge-launcher.js" > /dev/null; then
            log "Bridge started manually"
        else
            error "Failed to start bridge manually"
            exit 1
        fi
    fi
}

# Test bridge connectivity
test_bridge() {
    log "Testing MT5 Bridge connectivity..."
    
    # Wait for service to fully start
    sleep 5
    
    # Test health endpoint
    if command -v curl &> /dev/null; then
        if curl -s -f "http://127.0.0.1:9876/health" > /dev/null; then
            log "✓ Bridge health check passed"
        else
            error "✗ Bridge health check failed"
            exit 1
        fi
        
        # Test status endpoint
        STATUS_RESPONSE=$(curl -s "http://127.0.0.1:9876/status" 2>/dev/null || echo "")
        if [[ -n "$STATUS_RESPONSE" ]]; then
            log "✓ Bridge status endpoint accessible"
            info "Bridge Status: $STATUS_RESPONSE"
        else
            warn "Bridge status endpoint not responding"
        fi
    else
        warn "curl not available, skipping connectivity test"
    fi
}

# Create MT5 configuration helper
create_mt5_config() {
    log "Creating MT5 configuration helper..."
    
    cat > "$INSTALL_DIR/mt5-bridge-config.mqh" << 'EOF'
//+------------------------------------------------------------------+
//|                    MT5 Bridge Configuration                      |
//|           Auto-generated by GomerAI Installation                |
//+------------------------------------------------------------------+

// Bridge endpoints (local relay)
string BRIDGE_INGEST_URL = "http://127.0.0.1:9876/ingest";
string BRIDGE_TOKEN_URL = "http://127.0.0.1:9876/token";
string BRIDGE_DASHBOARD_URL = "http://127.0.0.1:9876/dashboard";
string BRIDGE_ML_SNAPSHOT_URL = "http://127.0.0.1:9876/ml-snapshot";

// Fallback to direct GCP endpoints if bridge unavailable
string DIRECT_INGEST_URL = "https://us-central1-gomerai-silo-alpha.cloudfunctions.net/eaIngestPublisher";
string DIRECT_TOKEN_URL = "https://us-central1-gomerai-silo-alpha.cloudfunctions.net/token-broker";
string DIRECT_DASHBOARD_URL = "https://us-central1-gomerai-silo-alpha.cloudfunctions.net/customerDashboard";
string DIRECT_ML_SNAPSHOT_URL = "https://us-central1-gomerai-silo-alpha.cloudfunctions.net/logMLSnapshot";

// Bridge configuration
bool USE_BRIDGE = true;
int BRIDGE_TIMEOUT = 5000; // 5 seconds
int DIRECT_TIMEOUT = 10000; // 10 seconds

//+------------------------------------------------------------------+
//| Smart WebRequest with Bridge Fallback                           |
//+------------------------------------------------------------------+
int SmartWebRequest(string method, string endpointType, string headers, 
                   int timeout, uchar &data[], uchar &result[], string &resultHeaders)
{
    string primaryUrl = "";
    string fallbackUrl = "";
    
    // Determine URLs based on endpoint type
    if (endpointType == "ingest") {
        primaryUrl = USE_BRIDGE ? BRIDGE_INGEST_URL : DIRECT_INGEST_URL;
        fallbackUrl = USE_BRIDGE ? DIRECT_INGEST_URL : "";
    } else if (endpointType == "token") {
        primaryUrl = USE_BRIDGE ? BRIDGE_TOKEN_URL : DIRECT_TOKEN_URL;
        fallbackUrl = USE_BRIDGE ? DIRECT_TOKEN_URL : "";
    } else if (endpointType == "dashboard") {
        primaryUrl = USE_BRIDGE ? BRIDGE_DASHBOARD_URL : DIRECT_DASHBOARD_URL;
        fallbackUrl = USE_BRIDGE ? DIRECT_DASHBOARD_URL : "";
    } else if (endpointType == "ml-snapshot") {
        primaryUrl = USE_BRIDGE ? BRIDGE_ML_SNAPSHOT_URL : DIRECT_ML_SNAPSHOT_URL;
        fallbackUrl = USE_BRIDGE ? DIRECT_ML_SNAPSHOT_URL : "";
    }
    
    if (primaryUrl == "") {
        Print("Invalid endpoint type: ", endpointType);
        return -1;
    }
    
    // Try primary URL (bridge or direct)
    int result_code = WebRequest(method, primaryUrl, headers, timeout, data, result, resultHeaders);
    
    if (result_code > 0) {
        Print("✓ Request successful via ", USE_BRIDGE ? "bridge" : "direct", ": ", primaryUrl);
        return result_code;
    }
    
    // If bridge failed and we have a fallback, try direct connection
    if (USE_BRIDGE && fallbackUrl != "") {
        Print("Bridge failed, trying direct connection: ", fallbackUrl);
        
        result_code = WebRequest(method, fallbackUrl, headers, DIRECT_TIMEOUT, data, result, resultHeaders);
        
        if (result_code > 0) {
            Print("✓ Request successful via direct fallback: ", fallbackUrl);
            return result_code;
        } else {
            Print("✗ Both bridge and direct connection failed");
        }
    }
    
    return result_code;
}

//+------------------------------------------------------------------+
//| File Drop Fallback (when all HTTP methods fail)                |
//+------------------------------------------------------------------+
bool WriteToFileDrop(string data, string fileType = "ingest")
{
    datetime now = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(now, dt);
    
    string filename = StringFormat("gomerai_%s_%04d%02d%02d_%02d%02d%02d_%d.json",
                                   fileType,
                                   dt.year, dt.mon, dt.day,
                                   dt.hour, dt.min, dt.sec,
                                   GetMicrosecondCount() % 1000);
    
    // Use the bridge file-drop directory
    string dropPath = "file-drops\\inbound\\" + filename;
    string tempPath = dropPath + ".tmp";
    
    int handle = FileOpen(tempPath, FILE_WRITE | FILE_TXT);
    if (handle == INVALID_HANDLE) {
        Print("Failed to create file drop: ", tempPath);
        return false;
    }
    
    FileWriteString(handle, data);
    FileClose(handle);
    
    // Atomic rename
    if (!FileMove(tempPath, dropPath)) {
        Print("Failed to move temp file to drop location");
        FileDelete(tempPath);
        return false;
    }
    
    Print("✓ Data written to file drop: ", filename);
    return true;
}
EOF
    
    log "MT5 configuration helper created: $INSTALL_DIR/mt5-bridge-config.mqh"
}

# Display installation summary
show_summary() {
    log "MT5 Bridge Installation Complete!"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 GomerAI MT5 Bridge Installed                 ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║ Installation Directory: $INSTALL_DIR"
    echo "║ Log Directory:          $LOG_DIR"
    echo "║ Configuration:          $INSTALL_DIR/config/bridge-config.json"
    echo "║ MT5 Helper:             $INSTALL_DIR/mt5-bridge-config.mqh"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║ Bridge Endpoints:                                            ║"
    echo "║ • Health:      http://127.0.0.1:9876/health                 ║"
    echo "║ • Status:      http://127.0.0.1:9876/status                 ║"
    echo "║ • Ingest:      http://127.0.0.1:9876/ingest                 ║"
    echo "║ • Token:       http://127.0.0.1:9876/token                  ║"
    echo "║ • Dashboard:   http://127.0.0.1:9876/dashboard              ║"
    echo "║ • ML Snapshot: http://127.0.0.1:9876/ml-snapshot            ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║ Service Status: $(systemctl --user is-active $SERVICE_NAME 2>/dev/null || echo 'Manual')"
    echo "║ File Drop:      $INSTALL_DIR/file-drops/inbound"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    info "Next Steps:"
    info "1. Copy mt5-bridge-config.mqh to your MT5 Include directory"
    info "2. Update your EA to use #include <mt5-bridge-config.mqh>"
    info "3. Replace WebRequest calls with SmartWebRequest function"
    info "4. Test connectivity using the bridge endpoints"
    
    echo ""
    log "Installation completed successfully!"
}

# Main installation function
main() {
    log "Starting GomerAI MT5 Bridge Installation (v$BRIDGE_VERSION)"
    
    check_tmux_context
    check_requirements
    create_directories
    install_bridge_components
    configure_bridge
    create_service
    start_bridge
    test_bridge
    create_mt5_config
    show_summary
    
    log "MT5 Bridge installation completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
