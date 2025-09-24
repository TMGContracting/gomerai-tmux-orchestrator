#!/usr/bin/env node
/**
 * GomerAI MT5 Bridge Launcher
 * ===========================
 * 
 * Production launcher for MT5 Bridge system
 * Designed to be embedded in tmux installation.exe
 */

const fs = require('fs');
const path = require('path');
const { spawn, fork } = require('child_process');

// Configuration
const CONFIG = {
    configPath: process.env.GOMERAI_CONFIG_PATH || './config/bridge-config.json',
    relayScript: './relay-server.js',
    fileDropScript: './file-drop-relay.js',
    healthCheckInterval: 30000, // 30 seconds
    restartDelay: 5000, // 5 seconds
    maxRestarts: 10,
    restartWindow: 300000 // 5 minutes
};

class BridgeLauncher {
    constructor() {
        this.config = null;
        this.relayProcess = null;
        this.fileDropProcess = null;
        this.restartCounts = {
            relay: 0,
            fileDrop: 0
        };
        this.restartTimestamps = {
            relay: [],
            fileDrop: []
        };
        this.healthCheckTimer = null;
        this.isShuttingDown = false;
    }

    async initialize() {
        console.log('🚀 GomerAI MT5 Bridge Launcher Starting...');
        
        // Load configuration
        await this.loadConfiguration();
        
        // Setup signal handlers
        this.setupSignalHandlers();
        
        // Start bridge components
        await this.startBridgeComponents();
        
        // Start health monitoring
        this.startHealthMonitoring();
        
        console.log('✅ MT5 Bridge Launcher initialized successfully');
        console.log(`📊 Health checks every ${CONFIG.healthCheckInterval / 1000} seconds`);
        console.log(`🔄 Max ${CONFIG.maxRestarts} restarts per ${CONFIG.restartWindow / 60000} minutes`);
    }

    async loadConfiguration() {
        try {
            if (!fs.existsSync(CONFIG.configPath)) {
                throw new Error(`Configuration file not found: ${CONFIG.configPath}`);
            }
            
            const configData = fs.readFileSync(CONFIG.configPath, 'utf8');
            this.config = JSON.parse(configData);
            
            console.log(`📋 Configuration loaded from: ${CONFIG.configPath}`);
            console.log(`🔧 Bridge version: ${this.config.version}`);
            console.log(`🌐 Relay port: ${this.config.relay.port}`);
            
        } catch (error) {
            console.error('❌ Failed to load configuration:', error.message);
            process.exit(1);
        }
    }

    setupSignalHandlers() {
        const gracefulShutdown = (signal) => {
            console.log(`\n🛑 Received ${signal}, shutting down gracefully...`);
            this.shutdown();
        };

        process.on('SIGINT', gracefulShutdown);
        process.on('SIGTERM', gracefulShutdown);
        process.on('SIGHUP', () => {
            console.log('🔄 Received SIGHUP, reloading configuration...');
            this.reloadConfiguration();
        });

        process.on('uncaughtException', (error) => {
            console.error('💥 Uncaught Exception:', error);
            this.shutdown();
        });

        process.on('unhandledRejection', (reason, promise) => {
            console.error('💥 Unhandled Rejection at:', promise, 'reason:', reason);
        });
    }

    async startBridgeComponents() {
        console.log('🔧 Starting bridge components...');
        
        // Start HTTP Relay Server
        await this.startRelayServer();
        
        // Start File Drop Relay (if enabled)
        if (this.config.fileDrop && this.config.fileDrop.enabled) {
            await this.startFileDropRelay();
        } else {
            console.log('📁 File Drop Relay disabled in configuration');
        }
    }

