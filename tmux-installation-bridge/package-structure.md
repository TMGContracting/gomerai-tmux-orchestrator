# GomerAI MT5 Bridge - Tmux Installation Package Structure

## Overview

The MT5 Bridge system is designed to be embedded within the main GomerAI `installation.exe` tmux orchestrator. This document outlines the package structure and integration points.

## Package Structure

```
installation.exe/
├── main-installer.sh                 # Main tmux orchestrator
├── components/
│   ├── gomerai-core/                # Core GomerAI components
│   ├── ea-distribution/             # EA distribution system
│   └── mt5-bridge/                  # MT5 Bridge system (this package)
│       ├── install-mt5-bridge.sh   # Bridge installation script
│       ├── tmux-bridge-integration.sh # Tmux integration script
│       ├── bridge-launcher.js       # Production bridge launcher
│       ├── relay-server.js          # HTTP relay server
│       ├── file-drop-relay.js       # File-drop fallback system
│       ├── package.json             # Node.js dependencies
│       ├── config/
│       │   └── bridge-config.template.json # Configuration template
│       ├── templates/
│       │   └── mt5-bridge-config.mqh # MT5 integration template
│       └── docs/
│           ├── README.md            # Bridge documentation
│           ├── INTEGRATION.md       # EA integration guide
│           └── TROUBLESHOOTING.md   # Common issues and solutions
```

## Integration Flow

### 1. Main Installation Orchestrator

The main `installation.exe` calls the MT5 Bridge integration:

```bash
#!/bin/bash
# main-installer.sh

# ... other installation steps ...

# Install MT5 Bridge
log "Installing MT5 Data Pipeline Bridge..."
if ./components/mt5-bridge/tmux-bridge-integration.sh; then
    log "✅ MT5 Bridge installed successfully"
else
    error "❌ MT5 Bridge installation failed"
    exit 1
fi

# ... continue with other components ...
```

### 2. Tmux Window Layout

The installation creates the following tmux layout:

```
Session: gomerai-installation
├── Window 0: main-installer        # Main installation progress
├── Window 1: gomerai-core          # Core system installation
├── Window 2: ea-distribution       # EA distribution setup
├── Window 3: mt5-bridge            # MT5 Bridge (this component)
│   ├── Pane 0: Installation        # Bridge installation logs
│   ├── Pane 1: Bridge Service      # Running bridge service
│   └── Pane 2: Monitoring          # Health monitoring
└── Window 4: final-setup           # Final configuration steps
```

### 3. Service Management

The bridge runs as a managed service within the tmux session:

- **Primary**: HTTP Relay Server (port 9876)
- **Secondary**: File-Drop Relay (fallback mechanism)
- **Monitoring**: Health checks and status reporting

## Configuration Management

### Environment Variables

The bridge uses the following environment variables:

```bash
TMUX_INSTALL_SESSION=gomerai-installation
GOMERAI_CONFIG_PATH=$HOME/.gomerai/mt5-bridge/config/bridge-config.json
NODE_ENV=production
ENABLE_STATUS_SERVER=true
STATUS_PORT=9877
```

### Configuration File

Bridge configuration is stored in `~/.gomerai/mt5-bridge/config/bridge-config.json`:

```json
{
    "version": "1.0.0",
    "installDate": "2025-01-XX",
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
        "file": "~/.gomerai/logs/mt5-bridge.log",
        "maxFiles": 5,
        "maxSize": "10m"
    },
    "fileDrop": {
        "enabled": true,
        "watchPath": "~/.gomerai/mt5-bridge/file-drops/inbound",
        "processInterval": 5000
    }
}
```

## EA Integration

### MT5 Configuration Helper

The installation creates `mt5-bridge-config.mqh` for easy EA integration:

```cpp
// Include in EA
#include <mt5-bridge-config.mqh>

// Use SmartWebRequest instead of WebRequest
int result = SmartWebRequest("POST", "ingest", headers, timeout, data, response, responseHeaders);

// Fallback to file-drop if needed
if (result <= 0) {
    WriteToFileDrop(jsonData, "ingest");
}
```

### Bridge Endpoints

