#!/usr/bin/env node

const fs = require('fs-extra');
const path = require('path');
const MarkdownIt = require('markdown-it');
const markdownItAnchor = require('markdown-it-anchor');
const hljs = require('highlight.js');

// Configuration
const CONFIG = {
    // Input files
    readmeFile: path.join(__dirname, '..', 'README.md'),
    docsDir: path.join(__dirname, '..', 'docs'),
    
    // Templates
    homeTemplate: path.join(__dirname, 'templates', 'home.html'),
    docsTemplate: path.join(__dirname, 'templates', 'docs.html'),
    
    // Assets
    assetsDir: path.join(__dirname, 'assets'),
    
    // Output
    outputDir: path.join(__dirname, 'dist'),
    
    // Site info
    title: 'Velocity - Lightning-fast Package Manager for Apple Silicon',
    description: 'Native speed. Modern architecture. Zero sudo required. A lightning-fast package manager built exclusively for M1/M2/M3 Macs.',
    baseUrl: process.env.GITHUB_PAGES_URL || 'https://dimaosipa.github.io/velocity'
};

// Documentation structure
const DOCS_STRUCTURE = [
    { 
        file: 'installation.md', 
        title: 'Installation Guide', 
        path: '/docs/installation',
        description: 'Complete installation guide for Velocity package manager'
    },
    { 
        file: 'commands.md', 
        title: 'Command Reference', 
        path: '/docs/commands',
        description: 'Complete reference for all Velocity commands'
    },
    { 
        file: 'local-packages.md', 
        title: 'Local Package Management', 
        path: '/docs/local-packages',
        description: 'Project-local dependency management with velo.json'
    },
    { 
        file: 'architecture.md', 
        title: 'Architecture', 
        path: '/docs/architecture',
        description: 'Technical design and implementation details'
    },
    { 
        file: 'contributing.md', 
        title: 'Contributing', 
        path: '/docs/contributing',
        description: 'Development guide and contribution workflow'
    }
];

// Initialize markdown parser
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
        return '';
    }
}).use(markdownItAnchor, {
    permalink: markdownItAnchor.permalink.linkInsideHeader({
        symbol: '#',
        renderAttrs: (slug, state) => ({ 'aria-label': `Permalink to "${slug}"` })
    })
});

/**
 * Generate slug from text
 */
function generateSlug(text) {
    return text
        .toLowerCase()
        .replace(/[^\w\s-]/g, '')
        .replace(/\s+/g, '-')
        .trim();
}

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
                const slug = generateSlug(text);
                
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
function generateNavigation(headings, isMainNav = false) {
    if (headings.length === 0) return '';
    
    let html = '<ul>\n';
    
    for (const heading of headings) {
        // Skip h1 for main nav, show h2-h4 only
        if (isMainNav && (heading.level === 1 || heading.level > 4)) continue;
        
        const levelClass = `level-${heading.level}`;
        html += `    <li><a href="#${heading.slug}" class="${levelClass}">${heading.text}</a></li>\n`;
    }
    
    html += '</ul>';
    return html;
}

/**
 * Generate sidebar navigation based on page depth
 */
function generateSidebarNavigation(currentPagePath) {
    const isRootDocs = currentPagePath === '/docs';
    
    let overviewHref, itemHref;
    
    if (isRootDocs) {
        // From /docs/ page - use relative paths
        overviewHref = './';
        itemHref = (path) => `./${path}/`;
    } else {
        // From /docs/subpage/ page - calculate proper relative paths
        overviewHref = '../';
        itemHref = (path) => {
            const currentPage = currentPagePath.replace('/docs/', '');
            return path === currentPage ? './' : `NAVLINK:${path}`;
        };
    }
    
    const navigation = `
        <div class="nav-section">
            <h4 class="nav-section-title">Getting Started</h4>
            <ul class="nav-list">
                <li><a href="${overviewHref}" class="nav-item">Overview</a></li>
                <li><a href="${itemHref('installation')}" class="nav-item">Installation</a></li>
                <li><a href="${itemHref('commands')}" class="nav-item">Commands</a></li>
            </ul>
        </div>
        
        <div class="nav-section">
            <h4 class="nav-section-title">Core Concepts</h4>
            <ul class="nav-list">
                <li><a href="${itemHref('local-packages')}" class="nav-item">Local Packages</a></li>
                <li><a href="${itemHref('architecture')}" class="nav-item">Architecture</a></li>
            </ul>
        </div>
        
        <div class="nav-section">
            <h4 class="nav-section-title">Development</h4>
            <ul class="nav-list">
                <li><a href="${itemHref('contributing')}" class="nav-item">Contributing</a></li>
            </ul>
        </div>
    `;
    
    return navigation;
}

