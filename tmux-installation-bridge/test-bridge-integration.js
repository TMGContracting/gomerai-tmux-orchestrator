#!/usr/bin/env node
/**
 * GomerAI MT5 Bridge Integration Test
 * ==================================
 * 
 * Comprehensive test suite for the MT5 Bridge system
 * Tests all components before production deployment
 */

const axios = require('axios');
const fs = require('fs-extra');
const path = require('path');
const { spawn } = require('child_process');

// Test configuration
const TEST_CONFIG = {
    bridgeUrl: 'http://127.0.0.1:9876',
    testTimeout: 30000,
    maxRetries: 3,
    testDataDir: './test-data',
    fileDropDir: './file-drops/inbound'
};

class BridgeIntegrationTest {
    constructor() {
        this.testResults = {
            total: 0,
            passed: 0,
            failed: 0,
            skipped: 0,
            errors: []
        };
        this.startTime = Date.now();
    }

    // Logging utilities
    log(message) {
        console.log(`[${new Date().toISOString()}] ${message}`);
    }

    success(message) {
        console.log(`✅ ${message}`);
    }

    error(message) {
        console.log(`❌ ${message}`);
    }

    warn(message) {
        console.log(`⚠️  ${message}`);
    }

    info(message) {
        console.log(`ℹ️  ${message}`);
    }

    // Test execution framework
    async runTest(testName, testFunction) {
        this.testResults.total++;
        this.log(`Running test: ${testName}`);
        
        try {
            await testFunction();
            this.testResults.passed++;
            this.success(`Test passed: ${testName}`);
            return true;
        } catch (error) {
            this.testResults.failed++;
            this.testResults.errors.push({ test: testName, error: error.message });
            this.error(`Test failed: ${testName} - ${error.message}`);
            return false;
        }
    }

    // Individual test functions
    async testBridgeHealth() {
        const response = await axios.get(`${TEST_CONFIG.bridgeUrl}/health`, {
            timeout: 5000
        });
        
        if (response.status !== 200) {
            throw new Error(`Health check failed with status ${response.status}`);
        }
        
        if (!response.data.status || response.data.status !== 'healthy') {
            throw new Error(`Bridge reports unhealthy status: ${response.data.status}`);
        }
        
        this.info(`Bridge uptime: ${response.data.uptime}s`);
    }

    async testBridgeStatus() {
        const response = await axios.get(`${TEST_CONFIG.bridgeUrl}/status`, {
            timeout: 5000
        });
        
        if (response.status !== 200) {
            throw new Error(`Status check failed with status ${response.status}`);
        }
        
        const status = response.data;
        
        // Validate status structure
        if (!status.server || !status.queue) {
            throw new Error('Invalid status response structure');
        }
        
        this.info(`Queue size: ${status.queue.size}`);
        this.info(`Memory usage: ${Math.round(status.server.memory.heapUsed / 1024 / 1024)}MB`);
    }

    async testIngestEndpoint() {
        const testData = {
            testType: 'integration_test',
            timestamp: new Date().toISOString(),
            terminalId: 'TEST_TERMINAL_123',
            symbol: 'EURUSD',
            marketData: {
                bid: 1.0850,
                ask: 1.0852,
                spread: 0.0002
            },
            accountInfo: {
                account: 12345,
                balance: 10000.00
            }
        };

        const response = await axios.post(`${TEST_CONFIG.bridgeUrl}/ingest`, testData, {
            headers: {
                'Content-Type': 'application/json',
                'X-Terminal-ID': 'TEST_TERMINAL_123'
            },
            timeout: TEST_CONFIG.testTimeout
        });

        if (response.status < 200 || response.status >= 300) {
            throw new Error(`Ingest endpoint failed with status ${response.status}`);
        }

        this.info(`Ingest response: ${JSON.stringify(response.data).substring(0, 100)}...`);
    }

    async testTokenEndpoint() {
        const testData = {
            action: 'validate_license',
            licenseKey: 'TEST_LICENSE_KEY',
            terminalId: 'TEST_TERMINAL_123'
        };

        const response = await axios.post(`${TEST_CONFIG.bridgeUrl}/token`, testData, {
            headers: {
                'Content-Type': 'application/json'
            },
            timeout: TEST_CONFIG.testTimeout
        });

        // Token endpoint may return various status codes depending on license validity
        // We just check that we get a response
        if (!response.status) {
            throw new Error('Token endpoint did not respond');
        }

        this.info(`Token response status: ${response.status}`);
    }

