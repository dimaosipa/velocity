# Homebrew Tap Automation Setup

This guide explains how to set up the automated Homebrew tap updates for Velo releases.

## Prerequisites

- Access to both repositories:
  - `dimaosipa/velocity` (main repo)
  - `dimaosipa/brew` (tap repo)
- Formula file already exists at `dimaosipa/brew/Formula/velo.rb`

## Setup Steps

### 1. Create GitHub Personal Access Token

1. Go to GitHub Settings → Developer Settings → Personal Access Tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Give it a descriptive name: `HOMEBREW_TAP_TOKEN`
4. Select scopes:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `workflow` (Update GitHub Action workflows)
5. Set expiration (recommend: 1 year)
6. Click "Generate token"
7. **Copy the token immediately** (you won't see it again!)

### 2. Add Token to Repository Secrets

1. Go to `dimaosipa/velocity` repository
2. Navigate to Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Name: `HOMEBREW_TAP_TOKEN`
5. Value: Paste the token from step 1
6. Click "Add secret"

## How It Works

### For Tagged Releases

When you create a new release (e.g., `v1.0.0`):

1. Push tag: `git tag v1.0.0 && git push origin v1.0.0`
2. Release workflow automatically:
   - Builds the binary
   - Creates GitHub release
   - Updates `dimaosipa/brew/Formula/velo.rb`
3. Users can immediately: `brew update && brew upgrade velo`

### For Development Builds

Every push to main branch:

1. Creates/updates a "nightly" pre-release
2. Provides stable URL for testing
3. (Optional) Can update tap with dev version

## Testing

To test the automation:

1. Create a test tag: `git tag v0.0.3-test`
2. Push it: `git push origin v0.0.3-test`
3. Watch the Actions tab for progress
4. Check `dimaosipa/brew` for the automated commit
5. Test installation: `brew install dimaosipa/brew/velo`

## Troubleshooting

### Token Issues

If you see "Bad credentials" errors:

- Verify token hasn't expired
- Ensure token has correct permissions
- Check secret name matches exactly: `HOMEBREW_TAP_TOKEN`

### Formula Update Fails

If the formula update fails:

- Ensure `Formula/velo.rb` exists in tap repo
- Check that formula class name is `class Velo < Formula`
- Verify download URL is accessible

### Manual Testing

Test the download URL manually:

```bash
curl -L https://github.com/dimaosipa/velocity/releases/download/v0.0.3/velo-v0.0.3-arm64.tar.gz -o test.tar.gz
shasum -a 256 test.tar.gz
```

## Enabling Development Builds

To enable Homebrew updates for development builds:

1. Edit `.github/workflows/ci.yml`
2. Uncomment the "Update Homebrew Tap (Development)" section
3. This will update tap on every main branch push

⚠️ **Warning**: This can create many commits in your tap repo!