    async startRelayServer() {
        return new Promise((resolve, reject) => {
            console.log('🌐 Starting HTTP Relay Server...');
            
            const relayEnv = {
                ...process.env,
                NODE_ENV: 'production',
                GOMERAI_CONFIG_PATH: CONFIG.configPath
            };

            this.relayProcess = fork(CONFIG.relayScript, [], {
                env: relayEnv,
                silent: false
            });

            this.relayProcess.on('message', (message) => {
                if (message.type === 'ready') {
                    console.log('✅ HTTP Relay Server started successfully');
                    resolve();
                } else if (message.type === 'error') {
                    console.error('❌ HTTP Relay Server error:', message.error);
                }
            });

            this.relayProcess.on('exit', (code, signal) => {
                console.log(`🔄 HTTP Relay Server exited (code: ${code}, signal: ${signal})`);
                
                if (!this.isShuttingDown) {
                    this.handleProcessExit('relay', code, signal);
                }
            });

            this.relayProcess.on('error', (error) => {
                console.error('❌ HTTP Relay Server spawn error:', error);
                reject(error);
            });

            // Timeout for startup
            setTimeout(() => {
                if (this.relayProcess && !this.relayProcess.killed) {
                    console.log('✅ HTTP Relay Server startup timeout reached, assuming success');
                    resolve();
                }
            }, 10000);
        });
    }

    async startFileDropRelay() {
        return new Promise((resolve, reject) => {
            console.log('📁 Starting File Drop Relay...');
            
            const fileDropEnv = {
                ...process.env,
                NODE_ENV: 'production',
                GOMERAI_CONFIG_PATH: CONFIG.configPath
            };

            this.fileDropProcess = fork(CONFIG.fileDropScript, [], {
                env: fileDropEnv,
                silent: false
            });

            this.fileDropProcess.on('message', (message) => {
                if (message.type === 'ready') {
                    console.log('✅ File Drop Relay started successfully');
                    resolve();
                } else if (message.type === 'error') {
                    console.error('❌ File Drop Relay error:', message.error);
                }
            });

            this.fileDropProcess.on('exit', (code, signal) => {
                console.log(`🔄 File Drop Relay exited (code: ${code}, signal: ${signal})`);
                
                if (!this.isShuttingDown) {
                    this.handleProcessExit('fileDrop', code, signal);
                }
            });

            this.fileDropProcess.on('error', (error) => {
                console.error('❌ File Drop Relay spawn error:', error);
                reject(error);
            });

            // Timeout for startup
            setTimeout(() => {
                if (this.fileDropProcess && !this.fileDropProcess.killed) {
                    console.log('✅ File Drop Relay startup timeout reached, assuming success');
                    resolve();
                }
            }, 5000);
        });
    }

    handleProcessExit(processType, code, signal) {
        const now = Date.now();
        const timestamps = this.restartTimestamps[processType];
        
        // Clean old timestamps (outside restart window)
        const cutoff = now - CONFIG.restartWindow;
        this.restartTimestamps[processType] = timestamps.filter(t => t > cutoff);
        
        // Check if we've exceeded restart limit
        if (this.restartTimestamps[processType].length >= CONFIG.maxRestarts) {
            console.error(`💀 ${processType} has exceeded restart limit (${CONFIG.maxRestarts} restarts in ${CONFIG.restartWindow / 60000} minutes)`);
            console.error('🛑 Stopping automatic restarts to prevent infinite loop');
            return;
        }
        
        // Add current restart timestamp
        this.restartTimestamps[processType].push(now);
        this.restartCounts[processType]++;
        
        console.log(`🔄 Restarting ${processType} in ${CONFIG.restartDelay / 1000} seconds (attempt ${this.restartCounts[processType]})...`);
        
        setTimeout(() => {
            if (!this.isShuttingDown) {
                if (processType === 'relay') {
                    this.startRelayServer().catch(error => {
                        console.error('❌ Failed to restart HTTP Relay Server:', error);
                    });
                } else if (processType === 'fileDrop') {
                    this.startFileDropRelay().catch(error => {
                        console.error('❌ Failed to restart File Drop Relay:', error);
                    });
                }
            }
        }, CONFIG.restartDelay);
    }

    startHealthMonitoring() {
        console.log('🏥 Starting health monitoring...');
        
        this.healthCheckTimer = setInterval(() => {
            this.performHealthCheck();
        }, CONFIG.healthCheckInterval);
        
        // Perform initial health check after a delay
        setTimeout(() => {
            this.performHealthCheck();
        }, 10000);
    }

