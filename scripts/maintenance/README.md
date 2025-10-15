# RTPI-PEN Maintenance Scripts

This directory contains maintenance and utility scripts for the RTPI-PEN Docker image resolution system and infrastructure management.

## Overview

These scripts were developed to solve Docker image availability issues that were causing deployment failures, particularly with hardcoded tags like `kasmweb/vs-code:1.17.0-rolling-daily` that would become unavailable.

## Scripts

### Core Image Resolution Scripts

#### `image-resolver.sh`
**Purpose**: Dynamically resolves available Docker image tags from registries and selects the best available options.

**Key Features**:
- Queries Docker Hub API for available tags
- Implements intelligent tag selection with preference ordering
- Supports pattern matching (e.g., `1.17.*` matches `1.17.0`, `1.17.1`, etc.)
- Includes retry logic with exponential backoff
- Comprehensive error handling and logging

**Usage**:
```bash
./image-resolver.sh resolve          # Resolve all configured images
./image-resolver.sh tags nginx       # Get available tags for specific image
./image-resolver.sh verify           # Verify resolved images
```

#### `image-checker.sh`
**Purpose**: Pre-deployment verification of Docker images to prevent deployment failures.

**Key Features**:
- Checks local image availability
- Verifies remote image manifests without pulling
- Pre-loads critical images with retry logic
- Categorizes images by criticality (core vs optional)
- Provides detailed verification reports

**Usage**:
```bash
./image-checker.sh verify            # Verify all images
./image-checker.sh pull              # Verify and pull missing images
./image-checker.sh preload           # Pre-load critical images
./image-checker.sh check nginx:latest # Check specific image
```

#### `compose-generator.sh`
**Purpose**: Generates dynamic docker-compose.yml files from templates with resolved image tags.

**Key Features**:
- Template-based composition generation
- Environment variable substitution
- Automatic backup of existing compose files
- Profile-specific compose file generation
- Comprehensive validation

**Usage**:
```bash
./compose-generator.sh generate      # Generate docker-compose.yml
./compose-generator.sh validate      # Validate files
./compose-generator.sh profiles      # Generate profile-specific files
./compose-generator.sh backup        # Backup existing files
```

## Configuration Files

### `configs/image-fallbacks.conf`
Defines image preferences and fallback strategies.

**Format**:
```
VARIABLE_NAME=image_name:preference1,preference2,preference3
```

**Example**:
```
KASM_VSCODE_IMAGE=kasmweb/vs-code:1.17.*,1.16.*,rolling-daily,rolling-weekly,latest
POSTGRES_IMAGE=postgres:16,15,14,latest
```

## Templates

### `templates/docker-compose.template.yml`
Template for generating dynamic docker-compose.yml files with environment variable substitution.

**Features**:
- Uses environment variables: `${KASM_VSCODE_IMAGE:-kasmweb/vs-code:latest}`
- Includes service profiles for selective deployment
- Maintains all original functionality while adding flexibility

## Integration

These scripts are integrated into the main deployment workflows:

- **fresh-rtpi-pen.sh**: Uses the image resolution system before Docker operations
- **deploy-self-healing.sh**: Includes image resolution in the deployment pipeline

## Workflow

1. **Configure** image preferences in `configs/image-fallbacks.conf`
2. **Resolve** available image tags with `image-resolver.sh resolve`
3. **Generate** docker-compose.yml with `compose-generator.sh generate`
4. **Verify** image availability with `image-checker.sh verify`
5. **Deploy** using the generated compose file

## Benefits

- **Eliminates hardcoded tag dependencies** - No more deployment failures due to unavailable tags
- **Automatic recovery** - System handles image availability issues without manual intervention
- **Comprehensive fallback strategy** - Multiple levels of redundancy ensure deployment success
- **Improved reliability** - Extensive testing and validation prevent configuration errors

## Troubleshooting

### Common Issues

1. **API Rate Limiting**: System includes retry logic with exponential backoff
2. **Network Connectivity**: Falls back to cached results when available
3. **Image Not Available**: Automatically tries fallback images
4. **Configuration Errors**: Comprehensive validation with clear error messages

### Manual Recovery

```bash
# Complete reset
rm -f configs/resolved-image-tags.env
./image-resolver.sh resolve
./compose-generator.sh generate

# Check specific image
./image-resolver.sh tags kasmweb/vs-code

# Verify all images
./image-checker.sh verify
```

## Generated Files

- `configs/resolved-image-tags.env` - Auto-generated resolved image tags
- `docker-compose.yml` - Generated from template with resolved tags
- `backups/docker-compose.yml.backup.*` - Automatic backups

## Maintenance

- **Weekly**: Run `./image-resolver.sh resolve` to update image tags
- **Monthly**: Run `./image-checker.sh cleanup` to clean old images
- **Quarterly**: Review `configs/image-fallbacks.conf` for new image versions

---

For detailed documentation, see the original `IMAGE_RESOLUTION_SYSTEM.md` in the `docs/` directory.
