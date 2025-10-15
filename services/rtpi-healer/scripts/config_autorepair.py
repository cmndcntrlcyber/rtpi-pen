#!/usr/bin/env python3
"""
RTPI-PEN Configuration Auto-Repair Engine
Automatically fixes configuration issues identified by the validator
"""

import os
import sys
import json
import yaml
import base64
import uuid
import secrets
import logging
import shutil
import subprocess
from datetime import datetime
from typing import Dict, List, Optional, Tuple, Any
from pathlib import Path

from config_validator import ConfigurationValidator, ValidationResult

logger = logging.getLogger('rtpi-config-autorepair')

class ConfigurationAutoRepair:
    """Automatically repairs configuration issues"""
    
    def __init__(self):
        self.validator = ConfigurationValidator()
        self.repair_actions = {
            'generate_base64_key': self._generate_base64_key,
            'generate_encryption_keys': self._generate_encryption_keys,
            'generate_secret_key': self._generate_secret_key,
            'create_sysreptor_config': self._create_sysreptor_config,
            'fix_permissions': self._fix_permissions,
            'create_from_template': self._create_from_template,
            'add_missing_env_vars': self._add_missing_env_vars,
            'populate_empty_env_vars': self._populate_empty_env_vars,
            'repair_config_syntax': self._repair_config_syntax,
            'fix_json_structure': self._fix_json_structure,
            'regenerate_encryption_key': self._regenerate_encryption_key,
            'initialize_empire_db': self._initialize_empire_db
        }
        
        self.config_backups = []
    
    def _backup_config_file(self, config_path: str) -> str:
        """Create a backup of a configuration file"""
        try:
            if not os.path.exists(config_path):
                return None
            
            backup_dir = os.path.dirname(config_path)
            backup_name = f"{os.path.basename(config_path)}.bak.{datetime.now().strftime('%Y%m%d-%H%M%S')}"
            backup_path = os.path.join(backup_dir, backup_name)
            
            shutil.copy2(config_path, backup_path)
            self.config_backups.append(backup_path)
            logger.info(f"📁 Created config backup: {backup_path}")
            
            return backup_path
            
        except Exception as e:
            logger.error(f"Failed to backup {config_path}: {str(e)}")
            return None
    
    def _execute_command(self, command: str, timeout: int = 30) -> Tuple[bool, str]:
        """Execute shell command with timeout"""
        try:
            result = subprocess.run(
                command, shell=True, capture_output=True, 
                text=True, timeout=timeout
            )
            return result.returncode == 0, result.stdout + result.stderr
        except subprocess.TimeoutExpired:
            return False, "Command timed out"
        except Exception as e:
            return False, str(e)
    
    def _generate_base64_key(self, length: int = 32) -> str:
        """Generate a secure base64-encoded key"""
        key_bytes = secrets.token_bytes(length)
        return base64.b64encode(key_bytes).decode('utf-8')
    
    def _generate_secret_key(self, length: int = 64) -> str:
        """Generate a Django-compatible secret key"""
        chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*(-_=+)'
        return ''.join(secrets.choice(chars) for _ in range(length))
    
    def _generate_encryption_keys(self) -> str:
        """Generate SysReptor encryption keys structure"""
        key_id = str(uuid.uuid4())
        key_data = self._generate_base64_key(32)
        
        encryption_keys = [{
            "id": key_id,
            "key": key_data,
            "cipher": "AES-GCM",
            "revoked": False
        }]
        
        return json.dumps(encryption_keys)
    
    def _create_sysreptor_config(self, config_path: str) -> bool:
        """Create a new SysReptor configuration file from template"""
        try:
            template_path = self.validator.config_templates['sysreptor']
            
            if not os.path.exists(template_path):
                logger.error(f"SysReptor template not found: {template_path}")
                return False
            
            # Load template
            with open(template_path, 'r') as f:
                template_content = f.read()
            
            # Generate secure values
            secret_key = self._generate_secret_key()
            encryption_keys = self._generate_encryption_keys()
            key_id = json.loads(encryption_keys)[0]['id']
            
            # Create configuration content
            config_content = f"""# SysReptor Configuration
# Generated automatically by RTPI-PEN Auto-Repair
# Generated: {datetime.now().isoformat()}
# DO NOT EDIT MANUALLY - Configuration managed by self-healing system

# Security Keys
SECRET_KEY={secret_key}

# Database Configuration
DATABASE_HOST=rtpi-database
DATABASE_NAME=sysreptor
DATABASE_USER=sysreptor
DATABASE_PASSWORD=sysreptorpassword
DATABASE_PORT=5432

# Encryption Keys
ENCRYPTION_KEYS={encryption_keys}
DEFAULT_ENCRYPTION_KEY_ID={key_id}

# Security and Access
ALLOWED_HOSTS=sysreptor,0.0.0.0,127.0.0.1,rtpi-pen-dev,localhost
SECURE_SSL_REDIRECT=off
USE_X_FORWARDED_HOST=on
DEBUG=off

# Redis Configuration
REDIS_HOST=sysreptor-redis
REDIS_PORT=6379
REDIS_INDEX=0
REDIS_PASSWORD=sysreptorredispassword

# Features and Plugins
ENABLE_PRIVATE_DESIGNS=true
DISABLE_WEBSOCKETS=true
ENABLED_PLUGINS=cyberchef,graphqlvoyager,checkthehash

# Performance and Scaling
CELERY_BROKER_URL=redis://:sysreptorredispassword@sysreptor-redis:6379/0
CELERY_RESULT_BACKEND=redis://:sysreptorredispassword@sysreptor-redis:6379/0
"""
            
            # Ensure directory exists
            os.makedirs(os.path.dirname(config_path), exist_ok=True)
            
            # Write configuration
            with open(config_path, 'w') as f:
                f.write(config_content)
            
            # Set proper permissions
            self._execute_command(f"chown 1000:1000 {config_path}")
            self._execute_command(f"chmod 644 {config_path}")
            
            logger.info(f"✅ Created new SysReptor configuration: {config_path}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to create SysReptor config: {str(e)}")
            return False
    
    def _fix_permissions(self, file_path: str, owner: str = "1000:1000", perms: str = "644") -> bool:
        """Fix file permissions and ownership"""
        try:
            # Ensure file exists
            if not os.path.exists(file_path):
                # Try to create from template first
                if not self._create_from_template(file_path):
                    return False
            
            # Fix ownership
            success, output = self._execute_command(f"chown {owner} {file_path}")
            if not success:
                logger.error(f"Failed to fix ownership for {file_path}: {output}")
                return False
            
            # Fix permissions
            success, output = self._execute_command(f"chmod {perms} {file_path}")
            if not success:
                logger.error(f"Failed to fix permissions for {file_path}: {output}")
                return False
            
            logger.info(f"✅ Fixed permissions for {file_path} ({owner}, {perms})")
            return True
            
        except Exception as e:
            logger.error(f"Error fixing permissions for {file_path}: {str(e)}")
            return False
    
    def _create_from_template(self, file_path: str) -> bool:
        """Create a file from its template"""
        try:
            # Determine which template to use based on file path
            if 'sysreptor' in file_path and file_path.endswith('.env'):
                return self._create_sysreptor_config(file_path)
            
            # Handle other file types
            logger.warning(f"No template available for {file_path}")
            return False
            
        except Exception as e:
            logger.error(f"Failed to create from template: {str(e)}")
            return False
    
    def _add_missing_env_vars(self, config_path: str, missing_vars: List[str]) -> bool:
        """Add missing environment variables to configuration"""
        try:
            # Default values for common variables
            default_values = {
                'SECRET_KEY': self._generate_secret_key(),
                'DATABASE_HOST': 'rtpi-database',
                'DATABASE_NAME': 'sysreptor',
                'DATABASE_USER': 'sysreptor',
                'DATABASE_PASSWORD': 'sysreptorpassword',
                'DATABASE_PORT': '5432',
                'REDIS_HOST': 'sysreptor-redis',
                'REDIS_PORT': '6379',
                'REDIS_PASSWORD': 'sysreptorredispassword',
                'REDIS_INDEX': '0',
                'ALLOWED_HOSTS': 'sysreptor,0.0.0.0,127.0.0.1,rtpi-pen-dev,localhost',
                'DEBUG': 'off',
                'SECURE_SSL_REDIRECT': 'off'
            }
            
            # Backup configuration
            self._backup_config_file(config_path)
            
            # Read existing configuration
            existing_content = ""
            if os.path.exists(config_path):
                with open(config_path, 'r') as f:
                    existing_content = f.read()
            
            # Add missing variables
            additions = []
            for var in missing_vars:
                if var in default_values:
                    additions.append(f"{var}={default_values[var]}")
                else:
                    logger.warning(f"No default value for {var}, skipping")
            
            if additions:
                if existing_content and not existing_content.endswith('\n'):
                    existing_content += '\n'
                
                existing_content += '\n# Added by auto-repair\n'
                existing_content += '\n'.join(additions) + '\n'
                
                with open(config_path, 'w') as f:
                    f.write(existing_content)
                
                logger.info(f"✅ Added {len(additions)} missing environment variables to {config_path}")
                return True
            
            return False
            
        except Exception as e:
            logger.error(f"Failed to add missing env vars: {str(e)}")
            return False
    
    def _populate_empty_env_vars(self, config_path: str, empty_vars: List[str]) -> bool:
        """Populate empty environment variables"""
        try:
            # Backup configuration
            self._backup_config_file(config_path)
            
            # Load existing configuration
            env_vars = {}
            with open(config_path, 'r') as f:
                lines = f.readlines()
            
            # Default values for common variables
            default_values = {
                'SECRET_KEY': self._generate_secret_key(),
                'ENCRYPTION_KEYS': self._generate_encryption_keys(),
                'DATABASE_HOST': 'rtpi-database',
                'DATABASE_NAME': 'sysreptor',
                'DATABASE_USER': 'sysreptor',
                'DATABASE_PASSWORD': 'sysreptorpassword',
                'REDIS_HOST': 'sysreptor-redis',
                'REDIS_PASSWORD': 'sysreptorredispassword'
            }
            
            # Update lines with populated values
            updated_lines = []
            for line in lines:
                if '=' in line and not line.strip().startswith('#'):
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()
                    
                    if key in empty_vars and (not value or value == '""' or value == "''"):
                        if key in default_values:
                            updated_lines.append(f"{key}={default_values[key]}\n")
                            logger.info(f"✅ Populated empty variable: {key}")
                        else:
                            updated_lines.append(line)
                    else:
                        updated_lines.append(line)
                else:
                    updated_lines.append(line)
            
            # Write updated configuration
            with open(config_path, 'w') as f:
                f.writelines(updated_lines)
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to populate empty env vars: {str(e)}")
            return False
    
    def _repair_config_syntax(self, config_path: str) -> bool:
        """Repair configuration file syntax issues"""
        try:
            # Backup configuration
            self._backup_config_file(config_path)
            
            if config_path.endswith('.env'):
                return self._repair_env_file_syntax(config_path)
            elif config_path.endswith(('.yaml', '.yml')):
                return self._repair_yaml_file_syntax(config_path)
            else:
                logger.warning(f"Unknown config file type: {config_path}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to repair config syntax: {str(e)}")
            return False
    
    def _repair_env_file_syntax(self, config_path: str) -> bool:
        """Repair .env file syntax issues"""
        try:
            with open(config_path, 'r') as f:
                lines = f.readlines()
            
            repaired_lines = []
            for line_num, line in enumerate(lines, 1):
                original_line = line
                line = line.strip()
                
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    repaired_lines.append(original_line)
                    continue
                
                # Fix lines with = but no proper key=value format
                if '=' in line:
                    parts = line.split('=', 1)
                    key = parts[0].strip()
                    value = parts[1].strip() if len(parts) > 1 else ""
                    
                    # Remove quotes if they're unmatched
                    if value.startswith('"') and not value.endswith('"'):
                        value = value[1:]
                    elif value.startswith("'") and not value.endswith("'"):
                        value = value[1:]
                    
                    repaired_lines.append(f"{key}={value}\n")
                else:
                    # Line without =, treat as comment
                    repaired_lines.append(f"# {line}\n")
            
            # Write repaired configuration
            with open(config_path, 'w') as f:
                f.writelines(repaired_lines)
            
            logger.info(f"✅ Repaired syntax for {config_path}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to repair env file syntax: {str(e)}")
            return False
    
    def _repair_yaml_file_syntax(self, config_path: str) -> bool:
        """Repair YAML file syntax issues"""
        try:
            with open(config_path, 'r') as f:
                content = f.read()
            
            # Try to parse and rewrite YAML
            try:
                data = yaml.safe_load(content)
                with open(config_path, 'w') as f:
                    yaml.dump(data, f, default_flow_style=False)
                
                logger.info(f"✅ Repaired YAML syntax for {config_path}")
                return True
                
            except yaml.YAMLError as e:
                logger.error(f"Could not parse YAML file {config_path}: {str(e)}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to repair YAML file syntax: {str(e)}")
            return False
    
    def _fix_json_structure(self, config_path: str, field_name: str) -> bool:
        """Fix JSON structure issues in configuration fields"""
        try:
            # This is typically called for specific fields like ENCRYPTION_KEYS
            if field_name == "ENCRYPTION_KEYS":
                return self._fix_encryption_keys_json(config_path)
            
            logger.warning(f"No specific JSON fix available for {field_name}")
            return False
            
        except Exception as e:
            logger.error(f"Failed to fix JSON structure: {str(e)}")
            return False
    
    def _fix_encryption_keys_json(self, config_path: str) -> bool:
        """Fix encryption keys JSON structure"""
        try:
            # Backup configuration
            self._backup_config_file(config_path)
            
            # Generate new encryption keys
            new_encryption_keys = self._generate_encryption_keys()
            key_id = json.loads(new_encryption_keys)[0]['id']
            
            # Update configuration file
            with open(config_path, 'r') as f:
                lines = f.readlines()
            
            updated_lines = []
            for line in lines:
                if line.startswith('ENCRYPTION_KEYS='):
                    updated_lines.append(f"ENCRYPTION_KEYS={new_encryption_keys}\n")
                elif line.startswith('DEFAULT_ENCRYPTION_KEY_ID='):
                    updated_lines.append(f"DEFAULT_ENCRYPTION_KEY_ID={key_id}\n")
                else:
                    updated_lines.append(line)
            
            # Add DEFAULT_ENCRYPTION_KEY_ID if not present
            has_default_key_id = any(line.startswith('DEFAULT_ENCRYPTION_KEY_ID=') for line in updated_lines)
            if not has_default_key_id:
                updated_lines.append(f"DEFAULT_ENCRYPTION_KEY_ID={key_id}\n")
            
            with open(config_path, 'w') as f:
                f.writelines(updated_lines)
            
            logger.info(f"✅ Fixed encryption keys JSON structure in {config_path}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to fix encryption keys JSON: {str(e)}")
            return False
    
    def _regenerate_encryption_key(self, config_path: str) -> bool:
        """Regenerate a corrupted encryption key"""
        return self._fix_encryption_keys_json(config_path)
    
    def _initialize_empire_db(self, db_path: str) -> bool:
        """Initialize Empire database"""
        try:
            # Ensure directory exists
            os.makedirs(os.path.dirname(db_path), exist_ok=True)
            
            # Create empty database file
            with open(db_path, 'w') as f:
                f.write("")
            
            # Set proper permissions
            self._execute_command(f"chown 1000:1000 {db_path}")
            self._execute_command(f"chmod 644 {db_path}")
            
            logger.info(f"✅ Initialized Empire database: {db_path}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize Empire database: {str(e)}")
            return False
    
    def repair_validation_failures(self, validation_results: List[ValidationResult]) -> Dict[str, Any]:
        """Automatically repair validation failures"""
        logger.info("🔧 Starting automatic configuration repair...")
        
        repair_summary = {
            'total_failures': 0,
            'attempted_repairs': 0,
            'successful_repairs': 0,
            'failed_repairs': 0,
            'repair_details': []
        }
        
        for result in validation_results:
            if not result.passed and result.auto_fixable and result.fix_action:
                repair_summary['total_failures'] += 1
                
                if result.fix_action in self.repair_actions:
                    repair_summary['attempted_repairs'] += 1
                    
                    logger.info(f"🔧 Attempting repair: {result.fix_action} for '{result.message}'")
                    
                    try:
                        repair_func = self.repair_actions[result.fix_action]
                        
                        # Call repair function with appropriate parameters
                        if result.fix_action in ['create_sysreptor_config']:
                            # These functions need a file path
                            config_path = "/opt/rtpi-pen/configs/rtpi-sysreptor/app.env"
                            success = repair_func(config_path)
                        elif result.fix_action in ['fix_permissions']:
                            # Extract file path from message
                            import re
                            path_match = re.search(r'File (.*?) has', result.message)
                            if path_match:
                                file_path = path_match.group(1)
                                success = repair_func(file_path)
                            else:
                                success = False
                        elif result.fix_action in ['add_missing_env_vars', 'populate_empty_env_vars']:
                            # These need config path and variable list
                            config_path = "/opt/rtpi-pen/configs/rtpi-sysreptor/app.env"
                            # Extract variables from message
                            import re
                            vars_match = re.search(r'variables: \[(.*?)\]', result.message)
                            if vars_match:
                                vars_str = vars_match.group(1)
                                variables = [v.strip().strip("'\"") for v in vars_str.split(',')]
                                success = repair_func(config_path, variables)
                            else:
                                success = False
                        else:
                            # Generic repair functions
                            success = repair_func()
                        
                        if success:
                            repair_summary['successful_repairs'] += 1
                            repair_summary['repair_details'].append({
                                'action': result.fix_action,
                                'message': result.message,
                                'status': 'SUCCESS'
                            })
                            logger.info(f"✅ Successfully repaired: {result.fix_action}")
                        else:
                            repair_summary['failed_repairs'] += 1
                            repair_summary['repair_details'].append({
                                'action': result.fix_action,
                                'message': result.message,
                                'status': 'FAILED'
                            })
                            logger.error(f"❌ Failed to repair: {result.fix_action}")
                    
                    except Exception as e:
                        repair_summary['failed_repairs'] += 1
                        repair_summary['repair_details'].append({
                            'action': result.fix_action,
                            'message': result.message,
                            'status': 'ERROR',
                            'error': str(e)
                        })
                        logger.error(f"❌ Error during repair {result.fix_action}: {str(e)}")
                
                else:
                    logger.warning(f"⚠️ No repair action available for: {result.fix_action}")
        
        logger.info(f"🔧 Repair Summary: {repair_summary['successful_repairs']}/{repair_summary['attempted_repairs']} successful")
        
        return repair_summary
    
    def run_repair_cycle(self) -> Dict[str, Any]:
        """Run a complete validation and repair cycle"""
        logger.info("🔄 Starting validation and repair cycle...")
        
        # Run validation
        validation_summary = self.validator.run_comprehensive_validation()
        
        # Perform repairs if needed
        repair_summary = None
        if validation_summary['failed_checks'] > 0:
            repair_summary = self.repair_validation_failures(validation_summary['validation_results'])
            
            # Re-run validation to check if repairs were successful
            logger.info("🔍 Re-running validation after repairs...")
            post_repair_validation = self.validator.run_comprehensive_validation()
            
            return {
                'initial_validation': validation_summary,
                'repairs_performed': repair_summary,
                'post_repair_validation': post_repair_validation,
                'overall_success': post_repair_validation['overall_status'] == 'PASS'
           }
        else:
            logger.info("✅ No repairs needed - all validations passed")
            return {
                'initial_validation': validation_summary,
                'repairs_performed': None,
                'post_repair_validation': validation_summary,
                'overall_success': True
            }

if __name__ == "__main__":
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('/var/log/rtpi-healer/config-autorepair.log'),
            logging.StreamHandler()
        ]
    )
    
    autorepair = ConfigurationAutoRepair()
    result = autorepair.run_repair_cycle()
    
    # Generate report
    report_file = f"/tmp/rtpi-config-repair-{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(report_file, 'w') as f:
        json.dump(result, f, indent=2, default=str)
    
    print(f"📄 Repair report saved to: {report_file}")
    print(f"🔧 Overall Success: {'✅' if result['overall_success'] else '❌'}")
    
    # Exit with appropriate code
    sys.exit(0 if result['overall_success'] else 1)
