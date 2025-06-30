#!/usr/bin/env node

const fs = require('fs-extra');
const path = require('path');
const http = require('http');
const { spawn } = require('child_process');

const CONFIG = {
    distDir: path.join(__dirname, 'dist'),
    port: 8080,
    testTimeout: 5000
};

/**
 * Test server to serve static files
 */
function createTestServer() {
    return new Promise((resolve, reject) => {
        const handler = (req, res) => {
            let filePath = path.join(CONFIG.distDir, req.url === '/' ? 'index.html' : req.url);
            
            // Handle directory URLs
            if (req.url.endsWith('/') && req.url !== '/') {
                filePath = path.join(CONFIG.distDir, req.url, 'index.html');
            }
            
            fs.readFile(filePath, (err, data) => {
                if (err) {
                    res.writeHead(404);
                    res.end('404 Not Found');
                    return;
                }
                
                const ext = path.extname(filePath);
                const contentType = {
                    '.html': 'text/html',
                    '.css': 'text/css',
                    '.js': 'application/javascript',
                    '.png': 'image/png',
                    '.jpg': 'image/jpeg',
                    '.ico': 'image/x-icon',
                    '.json': 'application/json'
                }[ext] || 'text/plain';
                
                res.writeHead(200, { 'Content-Type': contentType });
                res.end(data);
            });
        };
        
        const server = http.createServer(handler);
        server.listen(CONFIG.port, (err) => {
            if (err) reject(err);
            else resolve(server);
        });
    });
}

/**
 * Check if all required files exist
 */
async function validateFiles() {
    console.log('🔍 Validating required files...');
    
    const requiredFiles = [
        'index.html',
        'home.css',
        'docs.css', 
        'logo.png',
        'favicon.ico',
        'docs/index.html',
        'docs/installation/index.html',
        'docs/commands/index.html',
        'docs/local-packages/index.html',
        'docs/architecture/index.html',
        'docs/contributing/index.html'
    ];
    
    let passed = 0;
    let failed = 0;
    
    for (const file of requiredFiles) {
        const filePath = path.join(CONFIG.distDir, file);
        if (await fs.pathExists(filePath)) {
            console.log(`  ✅ ${file}`);
            passed++;
        } else {
            console.log(`  ❌ ${file} - MISSING`);
            failed++;
        }
    }
    
    console.log(`📊 Files: ${passed} passed, ${failed} failed\n`);
    return failed === 0;
}

/**
 * Validate HTML structure and links
 */
async function validateHTML() {
    console.log('🔍 Validating HTML structure...');
    
    const htmlFiles = [
        'index.html',
        'docs/index.html',
        'docs/installation/index.html',
        'docs/commands/index.html'
    ];
    
    let passed = 0;
    let failed = 0;
    
    for (const file of htmlFiles) {
        const filePath = path.join(CONFIG.distDir, file);
        if (!(await fs.pathExists(filePath))) continue;
        
        const content = await fs.readFile(filePath, 'utf8');
        
        // Check for required elements
        const checks = [
            { name: 'DOCTYPE', test: content.includes('<!DOCTYPE html>') },
            { name: 'Title', test: content.includes('<title>') },
            { name: 'CSS link', test: content.includes('stylesheet') },
            { name: 'Logo image', test: content.includes('logo.png') },
            { name: 'No broken {{}}', test: !content.includes('{{') }
        ];
        
        let filePassed = true;
        for (const check of checks) {
            if (check.test) {
                console.log(`  ✅ ${file}: ${check.name}`);
                passed++;
            } else {
                console.log(`  ❌ ${file}: ${check.name} - FAILED`);
                failed++;
                filePassed = false;
            }
        }
        
        if (filePassed) {
            console.log(`  🎉 ${file} - All checks passed`);
        }
    }
    
    console.log(`📊 HTML checks: ${passed} passed, ${failed} failed\n`);
    return failed === 0;
}

/**
 * Test asset loading
 */
async function validateAssets() {
    console.log('🔍 Validating assets...');
    
    const assets = [
        { path: 'home.css', type: 'CSS' },
        { path: 'docs.css', type: 'CSS' },
        { path: 'logo.png', type: 'Image' },
        { path: 'favicon.ico', type: 'Icon' }
    ];
    
    let passed = 0;
    let failed = 0;
    
    for (const asset of assets) {
        const filePath = path.join(CONFIG.distDir, asset.path);
        
        if (await fs.pathExists(filePath)) {
            const stats = await fs.stat(filePath);
            if (stats.size > 0) {
                console.log(`  ✅ ${asset.type}: ${asset.path} (${(stats.size / 1024).toFixed(1)}KB)`);
                passed++;
            } else {
                console.log(`  ❌ ${asset.type}: ${asset.path} - EMPTY FILE`);
                failed++;
            }
        } else {
            console.log(`  ❌ ${asset.type}: ${asset.path} - MISSING`);
            failed++;
        }
    }
    
    console.log(`📊 Assets: ${passed} passed, ${failed} failed\n`);
    return failed === 0;
}

/**
 * Run all tests
 */
async function runTests() {
    console.log('🚀 Starting Velocity website tests...\n');
    
    // Check if dist directory exists
    if (!(await fs.pathExists(CONFIG.distDir))) {
        console.log('❌ dist/ directory not found. Run "npm run build" first.');
        process.exit(1);
    }
    
    const results = await Promise.all([
        validateFiles(),
        validateHTML(), 
        validateAssets()
    ]);
    
    const allPassed = results.every(result => result);
    
    if (allPassed) {
        console.log('🎉 All tests passed! Website is ready for deployment.');
        console.log(`🌐 Test locally: http://localhost:${CONFIG.port}`);
        
        // Optionally start local server
        if (process.argv.includes('--serve')) {
            console.log('\n🖥️  Starting local test server...');
            const server = await createTestServer();
            console.log(`📡 Server running at http://localhost:${CONFIG.port}`);
            console.log('Press Ctrl+C to stop');
        }
        
        process.exit(0);
    } else {
        console.log('❌ Some tests failed. Fix the issues before deploying.');
        process.exit(1);
    }
}

// Run tests if this script is executed directly
if (require.main === module) {
    runTests().catch(error => {
        console.error('💥 Test runner failed:', error.message);
        process.exit(1);
    });
}

module.exports = { runTests, validateFiles, validateHTML, validateAssets };