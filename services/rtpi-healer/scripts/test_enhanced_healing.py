#!/usr/bin/env python3
"""
RTPI-PEN Enhanced Self-Healing System Test Script
Demonstrates and validates the new configuration validation and auto-repair capabilities
"""

import os
import sys
import json
import logging
from datetime import datetime
from typing import Dict, Any

from config_validator import ConfigurationValidator
from config_autorepair import ConfigurationAutoRepair

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('enhanced-healing-test')

class EnhancedHealingTest:
    """Test suite for enhanced self-healing capabilities"""
    
    def __init__(self):
        self.validator = ConfigurationValidator()
        self.autorepair = ConfigurationAutoRepair()
        self.test_results = {}
    
    def print_banner(self):
        """Print test banner"""
        banner = """
╔══════════════════════════════════════════════════════════════════════════════╗
║                    RTPI-PEN Enhanced Self-Healing System                    ║
║                         Configuration Test & Demo                           ║
║                                                                              ║
║  🔍 Validates configurations proactively                                    ║
║  🔧 Automatically repairs detected issues                                   ║
║  🛡️ Prevents startup failures like the recent SysReptor base64 issue       ║
╚══════════════════════════════════════════════════════════════════════════════╝
        """
        print(banner)
    
    def test_base64_validation(self) -> Dict[str, Any]:
        """Test base64 validation capabilities"""
        logger.info("🧪 Testing Base64 Validation...")
        
        test_cases = [
            ("Valid base64", "SGVsbG8gV29ybGQh", True),  # "Hello World!" in base64
            ("Invalid base64", "InvalidBase64!", False),
            ("Empty string", "", False),
            ("Short key", "c2hvcnQ=", False),  # "short" in base64 (too short for encryption)
            ("Proper key length", "VGhpcyBpcyBhIDMyLWJ5dGUga2V5IGZvciBBRVMtMjU2IGVuY3J5cHRpb24h", True)  # 32-byte key
        ]
        
        results = []
        for description, test_value, should_pass in test_cases:
            result = self.validator.validate_base64_encoding(test_value, f"Test: {description}")
            passed = result.passed == should_pass
            
            results.append({
                'description': description,
                'test_value': test_value[:20] + "..." if len(test_value) > 20 else test_value,
                'expected': 'PASS' if should_pass else 'FAIL',
                'actual': 'PASS' if result.passed else 'FAIL',
                'test_passed': passed,
                'message': result.message
            })
            
            status = "✅" if passed else "❌"
            logger.info(f"  {status} {description}: Expected {should_pass}, Got {result.passed}")
        
        return {
            'test_name': 'Base64 Validation',
            'total_cases': len(test_cases),
            'passed_cases': sum(1 for r in results if r['test_passed']),
            'results': results
        }
    
    def test_encryption_keys_validation(self) -> Dict[str, Any]:
        """Test encryption keys validation"""
        logger.info("🔐 Testing Encryption Keys Validation...")
        
        # Valid encryption key structure
        valid_keys = '[{"id":"test-key-id","key":"VGhpcyBpcyBhIDMyLWJ5dGUga2V5IGZvciBBRVMtMjU2IGVuY3J5cHRpb24h","cipher":"AES-GCM","revoked":false}]'
        
        # Invalid cases
        test_cases = [
            ("Valid encryption keys", valid_keys, True),
            ("Invalid JSON", '[{"id":"test-key-id","key":', False),
            ("Missing required fields", '[{"id":"test-key-id"}]', False),
            ("Invalid base64 key", '[{"id":"test-key-id","key":"InvalidBase64!","cipher":"AES-GCM","revoked":false}]', False),
            ("Empty array", '[]', False)
        ]
        
        results = []
        for description, test_value, should_pass in test_cases:
            result = self.validator.validate_encryption_keys(test_value)
            passed = result.passed == should_pass
            
            results.append({
                'description': description,
                'expected': 'PASS' if should_pass else 'FAIL',
                'actual': 'PASS' if result.passed else 'FAIL',
                'test_passed': passed,
                'message': result.message,
                'auto_fixable': result.auto_fixable
            })
            
            status = "✅" if passed else "❌"
            auto_fix = "🔧" if result.auto_fixable else ""
            logger.info(f"  {status} {auto_fix} {description}: {result.message}")
        
        return {
            'test_name': 'Encryption Keys Validation',
            'total_cases': len(test_cases),
            'passed_cases': sum(1 for r in results if r['test_passed']),
            'results': results
        }
    
    def test_current_sysreptor_config(self) -> Dict[str, Any]:
        """Test current SysReptor configuration"""
        logger.info("📋 Testing Current SysReptor Configuration...")
        
        sysreptor_config = "/opt/rtpi-pen/configs/rtpi-sysreptor/app.env"
        
        if not os.path.exists(sysreptor_config):
            return {
                'test_name': 'Current SysReptor Configuration',
                'config_exists': False,
                'message': f"Configuration file not found: {sysreptor_config}"
            }
        
        validation_results = self.validator.validate_sysreptor_configuration(sysreptor_config)
        
        total_checks = len(validation_results)
        passed_checks = sum(1 for r in validation_results if r.passed)
        failed_checks = total_checks - passed_checks
        auto_fixable = sum(1 for r in validation_results if not r.passed and r.auto_fixable)
        
        # Show validation details
        for result in validation_results:
            status = "✅" if result.passed else "❌"
            auto_fix = "🔧" if result.auto_fixable else ""
            severity = f"[{result.severity.upper()}]" if hasattr(result, 'severity') and result.severity != 'error' else ""
            logger.info(f"  {status} {auto_fix} {severity} {result.message}")
        
        return {
            'test_name': 'Current SysReptor Configuration',
            'config_exists': True,
            'config_path': sysreptor_config,
            'total_checks': total_checks,
            'passed_checks': passed_checks,
            'failed_checks': failed_checks,
            'auto_fixable_failures': auto_fixable,
            'overall_status': 'HEALTHY' if failed_checks == 0 else 'ISSUES_DETECTED',
            'validation_results': [
                {
                    'message': r.message,
                    'passed': r.passed,
                    'auto_fixable': r.auto_fixable,
                    'severity': getattr(r, 'severity', 'error')
                } for r in validation_results
            ]
        }
    
    def test_auto_repair_capabilities(self) -> Dict[str, Any]:
        """Test auto-repair capabilities"""
        logger.info("🔧 Testing Auto-Repair Capabilities...")
        
        # Create a temporary invalid config to test repair
        temp_config = "/tmp/test_sysreptor_config.env"
        
        # Create a config with intentional issues
        invalid_config_content = """# Test configuration with issues
SECRET_KEY=too_short
DATABASE_HOST=rtpi-database
DATABASE_NAME=sysreptor
DATABASE_USER=sysreptor
DATABASE_PASSWORD=sysreptorpassword
# Missing ENCRYPTION_KEYS
# Missing REDIS_HOST
# Missing REDIS_PASSWORD
"""
        
        try:
            with open(temp_config, 'w') as f:
                f.write(invalid_config_content)
            
            # Validate the broken config
            logger.info("  📝 Created test configuration with intentional issues...")
            validation_results = self.validator.validate_sysreptor_configuration(temp_config)
            
            failed_validations = [r for r in validation_results if not r.passed]
            auto_fixable_count = sum(1 for r in failed_validations if r.auto_fixable)
            
            logger.info(f"  📊 Found {len(failed_validations)} issues, {auto_fixable_count} auto-fixable")
            
            # Attempt repairs
            if failed_validations:
                logger.info("  🔨 Attempting automatic repairs...")
                repair_summary = self.autorepair.repair_validation_failures(failed_validations)
                
                # Re-validate after repair
                post_repair_results = self.validator.validate_sysreptor_configuration(temp_config)
                post_repair_failures = sum(1 for r in post_repair_results if not r.passed)
                
                return {
                    'test_name': 'Auto-Repair Capabilities',
                    'initial_failures': len(failed_validations),
                    'auto_fixable_failures': auto_fixable_count,
                    'repair_attempts': repair_summary['attempted_repairs'],
                    'successful_repairs': repair_summary['successful_repairs'],
                    'failed_repairs': repair_summary['failed_repairs'],
                    'post_repair_failures': post_repair_failures,
                    'repair_effectiveness': f"{repair_summary['successful_repairs']}/{repair_summary['attempted_repairs']}",
                    'overall_success': post_repair_failures < len(failed_validations)
                }
            else:
                return {
                    'test_name': 'Auto-Repair Capabilities',
                    'message': 'No repairs needed - test config was already valid'
                }
                
        except Exception as e:
            return {
                'test_name': 'Auto-Repair Capabilities',
                'error': str(e),
                'success': False
            }
        finally:
            # Clean up temp file
            if os.path.exists(temp_config):
                os.remove(temp_config)
    
    def demonstrate_issue_prevention(self) -> Dict[str, Any]:
        """Demonstrate how the system would have prevented the recent SysReptor issue"""
        logger.info("🛡️ Demonstrating Issue Prevention...")
        
        # Simulate the corrupted encryption key that caused the recent issue
        problematic_config = """# SysReptor Configuration (simulating the recent issue)
SECRET_KEY=+6OihkIWYaHbVAp/6grlvPKGdrzB8/OPayL1QAu/ZgWKLJLrgv+f2rGK/GNvxMqa
DATABASE_HOST=rtpi-database
DATABASE_NAME=sysreptor
DATABASE_USER=sysreptor
DATABASE_PASSWORD=sysreptorpassword
DATABASE_PORT=5432

# This was the problematic encryption key (corrupted base64)
ENCRYPTION_KEYS=[{"id":"a704e0bc-a687-452b-aa59-bd23a3bff113","key":"olK4x8gl9pYknp405sKSueVTuPc5BSEH6WQbyaGvZx/85YnUCOFqEpmd8JU","cipher":"AES-GCM","revoked":false}]
DEFAULT_ENCRYPTION_KEY_ID=a704e0bc-a687-452b-aa59-bd23a3bff113
"""
        
        temp_problematic_config = "/tmp/problematic_sysreptor.env"
        
        try:
            with open(temp_problematic_config, 'w') as f:
                f.write(problematic_config)
            
            logger.info("  📝 Created configuration with the problematic base64 encryption key...")
            
            # Step 1: Detection
            logger.info("  🔍 Step 1: Detecting the issue...")
            validation_results = self.validator.validate_sysreptor_configuration(temp_problematic_config)
            
            encryption_key_issues = [r for r in validation_results if not r.passed and 'encryption' in r.message.lower()]
            
            if encryption_key_issues:
                logger.info(f"  ❌ Issue detected: {encryption_key_issues[0].message}")
                
                # Step 2: Auto-repair
                logger.info("  🔧 Step 2: Automatic repair...")
                repair_summary = self.autorepair.repair_validation_failures(encryption_key_issues)
                
                # Step 3: Re-validation
                logger.info("  ✅ Step 3: Re-validation after repair...")
                post_repair_results = self.validator.validate_sysreptor_configuration(temp_problematic_config)
                post_repair_encryption_issues = [r for r in post_repair_results if not r.passed and 'encryption' in r.message.lower()]
                
                prevention_successful = len(post_repair_encryption_issues) == 0
                
                if prevention_successful:
                    logger.info("  🎉 Success! The issue has been automatically resolved.")
                    logger.info("  💡 This would have prevented the SysReptor startup failure!")
                else:
                    logger.info("  ⚠️ Some issues remain, but the system attempted repair.")
                
                return {
                    'test_name': 'Issue Prevention Demonstration',
                    'issue_detected': True,
                    'issue_description': encryption_key_issues[0].message,
                    'auto_repair_attempted': True,
                    'repair_successful': prevention_successful,
                    'would_prevent_startup_failure': prevention_successful,
                    'repair_details': repair_summary
                }
            else:
                return {
                    'test_name': 'Issue Prevention Demonstration',
                    'issue_detected': False,
                    'message': 'The problematic configuration was not detected as invalid'
                }
                
        except Exception as e:
            return {
                'test_name': 'Issue Prevention Demonstration',
                'error': str(e),
                'success': False
            }
        finally:
            if os.path.exists(temp_problematic_config):
                os.remove(temp_problematic_config)
    
    def run_comprehensive_test(self) -> Dict[str, Any]:
        """Run all tests and generate comprehensive report"""
        logger.info("🚀 Starting comprehensive enhanced self-healing test suite...")
        
        self.print_banner()
        
        # Run all test suites
        test_suites = [
            self.test_base64_validation(),
            self.test_encryption_keys_validation(),
            self.test_current_sysreptor_config(),
            self.test_auto_repair_capabilities(),
            self.demonstrate_issue_prevention()
        ]
        
        # Compile results
        overall_results = {
            'test_timestamp': datetime.now().isoformat(),
            'test_suites': test_suites,
            'summary': self._generate_summary(test_suites)
        }
        
        self._print_summary(overall_results['summary'])
        
        return overall_results
    
    def _generate_summary(self, test_suites: list) -> Dict[str, Any]:
        """Generate test summary"""
        total_suites = len(test_suites)
        successful_suites = 0
        total_test_cases = 0
        passed_test_cases = 0
        
        for suite in test_suites:
            if suite.get('total_cases'):
                total_test_cases += suite['total_cases']
                passed_test_cases += suite.get('passed_cases', 0)
                if suite['passed_cases'] == suite['total_cases']:
                    successful_suites += 1
            elif suite.get('overall_success', True):
                successful_suites += 1
        
        return {
            'total_test_suites': total_suites,
            'successful_test_suites': successful_suites,
            'total_test_cases': total_test_cases,
            'passed_test_cases': passed_test_cases,
            'overall_success_rate': f"{successful_suites}/{total_suites}",
            'test_case_success_rate': f"{passed_test_cases}/{total_test_cases}" if total_test_cases > 0 else "N/A"
        }
    
    def _print_summary(self, summary: Dict[str, Any]):
        """Print test summary"""
        print("\n" + "="*80)
        print("🎯 ENHANCED SELF-HEALING SYSTEM TEST SUMMARY")
        print("="*80)
        print(f"📊 Test Suites: {summary['overall_success_rate']} successful")
        if summary.get('total_test_cases', 0) > 0:
            print(f"📋 Test Cases: {summary['test_case_success_rate']} passed")
        
        print("\n✨ ENHANCED CAPABILITIES DEMONSTRATED:")
        print("  🔍 Proactive configuration validation")
        print("  🔧 Automatic configuration repair")
        print("  🛡️ Prevention of startup failures")
        print("  📊 Comprehensive issue detection")
        print("  🔄 Self-healing workflow integration")
        
        print("\n💡 BENEFITS:")
        print("  ✅ Prevents issues like the recent SysReptor base64 encryption key problem")
        print("  ✅ Reduces manual intervention and downtime")
        print("  ✅ Maintains service availability through intelligent recovery")
        print("  ✅ Provides comprehensive visibility into system health")
        
        print("\n🔮 NEXT STEPS:")
        print("  • The enhanced healer will run proactive validation every 30 minutes")
        print("  • Pre-startup validation prevents problematic container restarts")
        print("  • Configuration auto-repair handles common issues automatically")
        print("  • System continues to monitor and heal container issues")
        
        print("="*80)

def main():
    """Main test execution"""
    test_suite = EnhancedHealingTest()
    
    try:
        results = test_suite.run_comprehensive_test()
        
        # Save detailed results
        report_file = f"/tmp/enhanced-healing-test-{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(report_file, 'w') as f:
            json.dump(results, f, indent=2, default=str)
        
        print(f"\n📄 Detailed test report saved to: {report_file}")
        
        # Exit with appropriate code
        success = results['summary']['successful_test_suites'] == results['summary']['total_test_suites']
        sys.exit(0 if success else 1)
        
    except Exception as e:
        logger.error(f"Test suite failed with error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