    async performHealthCheck() {
        try {
            const axios = require('axios');
            const healthUrl = `http://127.0.0.1:${this.config.relay.port}/health`;
            
            const response = await axios.get(healthUrl, { timeout: 5000 });
            
            if (response.status === 200) {
                console.log('💚 Health check passed - Bridge is healthy');
                
                // Log queue status if available
                if (response.data.queue) {
                    const queueSize = response.data.queue.size;
                    if (queueSize > 0) {
                        console.log(`📊 Queue status: ${queueSize} items pending`);
                    }
                }
            } else {
                console.warn(`💛 Health check warning - HTTP ${response.status}`);
            }
            
        } catch (error) {
            console.error('❤️‍🩹 Health check failed:', error.message);
            
            // If health check fails, the process exit handler will restart components
            if (error.code === 'ECONNREFUSED') {
                console.log('🔄 HTTP Relay Server appears to be down, restart should be triggered');
            }
        }
    }

    async reloadConfiguration() {
        try {
            console.log('🔄 Reloading configuration...');
            await this.loadConfiguration();
            
            // Send reload signal to child processes
            if (this.relayProcess) {
                this.relayProcess.send({ type: 'reload' });
            }
            if (this.fileDropProcess) {
                this.fileDropProcess.send({ type: 'reload' });
            }
            
            console.log('✅ Configuration reloaded successfully');
            
        } catch (error) {
            console.error('❌ Failed to reload configuration:', error.message);
        }
    }

    async shutdown() {
        if (this.isShuttingDown) {
            return;
        }
        
        this.isShuttingDown = true;
        console.log('🛑 Shutting down MT5 Bridge Launcher...');
        
        // Stop health monitoring
        if (this.healthCheckTimer) {
            clearInterval(this.healthCheckTimer);
        }
        
        // Gracefully stop child processes
        const shutdownPromises = [];
        
        if (this.relayProcess) {
            shutdownPromises.push(this.stopProcess(this.relayProcess, 'HTTP Relay Server'));
        }
        
        if (this.fileDropProcess) {
            shutdownPromises.push(this.stopProcess(this.fileDropProcess, 'File Drop Relay'));
        }
        
        // Wait for all processes to stop
        await Promise.all(shutdownPromises);
        
        console.log('✅ MT5 Bridge Launcher shutdown complete');
        process.exit(0);
    }

    async stopProcess(process, name) {
        return new Promise((resolve) => {
            console.log(`🛑 Stopping ${name}...`);
            
            // Send graceful shutdown signal
            process.send({ type: 'shutdown' });
            
            // Wait for graceful shutdown
            const timeout = setTimeout(() => {
                console.log(`⚡ Force killing ${name} (graceful shutdown timeout)`);
                process.kill('SIGKILL');
            }, 10000);
            
            process.on('exit', () => {
                clearTimeout(timeout);
                console.log(`✅ ${name} stopped`);
                resolve();
            });
        });
    }

    getStatus() {
        return {
            launcher: {
                uptime: process.uptime(),
                pid: process.pid,
                memory: process.memoryUsage(),
                isShuttingDown: this.isShuttingDown
            },
            processes: {
                relay: {
                    running: this.relayProcess && !this.relayProcess.killed,
                    pid: this.relayProcess ? this.relayProcess.pid : null,
                    restarts: this.restartCounts.relay
                },
                fileDrop: {
                    running: this.fileDropProcess && !this.fileDropProcess.killed,
                    pid: this.fileDropProcess ? this.fileDropProcess.pid : null,
                    restarts: this.restartCounts.fileDrop
                }
            },
            config: {
                version: this.config ? this.config.version : 'unknown',
                relayPort: this.config ? this.config.relay.port : 'unknown'
            }
        };
    }
}

// Start the launcher if this script is run directly
async function main() {
    const launcher = new BridgeLauncher();
    
    try {
        await launcher.initialize();
        
        // Keep the process running
        process.stdin.resume();
        
        // Optional: Expose status endpoint via HTTP
        if (process.env.ENABLE_STATUS_SERVER === 'true') {
            const express = require('express');
            const statusApp = express();
            
            statusApp.get('/launcher-status', (req, res) => {
                res.json(launcher.getStatus());
            });
            
            const statusPort = process.env.STATUS_PORT || 9877;
            statusApp.listen(statusPort, '127.0.0.1', () => {
                console.log(`📊 Launcher status server running on http://127.0.0.1:${statusPort}/launcher-status`);
            });
        }
        
    } catch (error) {
        console.error('💥 Failed to start MT5 Bridge Launcher:', error);
        process.exit(1);
    }
}

if (require.main === module) {
    main();
}

module.exports = BridgeLauncher;
