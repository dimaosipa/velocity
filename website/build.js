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

/**
 * Parse frontmatter from markdown content
 */
function parseFrontmatter(content) {
    const frontmatterRegex = /^---\r?\n(.*?)\r?\n---\r?\n/s;
    const match = content.match(frontmatterRegex);
    
    if (!match) {
        return { frontmatter: {}, content: content };
    }
    
    const frontmatterText = match[1];
    const remainingContent = content.substring(match[0].length);
    
    // Simple YAML-like parsing for basic fields
    const frontmatter = {};
    const lines = frontmatterText.split('\n');
    
    for (const line of lines) {
        const colonIndex = line.indexOf(':');
        if (colonIndex > 0) {
            const key = line.substring(0, colonIndex).trim();
            const value = line.substring(colonIndex + 1).trim().replace(/^["']|["']$/g, '');
            frontmatter[key] = value;
        }
    }
    
    return { frontmatter, content: remainingContent };
}

/**
 * Parse footer configuration from FOOTER.md
 */
async function parseFooterConfig() {
    const footerPath = path.join(CONFIG.docsDir, '..', 'FOOTER.md');
    
    try {
        if (!(await fs.pathExists(footerPath))) {
            console.log('ℹ️  No FOOTER.md found, using default footer structure');
            return {};
        }
        
        const content = await fs.readFile(footerPath, 'utf8');
        const { frontmatter, content: markdownContent } = parseFrontmatter(content);
        
        // Parse markdown sections into footer structure
        const sections = {};
        const lines = markdownContent.split('\n');
        let currentSection = null;
        
        for (const line of lines) {
            const trimmed = line.trim();
            
            // Check for section headers (## Section Name)
            if (trimmed.startsWith('## ')) {
                currentSection = trimmed.substring(3).trim();
                sections[currentSection] = [];
            }
            // Check for list items (- [Title](url) - description)
            else if (trimmed.startsWith('- [') && currentSection) {
                const linkMatch = trimmed.match(/- \[([^\]]+)\]\(([^)]+)\)(?:\s*-\s*(.+))?/);
                if (linkMatch) {
                    sections[currentSection].push({
                        title: linkMatch[1],
                        url: linkMatch[2],
                        description: linkMatch[3] || ''
                    });
                }
            }
        }
        
        console.log(`📄 Parsed footer configuration with ${Object.keys(sections).length} sections`);
        return sections;
        
    } catch (error) {
        console.warn('⚠️  Could not parse FOOTER.md, using default footer structure');
        return {};
    }
}

/**
 * Auto-discover documentation structure from docs/ directory
 */
async function discoverDocsStructure() {
    const docsFiles = [];
    
    try {
        const files = await fs.readdir(CONFIG.docsDir);
        
        for (const file of files) {
            if (!file.endsWith('.md')) continue;
            
            const filePath = path.join(CONFIG.docsDir, file);
            const stat = await fs.stat(filePath);
            
            if (stat.isFile()) {
                const content = await fs.readFile(filePath, 'utf8');
                const { frontmatter } = parseFrontmatter(content);
                
                // Generate title from filename if not in frontmatter
                const defaultTitle = file
                    .replace('.md', '')
                    .split('-')
                    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
                    .join(' ');
                
                const docInfo = {
                    file: file,
                    title: frontmatter.title || defaultTitle,
                    description: frontmatter.description || `${defaultTitle} documentation`,
                    order: parseInt(frontmatter.order) || 999,
                    category: frontmatter.category || 'Other',
                    path: `/docs/${file.replace('.md', '')}`,
                    hidden: frontmatter.hidden === 'true'
                };
                
                // Skip hidden files
                if (!docInfo.hidden) {
                    docsFiles.push(docInfo);
                }
            }
        }
        
        // Sort by order, then by title
        docsFiles.sort((a, b) => {
            if (a.order !== b.order) {
                return a.order - b.order;
            }
            return a.title.localeCompare(b.title);
        });
        
        console.log(`📋 Discovered ${docsFiles.length} documentation files`);
        return docsFiles;
        
    } catch (error) {
        console.warn('⚠️  Could not read docs directory, using empty structure');
        return [];
    }
}

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
 * Generate sidebar navigation based on page depth and discovered docs
 */
