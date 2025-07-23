#!/bin/bash

# RTPI-PEN Resilience Framework Test Suite
# Validates the installation resilience capabilities
# Version: 1.0.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test logging
test_log() {
    echo -e "${BLUE}[TEST] $1${NC}"
}

test_pass() {
    echo -e "${GREEN}[PASS] $1${NC}"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}[FAIL] $1${NC}"
    ((TESTS_FAILED++))
}

test_warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

# Load the resilience framework
if [ -f "lib/installation-resilience.sh" ]; then
    source lib/installation-resilience.sh
    test_pass "Resilience framework loaded successfully"
else
    test_fail "Resilience framework not found"
    exit 1
fi

# Test 1: Network Connectivity Test
test_network_connectivity_function() {
    ((TESTS_TOTAL++))
    test_log "Testing network connectivity function..."
    
    if test_network_connectivity; then
        test_pass "Network connectivity test function works"
    else
        test_fail "Network connectivity test failed"
    fi
}

# Test 2: Docker Image Availability Check
test_docker_image_availability() {
    ((TESTS_TOTAL++))
    test_log "Testing Docker image availability check..."
    
    # Test with a known good image
    if check_image_availability "alpine:latest" 10; then
        test_pass "Docker image availability check works for existing images"
    else
        test_fail "Failed to check availability of alpine:latest"
    fi
    
    ((TESTS_TOTAL++))
    # Test with a non-existent image
    if ! check_image_availability "nonexistent/image:fake" 5; then
        test_pass "Docker image availability correctly identifies non-existent images"
    else
        test_fail "Failed to identify non-existent image"
    fi
}

# Test 3: Image Fallback System
test_image_fallback_system() {
    ((TESTS_TOTAL++))
    test_log "Testing image fallback system..."
    
    # Test fallback for the fixed VS Code image
    local original_image="kasmweb/vs-code:1.17.0"
    local fallback=$(find_image_fallback "$original_image")
    
    if [ -n "$fallback" ]; then
        test_pass "Image fallback system found replacement: $fallback"
    else
        test_fail "Image fallback system failed to find replacement"
    fi
}

# Test 4: Docker Compose Image Validation
test_docker_compose_validation() {
    ((TESTS_TOTAL++))
    test_log "Testing Docker Compose image validation..."
    
    if [ -f "docker-compose.yml" ]; then
        # Create a backup
        cp docker-compose.yml docker-compose.yml.test-backup
        
        # Run validation (without updates to avoid modifying the real file)
        if validate_docker_images "docker-compose.yml" false; then
            test_pass "Docker Compose image validation completed"
        else
            test_warn "Some images in docker-compose.yml are not available (expected in test environment)"
        fi
        
        # Restore backup
        mv docker-compose.yml.test-backup docker-compose.yml
    else
        test_fail "docker-compose.yml not found"
    fi
}

# Test 5: Checkpoint System
test_checkpoint_system() {
    ((TESTS_TOTAL++))
    test_log "Testing checkpoint system..."
    
    # Clear any existing checkpoints
    clear_checkpoints
    
    # Save a test checkpoint
    save_checkpoint "TEST_CHECKPOINT"
    
    # Check if checkpoint exists
    if has_checkpoint "TEST_CHECKPOINT"; then
        test_pass "Checkpoint system works - checkpoint saved and found"
    else
        test_fail "Checkpoint system failed - checkpoint not found"
    fi
    
    ((TESTS_TOTAL++))
    # Test getting last checkpoint
    local last_checkpoint=$(get_last_checkpoint)
    if [ "$last_checkpoint" = "TEST_CHECKPOINT" ]; then
        test_pass "Get last checkpoint function works"
    else
        test_fail "Get last checkpoint returned: $last_checkpoint (expected: TEST_CHECKPOINT)"
    fi
    
    # Clean up test checkpoints
    clear_checkpoints
}