The bridge exposes the following local endpoints:

- `http://127.0.0.1:9876/health` - Health check
- `http://127.0.0.1:9876/status` - Status and statistics
- `http://127.0.0.1:9876/ingest` - EA data ingestion
- `http://127.0.0.1:9876/token` - Token broker
- `http://127.0.0.1:9876/dashboard` - Dashboard API
- `http://127.0.0.1:9876/ml-snapshot` - ML snapshot logging

## Installation Status Tracking

### Status Files

The installation creates status tracking files:

- `/tmp/gomerai-bridge-status.json` - Machine-readable status
- `/tmp/gomerai-bridge-summary.txt` - Human-readable summary
- `~/.gomerai/logs/mt5-bridge.log` - Runtime logs

### Status Reporting

The bridge reports status to the main installer:

```json
{
    "component": "mt5-bridge",
    "status": "healthy",
    "installation_time": "2025-01-XX",
    "version": "1.0.0",
    "port": 9876,
    "endpoints": {
        "ingest": "http://127.0.0.1:9876/ingest",
        "health": "http://127.0.0.1:9876/health"
    },
    "tmux_window": "mt5-bridge",
    "service_type": "tmux-managed"
}
```

## Customer Experience

### Installation Flow

1. Customer runs `installation.exe`
2. Main installer starts in tmux session
3. MT5 Bridge installs automatically as component
4. Bridge starts and validates connectivity
5. Customer receives MT5 configuration files
6. Installation completes with bridge running

### Post-Installation

- Bridge runs automatically in background
- Health monitoring via tmux window
- Logs available for troubleshooting
- MT5 EA uses local bridge endpoints
- Automatic fallback to direct GCP if needed

## Monitoring and Maintenance

### Tmux Commands

```bash
# View bridge window
tmux select-window -t gomerai-installation:mt5-bridge

# Check bridge logs
tail -f ~/.gomerai/logs/mt5-bridge.log

# Restart bridge service
tmux send-keys -t gomerai-installation:mt5-bridge.1 C-c
tmux send-keys -t gomerai-installation:mt5-bridge.1 "node bridge-launcher.js" C-m

# Check bridge health
curl http://127.0.0.1:9876/health
```

### Health Monitoring

The bridge includes built-in health monitoring:

- Automatic restart on failure
- Health checks every 30 seconds
- Queue monitoring and alerts
- Performance metrics tracking

## Security Considerations

### API Key Management

- API keys stored in configuration file (not in EA)
- Configuration file has restricted permissions
- Keys can be rotated without EA changes

### Network Security

- Bridge only listens on localhost (127.0.0.1)
- No external network exposure
- TLS/SSL handled by GCP endpoints
- Request validation and sanitization

## Troubleshooting

### Common Issues

1. **Port 9876 already in use**
   - Solution: Change port in configuration file

2. **Node.js not found**
   - Solution: Installation script installs Node.js automatically

3. **Bridge not starting**
   - Check: `~/.gomerai/logs/mt5-bridge.log`
   - Restart: Via tmux window

4. **EA can't connect to bridge**
   - Check: MT5 WebRequest whitelist includes `127.0.0.1`
   - Fallback: Direct GCP endpoints still work

### Support Commands

```bash
# Full bridge status
curl -s http://127.0.0.1:9876/status | jq .

# Test bridge connectivity
curl -X POST http://127.0.0.1:9876/ingest \
  -H "Content-Type: application/json" \
  -d '{"test": true}'

# View installation logs
cat ~/.gomerai/logs/mt5-bridge.log

# Check tmux session
tmux list-sessions
tmux list-windows -t gomerai-installation
```

## Version Management

### Updates

Bridge updates are delivered via the main installation system:

1. New bridge components in installation package
2. Configuration migration scripts
3. Service restart with zero downtime
4. Backward compatibility with existing EAs

### Rollback

If bridge update fails:

1. Automatic rollback to previous version
2. Configuration restoration
3. Service restart with old version
4. Error reporting to support

---

This package structure ensures the MT5 Bridge integrates seamlessly into the existing tmux installation.exe system while providing robust, reliable MT5 to GCP communication.
