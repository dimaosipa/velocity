#!/usr/bin/env node

const fs = require('fs-extra');
const path = require('path');
const MarkdownIt = require('markdown-it');
const markdownItAnchor = require('markdown-it-anchor');
const hljs = require('highlight.js');

// Configuration
const CONFIG = {
    inputFile: path.join(__dirname, '..', 'README.md'),
    templateFile: path.join(__dirname, 'template.html'),
    outputDir: path.join(__dirname, 'dist'),
    assetsDir: path.join(__dirname, 'assets'),
    title: 'Velo - Lightning-fast Package Manager for macOS',
    description: 'A lightning-fast, modern package manager for macOS - built for Apple Silicon.',
    baseUrl: 'https://velo.pages.dev'
};

// Initialize markdown parser with plugins
const md = new MarkdownIt({
    html: true,
    linkify: true,
    typographer: true,
    highlight: function (str, lang) {
        if (lang && hljs.getLanguage(lang)) {
            try {
                return hljs.highlight(str, { language: lang }).value;
            } catch (__) {}
        }
        return ''; // use external default escaping
    }
}).use(markdownItAnchor, {
    permalink: markdownItAnchor.permalink.linkInsideHeader({
        symbol: '#',
        renderAttrs: (slug, state) => ({ 'aria-label': `Permalink to "${slug}"` })
    })
});

/**
 * Extract table of contents from markdown content
 */
function generateTableOfContents(content) {
    const headings = [];
    const tokens = md.parse(content, {});
    
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token.type === 'heading_open') {
            const level = parseInt(token.tag.substring(1));
            const nextToken = tokens[i + 1];
            
            if (nextToken && nextToken.type === 'inline') {
                const text = nextToken.content;
                const slug = text.toLowerCase()
                    .replace(/[^\w\s-]/g, '')
                    .replace(/\s+/g, '-')
                    .trim();
                
                headings.push({
                    level,
                    text,
                    slug
                });
            }
        }
    }
    
    return headings;
}

/**
 * Generate HTML navigation from table of contents
 */
function generateNavigation(headings) {
    if (headings.length === 0) return '';
    
    let html = '<ul>\n';
    
    for (const heading of headings) {
        // Skip h1 (main title) and only show h2-h4
        if (heading.level === 1) continue;
        if (heading.level > 4) continue;
        
        const levelClass = `level-${heading.level}`;
        html += `    <li><a href="#${heading.slug}" class="${levelClass}">${heading.text}</a></li>\n`;
    }
    
    html += '</ul>';
    return html;
}

/**
 * Process markdown content and add features
 */
function processMarkdown(content) {
    // Add anchor IDs to headings manually to ensure they match our TOC
    const headings = generateTableOfContents(content);
    let processedContent = content;
    
    // Replace heading markdown with HTML that includes proper IDs
    for (const heading of headings) {
        const headingRegex = new RegExp(`^#{${heading.level}}\\s+${heading.text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'm');
        const replacement = `${'#'.repeat(heading.level)} <span id="${heading.slug}">${heading.text}</span>`;
        processedContent = processedContent.replace(headingRegex, replacement);
    }
    
    return md.render(processedContent);
}

/**
 * Copy assets to output directory
 */
async function copyAssets() {
    console.log('📁 Copying assets...');
    
    // Copy CSS file
    const cssSource = path.join(CONFIG.assetsDir, 'style.css');
    const cssTarget = path.join(CONFIG.outputDir, 'style.css');
    await fs.copy(cssSource, cssTarget);
    
    // Create a simple favicon if it doesn't exist
    const faviconPath = path.join(CONFIG.outputDir, 'favicon.ico');
    if (!await fs.pathExists(faviconPath)) {
        // Create a simple base64 favicon (16x16 blue square)
        const faviconData = Buffer.from(
            'AAABAAEAEBAAAAEAIABoBAAAFgAAACgAAAAQAAAAIAAAAAEAIAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAA' +
            'AAAAAAD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///' +
            'wD///8A////AP///wAAhv8AAIX/AACG/wAAhf8AAIX/AACG/wAAhf8AAIX/AACG/wAAhf8AAIX/AACG/wAAh' +
            'f8AAIX/AP///wD///8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AA' +
            'IX/AACF/wAAhf8A////AACG/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/A' +
            'ACF/wAAhf8AAIX/AP///wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/' +
            'wAAhf8AAIX/AACF/wD///8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAh' +
            'f8AAIX/AACF/wAAhf8A////AACG/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AA' +
            'IX/AACF/wAAhf8AAIX/AP///wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/A' +
            'ACF/wAAhf8AAIX/AACF/wD///8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/' +
            'wAAhf8AAIX/AACF/wAAhf8A////AACG/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAh' +
            'f8AAIX/AACF/wAAhf8AAIX/AP///wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AA' +
            'IX/AACF/wAAhf8AAIX/AACF/wD///8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/A' +
            'ACF/wAAhf8AAIX/AACF/wAAhf8A////AACG/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/' +
            'wAAhf8AAIX/AACF/wAAhf8AAIX/AP///wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAh' +
            'f8AAIX/AACF/wAAhf8AAIX/AACF/wD///8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AAIX/AACF/wAAhf8AA' +
            'IX/AACF/wAAhf8AAIX/AACF/wAAhf8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////A' +
            'P///wD///8A////AP///wD///8A////AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' +
            'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==', 
            'base64'
        );
        await fs.writeFile(faviconPath, faviconData);
    }
    
    console.log('✅ Assets copied successfully');
}

/**
 * Main build function
 */
async function build() {
    try {
        console.log('🚀 Building Velo website...');
        console.log(`📖 Reading README from: ${CONFIG.inputFile}`);
        
        // Ensure output directory exists
        await fs.ensureDir(CONFIG.outputDir);
        
        // Read input files
        const markdownContent = await fs.readFile(CONFIG.inputFile, 'utf8');
        const template = await fs.readFile(CONFIG.templateFile, 'utf8');
        
        // Generate table of contents
        const headings = generateTableOfContents(markdownContent);
        const navigation = generateNavigation(headings);
        
        // Convert markdown to HTML
        const htmlContent = processMarkdown(markdownContent);
        
        // Replace template placeholders
        const finalHtml = template
            .replace(/{{TITLE}}/g, CONFIG.title)
            .replace(/{{DESCRIPTION}}/g, CONFIG.description)
            .replace(/{{TABLE_OF_CONTENTS}}/g, navigation)
            .replace(/{{CONTENT}}/g, htmlContent);
        
        // Write output file
        const outputFile = path.join(CONFIG.outputDir, 'index.html');
        await fs.writeFile(outputFile, finalHtml, 'utf8');
        
        // Copy assets
        await copyAssets();
        
        console.log('✅ Website built successfully!');
        console.log(`📁 Output directory: ${CONFIG.outputDir}`);
        console.log(`🌐 Open: file://${outputFile}`);
        
        // Show build stats
        const stats = await fs.stat(outputFile);
        const sizeKB = (stats.size / 1024).toFixed(2);
        console.log(`📊 Generated ${sizeKB}KB HTML file with ${headings.length} sections`);
        
    } catch (error) {
        console.error('❌ Build failed:', error.message);
        process.exit(1);
    }
}

// Run build if this script is executed directly
if (require.main === module) {
    build();
}

module.exports = { build, CONFIG };