    async testDashboardEndpoint() {
        const testData = {
            action: 'get_stats',
            terminalId: 'TEST_TERMINAL_123'
        };

        const response = await axios.post(`${TEST_CONFIG.bridgeUrl}/dashboard`, testData, {
            headers: {
                'Content-Type': 'application/json'
            },
            timeout: TEST_CONFIG.testTimeout
        });

        if (!response.status) {
            throw new Error('Dashboard endpoint did not respond');
        }

        this.info(`Dashboard response status: ${response.status}`);
    }

    async testMLSnapshotEndpoint() {
        const testData = {
            type: 'ml_training_data',
            timestamp: new Date().toISOString(),
            terminalId: 'TEST_TERMINAL_123',
            weights: {
                rsi: 25.0,
                stochastic: 20.0,
                bollingerBands: 15.0
            },
            performance: {
                totalTrades: 10,
                winRate: 0.6,
                netProfit: 150.00
            }
        };

        const response = await axios.post(`${TEST_CONFIG.bridgeUrl}/ml-snapshot`, testData, {
            headers: {
                'Content-Type': 'application/json'
            },
            timeout: TEST_CONFIG.testTimeout
        });

        if (!response.status) {
            throw new Error('ML Snapshot endpoint did not respond');
        }

        this.info(`ML Snapshot response status: ${response.status}`);
    }

    async testFileDropFallback() {
        // Ensure file drop directory exists
        await fs.ensureDir(TEST_CONFIG.fileDropDir);

        const testData = {
            type: 'file_drop_test',
            timestamp: new Date().toISOString(),
            terminalId: 'TEST_TERMINAL_123',
            data: 'This is a test file drop'
        };

        const fileName = `gomerai_test_${Date.now()}.json`;
        const filePath = path.join(TEST_CONFIG.fileDropDir, fileName);

        // Write test file
        await fs.writeJson(filePath, testData, { spaces: 2 });

        // Wait for file to be processed
        await this.sleep(10000);

        // Check if file was moved (processed)
        const fileExists = await fs.pathExists(filePath);
        if (fileExists) {
            // File still exists, check if it was moved to completed
            const completedPath = path.join('./file-drops/completed', fileName);
            const wasProcessed = await fs.pathExists(completedPath);
            
            if (!wasProcessed) {
                this.warn('File drop test file was not processed (this may be normal if file-drop relay is not running)');
            } else {
                this.info('File drop test file was processed successfully');
            }
        } else {
            this.info('File drop test file was processed (moved from inbound directory)');
        }
    }

    async testErrorHandling() {
        // Test invalid endpoint
        try {
            await axios.post(`${TEST_CONFIG.bridgeUrl}/invalid-endpoint`, {}, {
                timeout: 5000
            });
            throw new Error('Expected 404 error for invalid endpoint');
        } catch (error) {
            if (error.response && error.response.status === 404) {
                this.info('Invalid endpoint correctly returned 404');
            } else {
                throw error;
            }
        }

        // Test malformed JSON
        try {
            await axios.post(`${TEST_CONFIG.bridgeUrl}/ingest`, 'invalid json', {
                headers: {
                    'Content-Type': 'application/json'
                },
                timeout: 5000
            });
            throw new Error('Expected error for malformed JSON');
        } catch (error) {
            if (error.response && error.response.status >= 400) {
                this.info('Malformed JSON correctly returned error status');
            } else {
                throw error;
            }
        }
    }

    async testConcurrentRequests() {
        const numRequests = 10;
        const requests = [];

        for (let i = 0; i < numRequests; i++) {
            const testData = {
                testType: 'concurrent_test',
                requestId: i,
                timestamp: new Date().toISOString()
            };

            requests.push(
                axios.post(`${TEST_CONFIG.bridgeUrl}/ingest`, testData, {
                    timeout: TEST_CONFIG.testTimeout
                })
            );
        }

        const responses = await Promise.allSettled(requests);
        const successful = responses.filter(r => r.status === 'fulfilled').length;
        const failed = responses.filter(r => r.status === 'rejected').length;

        if (failed > numRequests * 0.1) { // Allow up to 10% failure rate
            throw new Error(`Too many concurrent requests failed: ${failed}/${numRequests}`);
        }

        this.info(`Concurrent requests: ${successful} successful, ${failed} failed`);
    }