/**
 * Process markdown content and add proper heading IDs
 */
function processMarkdown(content) {
    // First pass: generate headings to get proper slugs
    const headings = generateTableOfContents(content);
    let processedContent = content;
    
    // Replace heading markdown with HTML that includes proper IDs
    for (const heading of headings) {
        const headingRegex = new RegExp(
            `^#{${heading.level}}\\s+${heading.text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 
            'm'
        );
        const replacement = `${'#'.repeat(heading.level)} <span id="${heading.slug}">${heading.text}</span>`;
        processedContent = processedContent.replace(headingRegex, replacement);
    }
    
    return md.render(processedContent);
}

/**
 * Copy and optimize assets
 */
async function copyAssets() {
    console.log('📁 Copying assets...');
    
    // Create assets directory in output
    const outputAssetsDir = path.join(CONFIG.outputDir, 'assets');
    await fs.ensureDir(outputAssetsDir);
    
    // Copy CSS files
    const cssFiles = ['home.css', 'docs.css'];
    for (const cssFile of cssFiles) {
        const srcPath = path.join(CONFIG.assetsDir, 'css', cssFile);
        const destPath = path.join(CONFIG.outputDir, cssFile);
        if (await fs.pathExists(srcPath)) {
            await fs.copy(srcPath, destPath);
        }
    }
    
    // Copy images
    const imagesDir = path.join(CONFIG.assetsDir, 'images');
    if (await fs.pathExists(imagesDir)) {
        const images = await fs.readdir(imagesDir);
        for (const image of images) {
            if (image.endsWith('.png') || image.endsWith('.jpg') || image.endsWith('.svg')) {
                const srcPath = path.join(imagesDir, image);
                const destPath = path.join(CONFIG.outputDir, image);
                await fs.copy(srcPath, destPath);
            }
        }
    }
    
    // Copy icons
    const iconsDir = path.join(CONFIG.assetsDir, 'icons');
    if (await fs.pathExists(iconsDir)) {
        const icons = await fs.readdir(iconsDir);
        for (const icon of icons) {
            if (icon.endsWith('.ico') || icon.endsWith('.png') || icon.endsWith('.json')) {
                const srcPath = path.join(iconsDir, icon);
                const destPath = path.join(CONFIG.outputDir, icon);
                await fs.copy(srcPath, destPath);
            }
        }
    }
    
    console.log('✅ Assets copied successfully');
}

/**
 * Generate home page
 */
async function generateHomePage() {
    console.log('🏠 Generating home page...');
    
    const template = await fs.readFile(CONFIG.homeTemplate, 'utf8');
    
    // For home page, replace placeholders and fix asset paths for GitHub Pages
    const html = template
        .replace(/{{TITLE}}/g, CONFIG.title)
        .replace(/{{DESCRIPTION}}/g, CONFIG.description)
        .replace(/href="\.\/([^"]+)"/g, 'href="./$1"')  // Keep relative paths as-is
        .replace(/src="\.\/([^"]+)"/g, 'src="./$1"');   // Keep relative paths as-is
    
    const outputFile = path.join(CONFIG.outputDir, 'index.html');
    await fs.writeFile(outputFile, html, 'utf8');
    
    console.log('✅ Home page generated');
}

/**
 * Generate documentation overview page
 */
async function generateDocsOverview() {
    console.log('📚 Generating docs overview...');
    
    // Create overview content from README
    const readmeContent = await fs.readFile(CONFIG.readmeFile, 'utf8');
    const template = await fs.readFile(CONFIG.docsTemplate, 'utf8');
    
    // Generate table of contents
    const headings = generateTableOfContents(readmeContent);
    const tocHtml = generateNavigation(headings);
    
    // Convert markdown to HTML
    const contentHtml = processMarkdown(readmeContent);
    
    // Add documentation links section
    const docsLinksHtml = `
        <section class="docs-links" style="margin-top: 2rem; padding: 1.5rem; background: var(--color-surface); border-radius: var(--radius-md); border: 1px solid var(--color-border);">
            <h2>📚 Documentation Sections</h2>
            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; margin-top: 1rem;">
                ${DOCS_STRUCTURE.map(doc => `
                    <a href="${doc.path}" style="display: block; padding: 1rem; background: white; border: 1px solid var(--color-border); border-radius: var(--radius-sm); text-decoration: none; transition: all 0.2s ease;">
                        <h3 style="margin: 0 0 0.5rem 0; color: var(--color-primary); font-size: 1rem;">${doc.title}</h3>
                        <p style="margin: 0; color: var(--color-text-secondary); font-size: 0.875rem; line-height: 1.4;">${doc.description}</p>
                    </a>
                `).join('')}
            </div>
        </section>
    `;
    
    const finalContent = contentHtml + docsLinksHtml;
    
    // Generate sidebar navigation for docs root
    const sidebarNav = generateSidebarNavigation('/docs');
    
    // Replace template placeholders and fix paths for docs root (one level deep)
    const html = template
        .replace(/{{TITLE}}/g, 'Overview')
        .replace(/{{DESCRIPTION}}/g, CONFIG.description)
        .replace(/{{TABLE_OF_CONTENTS}}/g, tocHtml)
        .replace(/{{CONTENT}}/g, finalContent)
        .replace(/{{SIDEBAR_NAVIGATION}}/g, sidebarNav)
        .replace(/{{SOURCE_FILE}}/g, 'README.md')
        .replace(/{{#BREADCRUMB}}.*?{{\/BREADCRUMB}}/gs, '')
        .replace(/{{#PREV_PAGE}}.*?{{\/PREV_PAGE}}/gs, '')
        .replace(/{{#NEXT_PAGE}}.*?{{\/NEXT_PAGE}}/gs, '')
        .replace(/href="\.\.\/([^"]+)"/g, 'href="../$1"')  // Fix relative paths for docs root
        .replace(/src="\.\.\/([^"]+)"/g, 'src="../$1"');   // Fix relative paths for docs root
    
    // Create docs directory and write overview
    const docsOutputDir = path.join(CONFIG.outputDir, 'docs');
    await fs.ensureDir(docsOutputDir);
    
    const outputFile = path.join(docsOutputDir, 'index.html');
    await fs.writeFile(outputFile, html, 'utf8');
    
    console.log('✅ Docs overview generated');
}

/**
 * Generate individual documentation pages
 */
async function generateDocPages() {
    console.log('📄 Generating documentation pages...');
    
    const template = await fs.readFile(CONFIG.docsTemplate, 'utf8');
    const docsOutputDir = path.join(CONFIG.outputDir, 'docs');
    await fs.ensureDir(docsOutputDir);
    
    for (let i = 0; i < DOCS_STRUCTURE.length; i++) {
        const doc = DOCS_STRUCTURE[i];
        const docFile = path.join(CONFIG.docsDir, doc.file);
        
        if (!(await fs.pathExists(docFile))) {
            console.log(`⚠️  Warning: ${doc.file} not found, skipping...`);
            continue;
        }
        
        const content = await fs.readFile(docFile, 'utf8');
        
        // Generate table of contents
        const headings = generateTableOfContents(content);
        const tocHtml = generateNavigation(headings);
        
        // Convert markdown to HTML
        const contentHtml = processMarkdown(content);
        
        // Navigation (prev/next)
        const prevPage = i > 0 ? DOCS_STRUCTURE[i - 1] : null;
        const nextPage = i < DOCS_STRUCTURE.length - 1 ? DOCS_STRUCTURE[i + 1] : null;
        
        let prevPageHtml = '';
        let nextPageHtml = '';
        
        if (prevPage) {
            prevPageHtml = `
                <a href="${prevPage.path}" class="footer-nav-link footer-nav-prev">
                    <svg class="footer-nav-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
                        <path d="M10 12L6 8L10 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
                    </svg>
                    <div>
                        <div class="footer-nav-label">Previous</div>
                        <div class="footer-nav-title">${prevPage.title}</div>
                    </div>
                </a>
            `;
        }
        
        if (nextPage) {
            nextPageHtml = `
                <a href="${nextPage.path}" class="footer-nav-link footer-nav-next">
                    <div>
                        <div class="footer-nav-label">Next</div>
                        <div class="footer-nav-title">${nextPage.title}</div>
                    </div>
                    <svg class="footer-nav-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
                        <path d="M6 12L10 8L6 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
                    </svg>
                </a>
            `;
        }
        
        // Generate sidebar navigation for subdoc pages
        const sidebarNav = generateSidebarNavigation(doc.path);
        
        // Replace template placeholders and fix paths for subdoc pages (two levels deep)
        let html = template
            .replace(/{{TITLE}}/g, doc.title)
            .replace(/{{DESCRIPTION}}/g, doc.description)
            .replace(/{{TABLE_OF_CONTENTS}}/g, tocHtml)
            .replace(/{{CONTENT}}/g, contentHtml)
            .replace(/{{SIDEBAR_NAVIGATION}}/g, sidebarNav)
            .replace(/{{SOURCE_FILE}}/g, `docs/${doc.file}`)
            .replace(/{{#BREADCRUMB}}(.*?){{\/BREADCRUMB}}/gs, `<span class="breadcrumb-separator">/</span><span class="breadcrumb-current">${doc.title}</span>`)
            .replace(/{{#PREV_PAGE}}.*?{{\/PREV_PAGE}}/gs, prevPageHtml)
            .replace(/{{#NEXT_PAGE}}.*?{{\/NEXT_PAGE}}/gs, nextPageHtml)
            .replace(/href="NAVLINK:([^"]+)"/g, 'href="NAV_FINAL:$1"')  // Mark navigation links to protect them
            .replace(/href="\.\.\/([^"]+)"/g, 'href="../../$1"')  // Fix relative paths for sub-docs (two levels up)
            .replace(/href="NAV_FINAL:([^"]+)"/g, 'href="../$1/"')  // Restore navigation links AFTER general replacement
            .replace(/src="\.\.\/([^"]+)"/g, 'src="../../$1"');   // Fix relative paths for sub-docs (two levels up)
        
        // Create subdirectory for clean URLs
        const pagePath = doc.path.replace('/docs/', '');
        const pageDir = path.join(docsOutputDir, pagePath);
        await fs.ensureDir(pageDir);
        
        const outputFile = path.join(pageDir, 'index.html');
        await fs.writeFile(outputFile, html, 'utf8');
        
        console.log(`  ✅ Generated ${doc.title}`);
    }
    
    console.log('✅ All documentation pages generated');
}

/**
 * Main build function
 */
async function build() {
    try {
        console.log('🚀 Building Velocity website...');
        
        // Ensure output directory exists
        await fs.ensureDir(CONFIG.outputDir);
        
        // Clean previous build
        await fs.emptyDir(CONFIG.outputDir);
        
        // Copy assets first
        await copyAssets();
        
        // Generate pages
        await generateHomePage();
        await generateDocsOverview();
        await generateDocPages();
        
        // Generate stats
        const files = await fs.readdir(CONFIG.outputDir, { recursive: true });
        const totalFiles = files.filter(f => f.endsWith('.html')).length;
        
        console.log('✅ Website built successfully!');
        console.log(`📁 Output directory: ${CONFIG.outputDir}`);
        console.log(`📊 Generated ${totalFiles} HTML pages`);
        console.log(`🌐 Home: file://${path.join(CONFIG.outputDir, 'index.html')}`);
        console.log(`📚 Docs: file://${path.join(CONFIG.outputDir, 'docs', 'index.html')}`);
        
    } catch (error) {
        console.error('❌ Build failed:', error.message);
        if (process.env.NODE_ENV === 'development') {
            console.error(error.stack);
        }
        process.exit(1);
    }
}

// Run build if this script is executed directly
if (require.main === module) {
    build();
}

module.exports = { build, CONFIG, DOCS_STRUCTURE };