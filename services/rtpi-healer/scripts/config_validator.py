#!/usr/bin/env python3
"""
RTPI-PEN Configuration Validation Engine
Proactive configuration validation to prevent startup failures
"""

import os
import sys
import json
import yaml
import base64
import logging
import re
import subprocess
import tempfile
from datetime import datetime
from typing import Dict, List, Optional, Tuple, Any
from pathlib import Path

import psycopg2
import redis
import docker

logger = logging.getLogger('rtpi-config-validator')

class ValidationResult:
    """Represents the result of a validation check"""
    def __init__(self, passed: bool, message: str, severity: str = "error", auto_fixable: bool = False, fix_action: str = None):
        self.passed = passed
        self.message = message
        self.severity = severity  # error, warning, info
        self.auto_fixable = auto_fixable
        self.fix_action = fix_action
        self.timestamp = datetime.now()

class ConfigurationValidator:
    """Main configuration validation engine"""
    
    def __init__(self):
        self.validation_results = []
        self.docker_client = docker.from_env()
        self.config_templates = {
            'sysreptor': '/opt/rtpi-pen/configs/rtpi-sysreptor/sysreptor/deploy/app.env.example',
            'kasm': '/opt/kasm/1.15.0/conf/app/agent.app.config.yaml',
            'empire': '/opt/empire/data/empire.db'
        }
        
    def _add_result(self, result: ValidationResult):
        """Add a validation result"""
        self.validation_results.append(result)
        if result.severity == "error":
            logger.error(f"❌ {result.message}")
        elif result.severity == "warning":
            logger.warning(f"⚠️ {result.message}")
        else:
            logger.info(f"ℹ️ {result.message}")
    
    def validate_base64_encoding(self, value: str, field_name: str) -> ValidationResult:
        """Validate base64 encoding of a value"""
        try:
            if not value:
                return ValidationResult(
                    False, 
                    f"{field_name} is empty",
                    auto_fixable=True,
                    fix_action="generate_base64_key"
                )
            
            # Try to decode base64
            decoded = base64.b64decode(value, validate=True)
            
            # Check if decoded length is reasonable for encryption keys (typically 32+ bytes)
            if len(decoded) < 16:
                return ValidationResult(
                    False,
                    f"{field_name} base64 decodes to only {len(decoded)} bytes (expected 16+)",
                    auto_fixable=True,
                    fix_action="generate_base64_key"
                )
            
            return ValidationResult(True, f"{field_name} has valid base64 encoding ({len(decoded)} bytes)")
            
        except Exception as e:
            return ValidationResult(
                False,
                f"{field_name} has invalid base64 encoding: {str(e)}",
                auto_fixable=True,
                fix_action="generate_base64_key"
            )
    
    def validate_json_structure(self, json_str: str, field_name: str, required_keys: List[str] = None) -> ValidationResult:
        """Validate JSON structure and required keys"""
        try:
            data = json.loads(json_str)
            
            if required_keys:
                missing_keys = [key for key in required_keys if key not in data]
                if missing_keys:
                    return ValidationResult(
                        False,
                        f"{field_name} missing required keys: {missing_keys}",
                        auto_fixable=True,
                        fix_action="fix_json_structure"
                    )
            
            return ValidationResult(True, f"{field_name} has valid JSON structure")
            
        except json.JSONDecodeError as e:
            return ValidationResult(
                False,
                f"{field_name} has invalid JSON: {str(e)}",
                auto_fixable=True,
                fix_action="fix_json_structure"
            )
    
    def validate_encryption_keys(self, encryption_keys_str: str) -> ValidationResult:
        """Validate SysReptor encryption keys format and content"""
        try:
            # Parse the encryption keys JSON
            encryption_keys = json.loads(encryption_keys_str)
            
            if not isinstance(encryption_keys, list) or len(encryption_keys) == 0:
                return ValidationResult(
                    False,
                    "ENCRYPTION_KEYS must be a non-empty list",
                    auto_fixable=True,
                    fix_action="generate_encryption_keys"
                )
            
            for i, key_obj in enumerate(encryption_keys):
                # Check required fields
                required_fields = ['id', 'key', 'cipher', 'revoked']
                missing_fields = [field for field in required_fields if field not in key_obj]
                if missing_fields:
                    return ValidationResult(
                        False,
                        f"Encryption key {i} missing fields: {missing_fields}",
                        auto_fixable=True,
                        fix_action="fix_encryption_key_structure"
                    )
                
                # Validate key base64 encoding
                key_validation = self.validate_base64_encoding(key_obj['key'], f"Encryption key {i}")
                if not key_validation.passed:
                    return ValidationResult(
                        False,
                        f"Encryption key {i} has invalid base64: {key_validation.message}",
                        auto_fixable=True,
                        fix_action="regenerate_encryption_key"
                    )
                
                # Check cipher type
                if key_obj['cipher'] != 'AES-GCM':
                    return ValidationResult(
                        False,
                        f"Encryption key {i} has unsupported cipher: {key_obj['cipher']}",
                        severity="warning"
                    )
            
            return ValidationResult(True, f"All {len(encryption_keys)} encryption keys are valid")
            
        except Exception as e:
            return ValidationResult(
                False,
                f"Failed to validate encryption keys: {str(e)}",
                auto_fixable=True,
                fix_action="generate_encryption_keys"
            )
    
    def validate_database_connection(self, host: str, database: str, user: str, password: str, port: int = 5432) -> ValidationResult:
        """Validate database connection parameters"""
        try:
            # Test connection
            conn = psycopg2.connect(
                host=host,
                database=database,
                user=user,
                password=password,
                port=port,
                connect_timeout=5
            )
            conn.close()
            
            return ValidationResult(True, f"Database connection to {host}:{port}/{database} successful")
            
        except psycopg2.OperationalError as e:
            return ValidationResult(
                False,
                f"Database connection failed: {str(e)}",
                auto_fixable=False
            )
        except Exception as e:
            return ValidationResult(
                False,
                f"Database connection error: {str(e)}",
                auto_fixable=False
            )
    
    def validate_redis_connection(self, host: str, port: int = 6379, password: str = None, index: int = 0) -> ValidationResult:
        """Validate Redis connection parameters"""
        try:
            r = redis.Redis(host=host, port=port, password=password, db=index, socket_timeout=5)
            r.ping()
            
            return ValidationResult(True, f"Redis connection to {host}:{port}/{index} successful")
            
        except redis.ConnectionError as e:
            return ValidationResult(
                False,
                f"Redis connection failed: {str(e)}",
                auto_fixable=False
            )
        except Exception as e:
            return ValidationResult(
                False,
                f"Redis connection error: {str(e)}",
                auto_fixable=False
            )
    
    def validate_file_permissions(self, file_path: str, expected_owner: str = "1000:1000", expected_perms: str = "644") -> ValidationResult:
        """Validate file permissions and ownership"""
        try:
            if not os.path.exists(file_path):
                return ValidationResult(
                    False,
                    f"File {file_path} does not exist",
                    auto_fixable=True,
                    fix_action="create_from_template"
                )
            
            # Check ownership
            stat_info = os.stat(file_path)
            actual_owner = f"{stat_info.st_uid}:{stat_info.st_gid}"
            
            if actual_owner != expected_owner:
                return ValidationResult(
                    False,
                    f"File {file_path} has wrong ownership: {actual_owner} (expected {expected_owner})",
                    auto_fixable=True,
                    fix_action="fix_permissions"
                )
            
            # Check permissions
            actual_perms = oct(stat_info.st_mode)[-3:]
            if actual_perms != expected_perms:
                return ValidationResult(
                    False,
                    f"File {file_path} has wrong permissions: {actual_perms} (expected {expected_perms})",
                    auto_fixable=True,
                    fix_action="fix_permissions"
                )
            
            return ValidationResult(True, f"File {file_path} has correct permissions and ownership")
            
        except Exception as e:
            return ValidationResult(
                False,
                f"Error checking permissions for {file_path}: {str(e)}",
                auto_fixable=True,
                fix_action="fix_permissions"
            )
    
    def validate_environment_variables(self, env_vars: Dict[str, str], required_vars: List[str]) -> ValidationResult:
        """Validate required environment variables are present"""
        missing_vars = []
        empty_vars = []
        
        for var in required_vars:
            if var not in env_vars:
                missing_vars.append(var)
            elif not env_vars[var] or env_vars[var].strip() == "":
                empty_vars.append(var)
        
        if missing_vars:
            return ValidationResult(
                False,
                f"Missing required environment variables: {missing_vars}",
                auto_fixable=True,
                fix_action="add_missing_env_vars"
            )
        
        if empty_vars:
            return ValidationResult(
                False,
                f"Empty required environment variables: {empty_vars}",
                auto_fixable=True,
                fix_action="populate_empty_env_vars"
            )
        
        return ValidationResult(True, f"All {len(required_vars)} required environment variables are present")
    
    def validate_sysreptor_configuration(self, config_file: str) -> List[ValidationResult]:
        """Comprehensive SysReptor configuration validation"""
        results = []
        
        if not os.path.exists(config_file):
            results.append(ValidationResult(
                False,
                f"SysReptor config file {config_file} does not exist",
                auto_fixable=True,
                fix_action="create_sysreptor_config"
            ))
            return results
        
        try:
            # Load configuration
            env_vars = {}
            with open(config_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        env_vars[key] = value
            
            # Required variables
            required_vars = [
                'SECRET_KEY', 'DATABASE_HOST', 'DATABASE_NAME', 'DATABASE_USER',
                'DATABASE_PASSWORD', 'REDIS_HOST', 'REDIS_PASSWORD'
            ]
            
            results.append(self.validate_environment_variables(env_vars, required_vars))
            
            # Validate SECRET_KEY
            if 'SECRET_KEY' in env_vars:
                secret_key = env_vars['SECRET_KEY']
                if len(secret_key) < 50:
                    results.append(ValidationResult(
                        False,
                        f"SECRET_KEY is too short ({len(secret_key)} chars, recommended 50+)",
                        severity="warning",
                        auto_fixable=True,
                        fix_action="generate_secret_key"
                    ))
                else:
                    results.append(ValidationResult(True, "SECRET_KEY has adequate length"))
            
            # Validate encryption keys if present
            if 'ENCRYPTION_KEYS' in env_vars:
                results.append(self.validate_encryption_keys(env_vars['ENCRYPTION_KEYS']))
            
            # Validate database connection
            if all(var in env_vars for var in ['DATABASE_HOST', 'DATABASE_NAME', 'DATABASE_USER', 'DATABASE_PASSWORD']):
                port = int(env_vars.get('DATABASE_PORT', 5432))
                results.append(self.validate_database_connection(
                    env_vars['DATABASE_HOST'],
                    env_vars['DATABASE_NAME'],
                    env_vars['DATABASE_USER'],
                    env_vars['DATABASE_PASSWORD'],
                    port
                ))
            
            # Validate Redis connection
            if all(var in env_vars for var in ['REDIS_HOST', 'REDIS_PASSWORD']):
                port = int(env_vars.get('REDIS_PORT', 6379))
                index = int(env_vars.get('REDIS_INDEX', 0))
                results.append(self.validate_redis_connection(
                    env_vars['REDIS_HOST'],
                    port,
                    env_vars['REDIS_PASSWORD'],
                    index
                ))
            
        except Exception as e:
            results.append(ValidationResult(
                False,
                f"Error parsing SysReptor configuration: {str(e)}",
                auto_fixable=True,
                fix_action="repair_config_syntax"
            ))
        
        return results
    
    def validate_kasm_configuration(self) -> List[ValidationResult]:
        """Validate Kasm Workspaces configuration"""
        results = []
        
        # Check if Kasm is installed
        if os.getenv('KASM_INSTALLED') != 'true':
            results.append(ValidationResult(True, "Kasm not installed, skipping validation", severity="info"))
            return results
        
        # Check critical directories
        kasm_dirs = [
            '/opt/kasm/1.15.0/conf',
            '/opt/kasm/1.15.0/log',
            '/opt/kasm/1.15.0/tmp'
        ]
        
        for kasm_dir in kasm_dirs:
            results.append(self.validate_file_permissions(kasm_dir, "1000:1000", "755"))
        
        # Check database connectivity
        try:
            results.append(self.validate_database_connection(
                "kasm_db", "kasm", "kasmapp", "kasmpassword"
            ))
        except Exception as e:
            results.append(ValidationResult(
                False,
                f"Kasm database validation failed: {str(e)}",
                auto_fixable=False
            ))
        
        return results
    
    def validate_empire_configuration(self) -> List[ValidationResult]:
        """Validate Empire configuration"""
        results = []
        
        empire_db = "/opt/empire/data/empire.db"
        if os.path.exists(empire_db):
            results.append(self.validate_file_permissions(empire_db, "1000:1000", "644"))
            results.append(ValidationResult(True, "Empire database file exists"))
        else:
            results.append(ValidationResult(
                False,
                "Empire database file does not exist",
                auto_fixable=True,
                fix_action="initialize_empire_db"
            ))
        
        return results
    
    def run_comprehensive_validation(self) -> Dict[str, Any]:
        """Run comprehensive configuration validation"""
        logger.info("🔍 Starting comprehensive configuration validation...")
        
        self.validation_results = []
        
        # Validate SysReptor
        sysreptor_config = "/opt/rtpi-pen/configs/rtpi-sysreptor/app.env"
        sysreptor_results = self.validate_sysreptor_configuration(sysreptor_config)
        self.validation_results.extend(sysreptor_results)
        
        # Validate Kasm
        kasm_results = self.validate_kasm_configuration()
        self.validation_results.extend(kasm_results)
        
        # Validate Empire
        empire_results = self.validate_empire_configuration()
        self.validation_results.extend(empire_results)
        
        # Summary
        total_checks = len(self.validation_results)
        passed_checks = sum(1 for r in self.validation_results if r.passed)
        failed_checks = total_checks - passed_checks
        auto_fixable = sum(1 for r in self.validation_results if not r.passed and r.auto_fixable)
        
        summary = {
            'total_checks': total_checks,
            'passed_checks': passed_checks,
            'failed_checks': failed_checks,
            'auto_fixable_failures': auto_fixable,
            'validation_results': self.validation_results,
            'overall_status': 'PASS' if failed_checks == 0 else 'FAIL'
        }
        
        logger.info(f"📊 Validation Summary: {passed_checks}/{total_checks} passed, {auto_fixable} auto-fixable failures")
        
        return summary
    
    def generate_validation_report(self, validation_summary: Dict[str, Any]) -> str:
        """Generate a detailed validation report"""
        report_lines = [
            "# RTPI-PEN Configuration Validation Report",
            f"Generated: {datetime.now().isoformat()}",
            "",
            "## Summary",
            f"- Total Checks: {validation_summary['total_checks']}",
            f"- Passed: {validation_summary['passed_checks']}",
            f"- Failed: {validation_summary['failed_checks']}",
            f"- Auto-fixable Failures: {validation_summary['auto_fixable_failures']}",
            f"- Overall Status: {validation_summary['overall_status']}",
            "",
            "## Detailed Results"
        ]
        
        for i, result in enumerate(validation_summary['validation_results'], 1):
            status_icon = "✅" if result.passed else "❌"
            severity_tag = f"[{result.severity.upper()}]" if not result.passed else ""
            auto_fix_tag = "[AUTO-FIXABLE]" if result.auto_fixable else ""
            
            report_lines.append(f"{i}. {status_icon} {severity_tag} {auto_fix_tag} {result.message}")
            
            if result.fix_action:
                report_lines.append(f"   → Fix Action: {result.fix_action}")
        
        return "\n".join(report_lines)

if __name__ == "__main__":
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('/var/log/rtpi-healer/config-validator.log'),
            logging.StreamHandler()
        ]
    )
    
    validator = ConfigurationValidator()
    summary = validator.run_comprehensive_validation()
    
    # Generate and save report
    report = validator.generate_validation_report(summary)
    report_file = f"/tmp/rtpi-config-validation-{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
    
    with open(report_file, 'w') as f:
        f.write(report)
    
    print(f"📄 Configuration validation report saved to: {report_file}")
    
    # Exit with appropriate code
    sys.exit(0 if summary['overall_status'] == 'PASS' else 1)