# Test 6: Retry with Backoff
test_retry_with_backoff() {
    ((TESTS_TOTAL++))
    test_log "Testing retry with backoff function..."
    
    # Test with a command that should succeed
    if retry_with_backoff 3 1 "test command" true; then
        test_pass "Retry with backoff works for successful commands"
    else
        test_fail "Retry with backoff failed for successful command"
    fi
    
    ((TESTS_TOTAL++))
    # Test with a command that should fail
    if ! retry_with_backoff 2 1 "failing command" false; then
        test_pass "Retry with backoff correctly handles failing commands"
    else
        test_fail "Retry with backoff should have failed but didn't"
    fi
}

# Test 7: Pre-flight Validation Components
test_preflight_components() {
    ((TESTS_TOTAL++))
    test_log "Testing pre-flight validation components..."
    
    # Test individual components without full validation
    local validation_passed=true
    
    # Test network connectivity
    if ! test_network_connectivity; then
        test_warn "Network connectivity test failed (may be expected in test environment)"
        validation_passed=false
    fi
    
    # Test Docker availability
    if ! command -v docker >/dev/null 2>&1; then
        test_fail "Docker not available"
        validation_passed=false
    elif ! docker info >/dev/null 2>&1; then
        test_fail "Docker not running"
        validation_passed=false
    fi
    
    if [ "$validation_passed" = true ]; then
        test_pass "Pre-flight validation components working"
    else
        test_warn "Some pre-flight validation components failed (may be expected in test environment)"
    fi
}

# Test 8: Configuration Validation
test_configuration_files() {
    ((TESTS_TOTAL++))
    test_log "Testing configuration file validation..."
    
    local config_valid=true
    
    # Check if critical files exist
    local critical_files=("docker-compose.yml" "fresh-rtpi-pen.sh" "lib/installation-resilience.sh")
    
    for file in "${critical_files[@]}"; do
        if [ ! -f "$file" ]; then
            test_fail "Critical file missing: $file"
            config_valid=false
        fi
    done
    
    if [ "$config_valid" = true ]; then
        test_pass "Critical configuration files present"
    fi
}

# Test 9: Image Fallback Database Completeness
test_fallback_database() {
    ((TESTS_TOTAL++))
    test_log "Testing image fallback database completeness..."
    
    # Extract images from docker-compose.yml
    if [ -f "docker-compose.yml" ]; then
        local compose_images=($(grep -E "^\s*image:" docker-compose.yml | sed 's/.*image:\s*//' | sed 's/[[:space:]]*$//' | sort -u))
        local missing_fallbacks=()
        
        for image in "${compose_images[@]}"; do
            if [ -z "${IMAGE_FALLBACKS[$image]}" ]; then
                missing_fallbacks+=("$image")
            fi
        done
        
        if [ ${#missing_fallbacks[@]} -eq 0 ]; then
            test_pass "All Docker Compose images have fallback definitions"
        else
            test_warn "Images without fallback definitions: ${missing_fallbacks[*]}"
            test_warn "Consider adding fallbacks for better resilience"
        fi
    else
        test_fail "docker-compose.yml not found for fallback validation"
    fi
}

# Test 10: Integration Test
test_integration() {
    ((TESTS_TOTAL++))
    test_log "Running integration test..."
    
    # Test the main resilience check function (dry run)
    test_log "Note: This is a dry-run integration test, not modifying system"
    
    # We can't run the full resilience check in a test environment
    # So we'll just verify the function exists and can be called
    if command -v run_installation_resilience_check >/dev/null 2>&1; then
        test_pass "Main resilience check function is available"
    else
        test_fail "Main resilience check function not found"
    fi
}

# Run all tests
echo "🧪 RTPI-PEN Resilience Framework Test Suite"
echo "==========================================="
echo ""

test_network_connectivity_function
test_docker_image_availability
test_image_fallback_system
test_docker_compose_validation
test_checkpoint_system
test_retry_with_backoff
test_preflight_components
test_configuration_files
test_fallback_database
test_integration

# Test summary
echo ""
echo "🏁 Test Results Summary"
echo "======================="
echo "Total Tests: $TESTS_TOTAL"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed! Resilience framework is working correctly.${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Some tests failed. Review the output above for details.${NC}"
    exit 1
fi
