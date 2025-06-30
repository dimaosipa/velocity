# Velo Website

This directory contains the static website generator for the Velo package manager documentation.

## 🚀 Quick Start

```bash
# Install dependencies
npm install

# Build the website
npm run build

# Build and serve locally
npm run dev
```

## 📁 Structure

- `build.js` - Main build script that converts `../README.md` to HTML
- `template.html` - HTML template with navigation and styling
- `assets/style.css` - Responsive CSS styling
- `dist/` - Generated static site (auto-created)

## 🔧 How It Works

1. **Reads** the main `README.md` from the repository root
2. **Converts** markdown to HTML with syntax highlighting
3. **Generates** table of contents from headers
4. **Applies** responsive styling and navigation
5. **Outputs** static website to `dist/` directory

## 🌐 Deployment

### GitHub Pages (Automatic)
The website automatically deploys to GitHub Pages when:
- README.md is updated
- Any file in `website/` is changed
- Workflow is manually triggered

### Local Development
```bash
npm run dev
# Opens http://localhost:8080
```

## 🛠 Features

- ✅ Responsive design (mobile-friendly)
- ✅ Automatic table of contents
- ✅ Syntax highlighting for code blocks
- ✅ GitHub-style markdown rendering
- ✅ SEO optimized with meta tags
- ✅ Fast loading with minimal dependencies

## 📦 Dependencies

- `markdown-it` - Markdown parser
- `markdown-it-anchor` - Header anchor links
- `highlight.js` - Syntax highlighting
- `fs-extra` - File system utilities

All styling and JavaScript is inlined for optimal performance.