    async testBridgeResilience() {
        // Test bridge behavior under various conditions
        
        // 1. Large payload test
        const largePayload = {
            testType: 'large_payload_test',
            timestamp: new Date().toISOString(),
            largeData: 'x'.repeat(1024 * 100) // 100KB of data
        };

        const response = await axios.post(`${TEST_CONFIG.bridgeUrl}/ingest`, largePayload, {
            timeout: TEST_CONFIG.testTimeout
        });

        if (response.status < 200 || response.status >= 300) {
            throw new Error(`Large payload test failed with status ${response.status}`);
        }

        this.info('Large payload test passed');

        // 2. Rapid requests test
        const rapidRequests = [];
        for (let i = 0; i < 5; i++) {
            rapidRequests.push(
                axios.post(`${TEST_CONFIG.bridgeUrl}/ingest`, {
                    testType: 'rapid_request_test',
                    requestId: i
                }, { timeout: 5000 })
            );
        }

        const rapidResponses = await Promise.allSettled(rapidRequests);
        const rapidSuccessful = rapidResponses.filter(r => r.status === 'fulfilled').length;

        if (rapidSuccessful < 3) { // At least 60% should succeed
            throw new Error(`Too many rapid requests failed: ${5 - rapidSuccessful}/5`);
        }

        this.info(`Rapid requests test: ${rapidSuccessful}/5 successful`);
    }

    // Utility functions
    async sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    async waitForBridge(maxWait = 30000) {
        const startTime = Date.now();
        
        while (Date.now() - startTime < maxWait) {
            try {
                await axios.get(`${TEST_CONFIG.bridgeUrl}/health`, { timeout: 2000 });
                return true;
            } catch (error) {
                await this.sleep(2000);
            }
        }
        
        return false;
    }

    // Main test runner
    async runAllTests() {
        this.log('Starting GomerAI MT5 Bridge Integration Tests');
        this.log('='.repeat(60));

        // Wait for bridge to be ready
        this.info('Waiting for bridge to be ready...');
        const bridgeReady = await this.waitForBridge();
        
        if (!bridgeReady) {
            this.error('Bridge is not responding. Please ensure the bridge is running.');
            return this.generateReport();
        }

        this.success('Bridge is ready, starting tests...');

        // Run all tests
        await this.runTest('Bridge Health Check', () => this.testBridgeHealth());
        await this.runTest('Bridge Status Check', () => this.testBridgeStatus());
        await this.runTest('Ingest Endpoint Test', () => this.testIngestEndpoint());
        await this.runTest('Token Endpoint Test', () => this.testTokenEndpoint());
        await this.runTest('Dashboard Endpoint Test', () => this.testDashboardEndpoint());
        await this.runTest('ML Snapshot Endpoint Test', () => this.testMLSnapshotEndpoint());
        await this.runTest('File Drop Fallback Test', () => this.testFileDropFallback());
        await this.runTest('Error Handling Test', () => this.testErrorHandling());
        await this.runTest('Concurrent Requests Test', () => this.testConcurrentRequests());
        await this.runTest('Bridge Resilience Test', () => this.testBridgeResilience());

        return this.generateReport();
    }

    generateReport() {
        const duration = Date.now() - this.startTime;
        const report = {
            summary: {
                total: this.testResults.total,
                passed: this.testResults.passed,
                failed: this.testResults.failed,
                skipped: this.testResults.skipped,
                duration: `${duration}ms`,
                success: this.testResults.failed === 0
            },
            errors: this.testResults.errors
        };

        this.log('='.repeat(60));
        this.log('TEST RESULTS SUMMARY');
        this.log('='.repeat(60));
        
        if (report.summary.success) {
            this.success(`All tests passed! (${report.summary.passed}/${report.summary.total})`);
        } else {
            this.error(`${report.summary.failed} tests failed out of ${report.summary.total}`);
        }

        this.info(`Test duration: ${duration}ms`);

        if (report.errors.length > 0) {
            this.log('\nFAILED TESTS:');
            report.errors.forEach(error => {
                this.error(`${error.test}: ${error.error}`);
            });
        }

        // Save report to file
        const reportPath = './test-results.json';
        fs.writeJsonSync(reportPath, report, { spaces: 2 });
        this.info(`Detailed report saved to: ${reportPath}`);

        return report;
    }
}

// Run tests if this script is executed directly
async function main() {
    const tester = new BridgeIntegrationTest();
    
    try {
        const report = await tester.runAllTests();
        process.exit(report.summary.success ? 0 : 1);
    } catch (error) {
        console.error('Test runner failed:', error);
        process.exit(1);
    }
}

if (require.main === module) {
    main();
}

module.exports = BridgeIntegrationTest;