function generateSidebarNavigation(currentPagePath, docsStructure) {
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
    
    // Group docs by category
    const categories = {};
    docsStructure.forEach(doc => {
        const category = doc.category;
        if (!categories[category]) {
            categories[category] = [];
        }
        categories[category].push(doc);
    });
    
    // Generate navigation sections
    let navigation = `
        <div class="nav-section">
            <h4 class="nav-section-title">Overview</h4>
            <ul class="nav-list">
                <li><a href="${overviewHref}" class="nav-item">Overview</a></li>
            </ul>
        </div>
    `;
    
    // Add sections for each category
    Object.keys(categories).sort().forEach(category => {
        if (categories[category].length === 0) return;
        
        navigation += `
        <div class="nav-section">
            <h4 class="nav-section-title">${category}</h4>
            <ul class="nav-list">`;
        
        categories[category].forEach(doc => {
            const slug = doc.file.replace('.md', '');
            const href = itemHref(slug);
            navigation += `
                <li><a href="${href}" class="nav-item">${doc.title}</a></li>`;
        });
        
        navigation += `
            </ul>
        </div>`;
    });
    
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
 * Generate dynamic footer HTML from FOOTER.md configuration
 */
function generateDynamicFooter(footerConfig, pageDepth = 0) {
    if (Object.keys(footerConfig).length === 0) {
        // Fallback to current hardcoded structure if no FOOTER.md
        return '';
    }
    
    // Determine path prefix based on page depth:
    // 0 = home page (./)
    // 1 = docs root (../)  
    // 2 = docs subdirectory (../../)
    const pathPrefix = pageDepth === 0 ? './' : '../'.repeat(pageDepth);
    
    let footerHtml = '';
    
    Object.keys(footerConfig).forEach(sectionName => {
        const links = footerConfig[sectionName];
        if (links.length === 0) return;
        
        footerHtml += `
                    <div class="footer-section">
                        <h4 class="footer-section-title">${sectionName}</h4>`;
        
        links.forEach(link => {
            // Adjust relative paths for different page depths
            let linkUrl = link.url;
            if (linkUrl.startsWith('./') && pageDepth > 0) {
                linkUrl = linkUrl.replace('./', pathPrefix);
            }
            
            footerHtml += `
                        <a href="${linkUrl}" class="footer-link"${link.url.startsWith('http') ? ' target="_blank"' : ''}>${link.title}</a>`;
        });
        
        footerHtml += `
                    </div>`;
    });
    
    return footerHtml;
}

/**
 * Generate home page
 */
async function generateHomePage() {
    console.log('🏠 Generating home page...');
    
    const template = await fs.readFile(CONFIG.homeTemplate, 'utf8');
    const footerConfig = await parseFooterConfig();
    
    // Generate dynamic footer if available
    const dynamicFooter = generateDynamicFooter(footerConfig, 0);
    
    // For home page, replace placeholders and fix asset paths for GitHub Pages
    let html = template
        .replace(/{{TITLE}}/g, CONFIG.title)
        .replace(/{{DESCRIPTION}}/g, CONFIG.description)
        .replace(/href="\.\/([^"]+)"/g, 'href="./$1"')  // Keep relative paths as-is
        .replace(/src="\.\/([^"]+)"/g, 'src="./$1"');   // Keep relative paths as-is
    
    // Replace footer links if dynamic footer is available
    if (dynamicFooter) {
        html = html.replace(
            /<div class="footer-links"[\s\S]*?<\/div>\s*<\/div>/,
            `<div class="footer-links">${dynamicFooter}
                </div>
            </div>`
        );
    }
    
    const outputFile = path.join(CONFIG.outputDir, 'index.html');
    await fs.writeFile(outputFile, html, 'utf8');
    
    console.log('✅ Home page generated');
}

/**
 * Generate documentation overview page
 */
