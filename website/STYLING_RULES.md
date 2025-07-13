# Dynamic Content Styling Rules for Velocity Website

This document outlines the comprehensive styling system implemented for all markdown content types in the Velocity website.

## Overview

The website now has a fully generic styling system that applies consistent formatting to all dynamic content sections regardless of what you add to `HOME.md` or other markdown files.

## CSS Class Structure

### Content Containers
All dynamic content is wrapped in containers with specific CSS classes:

- `.comparison-content` - For comparison tables and related content
- `.who-content` - For "Who is this for?" sections
- `.quickstart-content` - For installation and getting started content
- `.features-content` - For feature lists (fallback from grid)
- `.performance-content` - For performance details (fallback from grid)
- `.section-content` - Generic wrapper for any other dynamic content

### Universal Styling Rules

All content containers (`.comparison-content`, `.who-content`, etc.) inherit the same styling rules for:

#### Typography
- **H1**: 2.5rem, font-weight: 700, color: primary text
- **H2**: 2rem, font-weight: 600, color: primary text  
- **H3**: 1.5rem, font-weight: 600, color: primary text
- **H4**: 1.25rem, font-weight: 600, color: primary text
- **Paragraphs**: 1.1rem, line-height: 1.6, color: secondary text

#### Lists
- **Unordered lists**: Custom bullet points using primary color
- **Ordered lists**: Standard numbering with proper indentation
- **List items**: 1.1rem font size, proper spacing

#### Links
- **Default**: Primary color, no underline
- **Hover**: Primary dark color with underline
- **Smooth transitions**: 0.2s ease

#### Code
- **Inline code**: Light gray background, monospace font, rounded corners
- **Code blocks**: Dark background with syntax highlighting, rounded corners
- **Font**: JetBrains Mono and system monospace fallbacks

#### Tables
- **Design**: Clean, rounded corners, subtle shadows
- **Headers**: Gray background, bold text
- **Cells**: Proper padding, border separation
- **Hover**: Light gray background on row hover
- **Responsive**: Smaller font size on mobile

#### Other Elements
- **Blockquotes**: Left border in primary color, light background
- **Horizontal rules**: Subtle gray lines
- **Strong text**: Primary text color, font-weight: 600
- **Emphasis**: Italic, secondary text color

## Responsive Design

### Mobile (≤768px)
- Reduced font sizes for headings
- Smaller table cell padding
- Reduced code block padding
- Adjusted content container padding

### Accessibility
- Proper focus states for interactive elements
- High contrast colors
- Reduced motion support
- Print-friendly styles

## Syntax Highlighting

Code blocks include comprehensive syntax highlighting for:
- Comments (gray)
- Keywords (red)
- Strings (blue)
- Functions/Types (purple)
- Variables (orange)
- Numbers/Literals (blue)
- And more...

## Special Features

### Table Enhancement
- Automatic styling for comparison tables
- Green checkmarks (✅) styled with success color
- Red X marks (❌) styled with error color

### Future-Proof Design
The system automatically applies these styles to:
1. Any new sections you add to `HOME.md`
2. Any markdown content type (lists, tables, code, etc.)
3. Any combination of content within sections

## Usage Guidelines

### For Content Creators
1. **Just write markdown** - All styling is automatic
2. **Use standard markdown syntax** - No special formatting needed
3. **Add any sections** - They'll be styled consistently
4. **Mix content types** - Tables, lists, code blocks all work together

### For Developers
1. **Content containers** are automatically created by the build system
2. **CSS classes** are applied based on section names
3. **Fallback styling** ensures nothing appears unstyled
4. **Mobile responsiveness** is built-in

## Examples

### Supported Content Types
```markdown
## Any Section Name

Here's a paragraph with **bold text** and *italic text*.

- Bullet point lists
- With custom styling
- And proper spacing

1. Numbered lists
2. Also supported
3. With consistent formatting

| Tables | Are | Supported |
|--------|-----|-----------|
| With   | ✅  | Styling   |
| And    | ❌  | Indicators|

```code blocks```
Work perfectly

> Blockquotes look great too

[Links](./docs) are properly styled

---

This ensures that **any content you add to HOME.md** will look professional and consistent with the rest of the website design.
