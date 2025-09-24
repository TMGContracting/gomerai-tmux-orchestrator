# GomerAI tmux Orchestrator

Automated deployment and management scripts for GomerAI infrastructure using tmux sessions.

## Components

### Deployment Scripts
- **deploy-builder-tmux.sh** - tmux session builder and deployment automation
- **deploy-enterprise-ea-tmux.sh** - Enterprise EA deployment with tmux orchestration
- **gcp-vps-master-control.sh** - GCP VPS master control and monitoring

### Bridge Integration
- **tmux-installation-bridge/** - Bridge integration and installation scripts

## Features

- Automated tmux session management
- Enterprise EA deployment automation
- GCP VPS monitoring and control
- Bridge integration for seamless deployment
- Session persistence and recovery
- Automated error handling and logging

## Usage

```bash
# Deploy enterprise EA with tmux
./deploy-enterprise-ea-tmux.sh

# Build and deploy with tmux orchestration
./deploy-builder-tmux.sh

# Master control for GCP VPS
./gcp-vps-master-control.sh
```

## Architecture

The tmux orchestrator provides:
- **Session Management**: Automated creation and management of tmux sessions
- **Deployment Automation**: Streamlined deployment processes
- **Error Recovery**: Automatic handling of deployment failures
- **Bridge Integration**: Seamless integration with GomerAI bridge components

## Requirements

- tmux
- bash
- GCP CLI tools (for VPS control)
- SSH access to target systems
