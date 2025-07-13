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
    baseUrl: process.env.GITHUB_PAGES_URL || 'https://dimaosipa.github.io/velocity',
    
    // Default fallback content
    defaultHeroContent: {
        badge_icon: '⚠️',
        badge_text: 'Experimental Software - Use with caution',
        hero_title: 'Velocity: The Fastest<br>Package Manager for<br><span class="hero-title-accent">Apple Silicon</span>',
        hero_subtitle: 'Native speed. Modern architecture. Zero sudo required.',
        cta_primary_text: 'Get Started',
        cta_primary_url: './docs/installation',
        cta_secondary_text: 'View on GitHub',
        cta_secondary_url: 'https://github.com/dimaosipa/velocity',
        cta_note: '<strong>Note:</strong> Velocity is experimental software. Please test thoroughly before using in production environments.'
    }
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
    let currentKey = null;
    let multilineValue = [];
    let isMultiline = false;
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const colonIndex = line.indexOf(':');
        
        if (colonIndex > 0 && !isMultiline) {
            // Save previous multiline value if exists
            if (currentKey && multilineValue.length > 0) {
                frontmatter[currentKey] = multilineValue.join('\n').trim();
                multilineValue = [];
            }
            
            const key = line.substring(0, colonIndex).trim();
            const value = line.substring(colonIndex + 1).trim();
            
            // Check for multiline indicator |
            if (value === '|') {
                currentKey = key;
                isMultiline = true;
                multilineValue = [];
            } else {
                // Regular single-line value
                frontmatter[key] = value.replace(/^["']|["']$/g, '');
                currentKey = null;
            }
        } else if (isMultiline && line.trim()) {
            // Collect multiline content (skip empty lines)
            const content = line.replace(/^  /, ''); // Remove 2-space indentation
            if (content.trim()) {
                multilineValue.push(content);
            }
        } else if (isMultiline && !line.trim() && i < lines.length - 1) {
            // Empty line in multiline - check if next line is indented
            const nextLine = lines[i + 1];
            if (nextLine && !nextLine.startsWith('  ') && nextLine.includes(':')) {
                // End of multiline block
                if (currentKey && multilineValue.length > 0) {
                    frontmatter[currentKey] = multilineValue.join('\n').trim();
                }
                currentKey = null;
                multilineValue = [];
                isMultiline = false;
            }
        }
    }
    
    // Save final multiline value if exists
    if (currentKey && multilineValue.length > 0) {
        frontmatter[currentKey] = multilineValue.join('\n').trim();
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
 * Parse header configuration from HEADER.md
 */
async function parseHeaderConfig() {
    const headerPath = path.join(CONFIG.docsDir, '..', 'HEADER.md');
    
    try {
        if (!(await fs.pathExists(headerPath))) {
            console.log('ℹ️  No HEADER.md found, using default header structure');
            return {};
        }
        
        const content = await fs.readFile(headerPath, 'utf8');
        const { frontmatter, content: markdownContent } = parseFrontmatter(content);
        
        // Parse markdown sections into header structure
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
        
        console.log(`📄 Parsed header configuration with ${Object.keys(sections).length} sections`);
        return sections;
        
    } catch (error) {
        console.warn('⚠️  Could not parse HEADER.md, using default header structure');
        return {};
    }
}

/**
 * Parse home page configuration from HOME.md
 */
async function parseHomeConfig() {
    const homePath = path.join(CONFIG.docsDir, '..', 'HOME.md');
    
    try {
        if (!(await fs.pathExists(homePath))) {
            console.log('ℹ️  No HOME.md found, using hardcoded home page content');
            return null;
        }
        
        const content = await fs.readFile(homePath, 'utf8');
        const { frontmatter, content: markdownContent } = parseFrontmatter(content);
        
        // Parse markdown sections dynamically - keep them in order
        const sections = [];
        const lines = markdownContent.split('\n');
        let currentSection = null;
        let currentContent = [];
        
        for (const line of lines) {
            const trimmed = line.trim();
            
            // Check for main section headers (## Section Name)
            if (trimmed.startsWith('## ')) {
                // Save previous section if exists
                if (currentSection && currentContent.length > 0) {
                    sections.push({
                        title: currentSection,
                        subtitle: null,
                        raw: currentContent.join('\n').trim(),
                        html: md.render(currentContent.join('\n').trim())
                    });
                }
                
                const sectionMatch = trimmed.match(/^## (.+?)(?:\s*\|\s*(.+))?$/);
                currentSection = sectionMatch[1].trim();
                const subtitle = sectionMatch[2] ? sectionMatch[2].trim() : null;
                
                currentContent = [];
            }
            // Content lines (everything after ## headers)
            else if (currentSection) {
                currentContent.push(line);
            }
        }
        
        // Save final section
        if (currentSection && currentContent.length > 0) {
            sections.push({
                title: currentSection,
                subtitle: null,
                raw: currentContent.join('\n').trim(),
                html: md.render(currentContent.join('\n').trim())
            });
        }
        
        console.log(`🏠 Parsed home page configuration with ${sections.length} sections: ${sections.map(s => s.title).join(', ')}`);
        return { frontmatter, sections };
        
    } catch (error) {
        console.warn('⚠️  Could not parse HOME.md, using hardcoded home page content');
        return null;
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
                const defaultTitle = utils.parseTitle(file);
                
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

// Utility functions
const utils = {
    /**
     * Generate slug from text
     */
    generateSlug(text) {
        return text
            .toLowerCase()
            .replace(/[^\w\s-]/g, '')
            .replace(/\s+/g, '-')
            .trim();
    },

    /**
     * Parse title from filename
     */
    parseTitle(filename) {
        return filename
            .replace('.md', '')
            .split('-')
            .map(word => word.charAt(0).toUpperCase() + word.slice(1))
            .join(' ');
    },

    /**
     * Generate path prefix for different page depths
     */
    getPathPrefix(pageDepth) {
        return pageDepth === 0 ? './' : '../'.repeat(pageDepth);
    },

    /**
     * Apply template replacements
     */
    applyTemplateReplacements(template, replacements) {
        let result = template;
        for (const [key, value] of Object.entries(replacements)) {
            result = result.replace(new RegExp(`{{${key}}}`, 'g'), value || '');
        }
        return result;
    },

    /**
     * Fix relative paths for different page depths
     */
    fixRelativePaths(html, pageDepth) {
        if (pageDepth === 0) return html;
        
        const pathPrefix = '../'.repeat(pageDepth);
        return html
            .replace(/href="\.\.\/([^"]+)"/g, `href="${pathPrefix}$1"`)
            .replace(/src="\.\.\/([^"]+)"/g, `src="${pathPrefix}$1"`);
    }
};

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
                const slug = utils.generateSlug(text);
                
                headings.push({ level, text, slug });
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
 * Generate sidebar navigation based on page depth and discovered docs
 */
function generateSidebarNavigation(currentPagePath, docsStructure) {
    const isRootDocs = currentPagePath === '/docs';
    
    let overviewHref, itemHref;
    
    if (isRootDocs) {
        // From /docs/ page - use absolute paths to avoid relative path resolution issues
        overviewHref = '/docs/';
        itemHref = (path) => `/docs/${path}/`;
    } else {
        // From /docs/subpage/ page - calculate proper relative paths
        overviewHref = '../';
        itemHref = (path) => {
            const currentPage = currentPagePath.replace('/docs/', '');
            return path === currentPage ? './' : `NAVLINK:${path}`;
        };
    }
    
    // Generate simple navigation list
    let navigation = `
        <div class="nav-section">
            <ul class="nav-list">
                <li><a href="${overviewHref}" class="nav-item">Overview</a></li>`;
    
    // Add all docs as a simple list
    docsStructure.forEach(doc => {
        const slug = doc.file.replace('.md', '');
        const href = itemHref(slug);
        navigation += `
                <li><a href="${href}" class="nav-item">${doc.title}</a></li>`;
    });
    
    navigation += `
            </ul>
        </div>`;
    
    return navigation;
}

/**
 * Content generators
 */
const generators = {
    /**
     * Generate dynamic sections from all H2 sections in markdown
     * Each section gets alternating background colors
     */
    dynamicSections(sections) {
        if (!sections || sections.length === 0) {
            return '';
        }
        
        let sectionsHtml = '';
        
        sections.forEach((section, index) => {
            if (!section.html) return; // Skip sections without content
            
            // Alternate between light and dark backgrounds
            const isEven = index % 2 === 0;
            const sectionClass = isEven ? 'section-light' : 'section-dark';
            const sectionId = section.title.toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
            
            sectionsHtml += `
    <!-- ${section.title} Section -->
    <section class="content-section ${sectionClass}" id="${sectionId}">
        <div class="section-container">
            <div class="section-header">
                <h2 class="section-title">${section.title}</h2>
                ${section.subtitle ? `<p class="section-subtitle">${section.subtitle}</p>` : ''}
            </div>
            
            <div class="section-content">
                ${section.html}
            </div>
        </div>
    </section>`;
        });
        
        return sectionsHtml;
    },

    /**
     * Generate dynamic footer HTML from FOOTER.md configuration
     */
    dynamicFooter(footerConfig, pageDepth = 0) {
        if (Object.keys(footerConfig).length === 0) {
            return '';
        }
        
        const pathPrefix = utils.getPathPrefix(pageDepth);
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
    },

    /**
     * Generate dynamic header navigation HTML from HEADER.md configuration
     */
    dynamicHeader(headerConfig, pageDepth = 0) {
        if (Object.keys(headerConfig).length === 0) {
            return '';
        }
        
        const pathPrefix = utils.getPathPrefix(pageDepth);
        let headerHtml = '';
        
        Object.keys(headerConfig).forEach(sectionName => {
            const links = headerConfig[sectionName];
            if (links.length === 0) return;
            
            links.forEach(link => {
                // Adjust relative paths for different page depths
                let linkUrl = link.url;
                if (linkUrl.startsWith('./') && pageDepth > 0) {
                    linkUrl = linkUrl.replace('./', pathPrefix);
                }
                
                const isExternal = link.url.startsWith('http');
                const externalClass = isExternal ? ' nav-link-external' : '';
                
                headerHtml += `
                <a href="${linkUrl}" class="nav-link${externalClass}"${isExternal ? ' target="_blank"' : ''}>${link.title}</a>`;
            });
        });
        
        return headerHtml;
    }
};

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
 * Generate documentation overview page
 */
async function generateDocsOverview(docsStructure) {
    console.log('📚 Generating docs overview...');
    
    // Create overview content from README
    const readmeContent = await fs.readFile(CONFIG.readmeFile, 'utf8');
    const template = await fs.readFile(CONFIG.docsTemplate, 'utf8');
    const footerConfig = await parseFooterConfig();
    const headerConfig = await parseHeaderConfig();
    
    // Generate table of contents
    const headings = generateTableOfContents(readmeContent);
    const tocHtml = generateNavigation(headings);
    
    // Convert markdown to HTML
    const contentHtml = processMarkdown(readmeContent);
    
    // Generate sidebar navigation for docs root
    const sidebarNav = generateSidebarNavigation('/docs', docsStructure);
    
    // Generate dynamic footer and header for docs page
    const dynamicFooter = generators.dynamicFooter(footerConfig, 1);
    const dynamicHeader = generators.dynamicHeader(headerConfig, 1);
    
    // Apply template replacements
    const replacements = {
        TITLE: 'Overview',
        DESCRIPTION: CONFIG.description,
        TABLE_OF_CONTENTS: tocHtml,
        CONTENT: contentHtml,
        SIDEBAR_NAVIGATION: sidebarNav,
        SOURCE_FILE: 'README.md'
    };
    
    let html = utils.applyTemplateReplacements(template, replacements);
    
    // Handle conditional template blocks
    html = html.replace(/{{#BREADCRUMB}}.*?{{\/BREADCRUMB}}/gs, ''); // Remove breadcrumb for overview
    html = html.replace(/{{#PREV_PAGE}}.*?{{\/PREV_PAGE}}/gs, ''); // Remove prev page
    html = html.replace(/{{#NEXT_PAGE}}.*?{{\/NEXT_PAGE}}/gs, ''); // Remove next page
    
    html = utils.fixRelativePaths(html, 1);
    
    // Replace header navigation if dynamic header is available
    if (dynamicHeader) {
        html = html.replace(
            /<div class="nav-links"[\s\S]*?<\/div>/,
            `<div class="nav-links">${dynamicHeader}
            </div>`
        );
    }
    
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
    const headerConfig = await parseHeaderConfig();
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
        
        const prevPageHtml = prevPage ? generateNavLink(prevPage, 'Previous', 'prev') : '';
        const nextPageHtml = nextPage ? generateNavLink(nextPage, 'Next', 'next') : '';
        
        // Generate sidebar navigation for subdoc pages
        const sidebarNav = generateSidebarNavigation(doc.path, docsStructure);
        
        // Generate dynamic footer and header for subdoc pages  
        const dynamicFooter = generators.dynamicFooter(footerConfig, 2);
        const dynamicHeader = generators.dynamicHeader(headerConfig, 2);
        
        // Apply template replacements
        const replacements = {
            TITLE: doc.title,
            DESCRIPTION: doc.description,
            TABLE_OF_CONTENTS: tocHtml,
            CONTENT: contentHtml,
            SIDEBAR_NAVIGATION: sidebarNav,
            SOURCE_FILE: `docs/${doc.file}`
        };
        
        let html = utils.applyTemplateReplacements(template, replacements);
        
        // Handle conditional template blocks
        html = html.replace(/{{#BREADCRUMB}}.*?{{\/BREADCRUMB}}/gs, `<span class="breadcrumb-separator">/</span><span class="breadcrumb-current">${doc.title}</span>`);
        html = html.replace(/{{#PREV_PAGE}}.*?{{\/PREV_PAGE}}/gs, prevPageHtml);
        html = html.replace(/{{#NEXT_PAGE}}.*?{{\/NEXT_PAGE}}/gs, nextPageHtml);
        
        html = processDocPagePaths(html);
        
        // Replace header navigation if dynamic header is available
        if (dynamicHeader) {
            html = html.replace(
                /<div class="nav-links"[\s\S]*?<\/div>/,
                `<div class="nav-links">${dynamicHeader}
                </div>`
            );
        }
        
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
 * Generate navigation link for prev/next pages
 */
function generateNavLink(page, label, direction) {
    const iconPath = direction === 'prev' ? 'M10 12L6 8L10 4' : 'M6 12L10 8L6 4';
    const linkClass = `footer-nav-link footer-nav-${direction}`;
    
    return `
        <a href="${page.path}" class="${linkClass}">
            ${direction === 'prev' ? `<svg class="footer-nav-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
                <path d="${iconPath}" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>` : ''}
            <div>
                <div class="footer-nav-label">${label}</div>
                <div class="footer-nav-title">${page.title}</div>
            </div>
            ${direction === 'next' ? `<svg class="footer-nav-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
                <path d="${iconPath}" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>` : ''}
        </a>
    `;
}

/**
 * Process doc page paths for navigation
 */
function processDocPagePaths(html) {
    return html
        .replace(/href="NAVLINK:([^"]+)"/g, 'href="NAV_FINAL:$1"')  // Mark navigation links to protect them
        .replace(/href="\.\.\/([^"]+)"/g, 'href="../../$1"')  // Fix relative paths for sub-docs (two levels up)
        .replace(/href="NAV_FINAL:([^"]+)"/g, 'href="../$1/"')  // Restore navigation links AFTER general replacement
        .replace(/src="\.\.\/([^"]+)"/g, 'src="../../$1"');   // Fix relative paths for sub-docs (two levels up)
}

/**
 * Generate home page
 */
async function generateHomePage() {
    console.log('🏠 Generating home page...');
    
    const template = await fs.readFile(CONFIG.homeTemplate, 'utf8');
    const footerConfig = await parseFooterConfig();
    const headerConfig = await parseHeaderConfig();
    const homeConfig = await parseHomeConfig();
    
    // Prepare content data
    const contentData = prepareHomePageContent(homeConfig);
    
    // Generate dynamic footer and header
    const dynamicFooter = generators.dynamicFooter(footerConfig, 0);
    const dynamicHeader = generators.dynamicHeader(headerConfig, 0);
    
    // Apply template replacements
    const replacements = {
        TITLE: contentData.title,
        DESCRIPTION: contentData.description,
        KEYWORDS: contentData.keywords,
        BADGE_ICON: contentData.heroContent.badge_icon,
        BADGE_TEXT: contentData.heroContent.badge_text,
        HERO_TITLE: contentData.heroContent.hero_title,
        HERO_SUBTITLE: contentData.heroContent.hero_subtitle,
        CTA_PRIMARY_TEXT: contentData.heroContent.cta_primary_text,
        CTA_PRIMARY_URL: contentData.heroContent.cta_primary_url,
        CTA_SECONDARY_TEXT: contentData.heroContent.cta_secondary_text,
        CTA_SECONDARY_URL: contentData.heroContent.cta_secondary_url,
        CTA_NOTE: contentData.heroContent.cta_note,
        DYNAMIC_SECTIONS: contentData.dynamicSections
    };
    
    let html = utils.applyTemplateReplacements(template, replacements);
    
    // Replace header navigation if dynamic header is available
    if (dynamicHeader) {
        html = html.replace(
            /<div class="nav-links"[\s\S]*?<\/div>/,
            `<div class="nav-links">${dynamicHeader}
            </div>`
        );
    }
    
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
 * Prepare home page content data
 */
function prepareHomePageContent(homeConfig) {
    let contentData = {
        title: CONFIG.title,
        description: CONFIG.description,
        keywords: 'velocity, velo, package manager, homebrew, swift, macos, apple silicon',
        heroContent: CONFIG.defaultHeroContent,
        dynamicSections: '' // This will contain all the dynamic sections HTML
    };
    
    if (homeConfig) {
        const { frontmatter, sections } = homeConfig;
        
        // Override with HOME.md data if available
        contentData.title = frontmatter.title || contentData.title;
        contentData.description = frontmatter.description || contentData.description;
        contentData.keywords = frontmatter.keywords || contentData.keywords;
        
        // Extract hero content from frontmatter
        contentData.heroContent = {
            badge_icon: frontmatter.badge_icon || contentData.heroContent.badge_icon,
            badge_text: frontmatter.badge_text || contentData.heroContent.badge_text,
            hero_title: frontmatter.hero_title || contentData.heroContent.hero_title,
            hero_subtitle: frontmatter.hero_subtitle || contentData.heroContent.hero_subtitle,
            cta_primary_text: frontmatter.cta_primary_text || contentData.heroContent.cta_primary_text,
            cta_primary_url: frontmatter.cta_primary_url || contentData.heroContent.cta_primary_url,
            cta_secondary_text: frontmatter.cta_secondary_text || contentData.heroContent.cta_secondary_text,
            cta_secondary_url: frontmatter.cta_secondary_url || contentData.heroContent.cta_secondary_url,
            cta_note: frontmatter.cta_note || contentData.heroContent.cta_note
        };
        
        // Generate dynamic sections HTML from all H2 sections in markdown
        contentData.dynamicSections = generators.dynamicSections(sections);
    }
    
    return contentData;
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