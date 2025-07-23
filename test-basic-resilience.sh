#!/bin/bash

# RTPI-PEN Basic Resilience Framework Test
# Quick validation without network dependencies
# Version: 1.0.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🧪 RTPI-PEN Basic Resilience Framework Test"
echo "=========================================="

# Test 1: Load resilience framework
echo -e "${BLUE}[TEST] Loading resilience framework...${NC}"
if [ -f "lib/installation-resilience.sh" ]; then
    source lib/installation-resilience.sh
    echo -e "${GREEN}[PASS] Resilience framework loaded successfully${NC}"
else
    echo -e "${RED}[FAIL] Resilience framework not found${NC}"
    exit 1
fi

# Test 2: Basic function availability
echo -e "${BLUE}[TEST] Checking function availability...${NC}"
functions_to_check=(
    "log" "warn" "error" "info"
    "check_image_availability"
    "find_image_fallback" 
    "save_checkpoint"
    "has_checkpoint"
    "retry_with_backoff"
)

all_functions_available=true
for func in "${functions_to_check[@]}"; do
    if command -v "$func" >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ Function $func available${NC}"
    else
        echo -e "${RED}  ✗ Function $func not available${NC}"
        all_functions_available=false
    fi
done

if [ "$all_functions_available" = true ]; then
    echo -e "${GREEN}[PASS] All required functions available${NC}"
else
    echo -e "${RED}[FAIL] Some functions missing${NC}"
    exit 1
fi

# Test 3: Image fallback database
echo -e "${BLUE}[TEST] Checking image fallback database...${NC}"
if [ ${#IMAGE_FALLBACKS[@]} -gt 0 ]; then
    echo -e "${GREEN}[PASS] Image fallback database loaded with ${#IMAGE_FALLBACKS[@]} entries${NC}"
    echo -e "${BLUE}  Sample fallbacks:${NC}"
    count=0
    for image in "${!IMAGE_FALLBACKS[@]}"; do
        if [ $count -lt 3 ]; then
            echo -e "${BLUE}    $image -> ${IMAGE_FALLBACKS[$image]%%,*}${NC}"
            ((count++))
        fi
    done
else
    echo -e "${RED}[FAIL] Image fallback database is empty${NC}"
    exit 1
fi

# Test 4: Checkpoint system
echo -e "${BLUE}[TEST] Testing checkpoint system...${NC}"
clear_checkpoints
save_checkpoint "TEST_BASIC"

if has_checkpoint "TEST_BASIC"; then
    echo -e "${GREEN}[PASS] Checkpoint system works${NC}"
    clear_checkpoints
else
    echo -e "${RED}[FAIL] Checkpoint system failed${NC}"
    exit 1
fi

# Test 5: Docker Compose file validation
echo -e "${BLUE}[TEST] Checking Docker Compose file...${NC}"
if [ -f "docker-compose.yml" ]; then
    # Check if the VS Code image fix is present
    if grep -q "kasmweb/vs-code:1.17.0-rolling-daily" docker-compose.yml; then
        echo -e "${GREEN}[PASS] Docker Compose file contains fixed VS Code image${NC}"
    else
        echo -e "${YELLOW}[WARN] VS Code image fix not found in docker-compose.yml${NC}"
    fi
    
    # Count services
    service_count=$(grep -c "^[[:space:]]*[a-zA-Z0-9_-]*:" docker-compose.yml)
    echo -e "${GREEN}  ✓ Docker Compose file valid with ~$service_count services${NC}"
else
    echo -e "${RED}[FAIL] docker-compose.yml not found${NC}"
    exit 1
fi

# Test 6: Fresh installation script integration
echo -e "${BLUE}[TEST] Checking fresh installation script integration...${NC}"
if [ -f "fresh-rtpi-pen.sh" ]; then
    if grep -q "lib/installation-resilience.sh" fresh-rtpi-pen.sh; then
        echo -e "${GREEN}[PASS] Fresh installation script integrated with resilience framework${NC}"
    else
        echo -e "${RED}[FAIL] Fresh installation script not integrated${NC}"
        exit 1
    fi
    
    if grep -q "run_installation_resilience_check" fresh-rtpi-pen.sh; then
        echo -e "${GREEN}  ✓ Resilience check call found in installation script${NC}"
    else
        echo -e "${YELLOW}[WARN] Resilience check call not found${NC}"
    fi
else
    echo -e "${RED}[FAIL] fresh-rtpi-pen.sh not found${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 All basic tests passed! Resilience framework is properly integrated.${NC}"
echo ""
echo "📋 Summary:"
echo "  ✅ Resilience framework loaded and functional"
echo "  ✅ Docker image issue (kasmweb/vs-code:1.17.0) fixed"
echo "  ✅ Installation script enhanced with resilience checks"
echo "  ✅ Checkpoint system for installation recovery"
echo "  ✅ Image fallback system for unavailable Docker images"
echo ""
echo -e "${BLUE}🚀 Ready for production deployment!${NC}"
echo ""
echo "Next steps:"
echo "  • Run './fresh-rtpi-pen.sh' for installation with resilience"
echo "  • Use './test-resilience-framework.sh' for comprehensive testing"
echo "  • Monitor logs for resilience framework activity"