async function generateDocsOverview(docsStructure) {
    console.log('📚 Generating docs overview...');
    
    // Create overview content from README
    const readmeContent = await fs.readFile(CONFIG.readmeFile, 'utf8');
    const template = await fs.readFile(CONFIG.docsTemplate, 'utf8');
    const footerConfig = await parseFooterConfig();
    
    // Generate table of contents
    const headings = generateTableOfContents(readmeContent);
    const tocHtml = generateNavigation(headings);
    
    // Convert markdown to HTML
    const contentHtml = processMarkdown(readmeContent);
    
    // Add documentation links section using discovered structure
    const docsLinksHtml = docsStructure.length > 0 ? `
        <section class="docs-links" style="margin-top: 2rem; padding: 1.5rem; background: var(--color-surface); border-radius: var(--radius-md); border: 1px solid var(--color-border);">
            <h2>📚 Documentation Sections</h2>
            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; margin-top: 1rem;">
                ${docsStructure.map(doc => `
                    <a href="${doc.path}" style="display: block; padding: 1rem; background: white; border: 1px solid var(--color-border); border-radius: var(--radius-sm); text-decoration: none; transition: all 0.2s ease;">
                        <h3 style="margin: 0 0 0.5rem 0; color: var(--color-primary); font-size: 1rem;">${doc.title}</h3>
                        <p style="margin: 0; color: var(--color-text-secondary); font-size: 0.875rem; line-height: 1.4;">${doc.description}</p>
                    </a>
                `).join('')}
            </div>
        </section>
    ` : '';
    
    const finalContent = contentHtml + docsLinksHtml;
    
    // Generate sidebar navigation for docs root
    const sidebarNav = generateSidebarNavigation('/docs', docsStructure);
    
    // Generate dynamic footer for docs page
    const dynamicFooter = generateDynamicFooter(footerConfig, 1);
    
    // Replace template placeholders and fix paths for docs root (one level deep)
    let html = template
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
    
    // Replace footer links if dynamic footer is available
    if (dynamicFooter) {
        html = html.replace(
            /<div class="footer-links"[\s\S]*?<\/div>\s*<\/div>/,
            `<div class="footer-links">${dynamicFooter}
                </div>
            </div>`
        );
    }
    
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
async function generateDocPages(docsStructure) {
    console.log('📄 Generating documentation pages...');
    
    const template = await fs.readFile(CONFIG.docsTemplate, 'utf8');
    const footerConfig = await parseFooterConfig();
    const docsOutputDir = path.join(CONFIG.outputDir, 'docs');
    await fs.ensureDir(docsOutputDir);
    
    for (let i = 0; i < docsStructure.length; i++) {
        const doc = docsStructure[i];
        const docFile = path.join(CONFIG.docsDir, doc.file);
        
        if (!(await fs.pathExists(docFile))) {
            console.log(`⚠️  Warning: ${doc.file} not found, skipping...`);
            continue;
        }
        
        const rawContent = await fs.readFile(docFile, 'utf8');
        const { frontmatter, content } = parseFrontmatter(rawContent);
        
        // Generate table of contents
        const headings = generateTableOfContents(content);
        const tocHtml = generateNavigation(headings);
        
        // Convert markdown to HTML
        const contentHtml = processMarkdown(content);
        
        // Navigation (prev/next)
        const prevPage = i > 0 ? docsStructure[i - 1] : null;
        const nextPage = i < docsStructure.length - 1 ? docsStructure[i + 1] : null;
        
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
        const sidebarNav = generateSidebarNavigation(doc.path, docsStructure);
        
        // Generate dynamic footer for subdoc pages  
        const dynamicFooter = generateDynamicFooter(footerConfig, 2);
        
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
        
        // Replace footer links if dynamic footer is available
        if (dynamicFooter) {
            html = html.replace(
                /<div class="footer-links"[\s\S]*?<\/div>\s*<\/div>/,
                `<div class="footer-links">${dynamicFooter}
                </div>
            </div>`
            );
        }
        
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
        
        // Discover documentation structure
        const docsStructure = await discoverDocsStructure();
        
        // Generate pages
        await generateHomePage();
        await generateDocsOverview(docsStructure);
        await generateDocPages(docsStructure);
        
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

module.exports = { build, CONFIG, discoverDocsStructure };