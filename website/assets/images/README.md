# Image Assets

This directory contains all image assets for the Velocity website.

## Required Assets (to be provided)

### Logos
- `logo.png` - Main logo (preferably SVG format)
- `logo-white.png` - White variant for dark backgrounds
- `logo-icon.png` - Icon-only version for favicons

### Screenshots/Mockups (optional)
- `hero-terminal.png` - Terminal demo showing velo vs brew speed
- `performance-chart.svg` - Speed comparison visualization
- `apple-silicon.svg` - M1/M2/M3 chip illustration

## File Guidelines

- **Logo**: SVG preferred for crisp scaling, PNG fallback
- **Screenshots**: PNG or JPG, high resolution
- **Icons**: SVG preferred for vector graphics
- **Compression**: Optimize for web (use tools like ImageOptim)

## Favicon Generation

From your main logo, generate:
- `favicon.ico` (16x16, 32x32, 48x48)
- `apple-touch-icon.png` (180x180)
- Various sizes for PWA manifest

The build system will automatically copy and optimize these assets.