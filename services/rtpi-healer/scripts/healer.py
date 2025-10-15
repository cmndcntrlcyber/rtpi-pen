#!/usr/bin/env python3
"""
RTPI-PEN Self-Healing Service
Monitors and auto-repairs container issues
"""

import os
import sys
import time
import json
import logging
import schedule
import subprocess
import threading
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple

import docker
import requests
import psutil
import redis
import psycopg2
import yaml
from http.server import HTTPServer, BaseHTTPRequestHandler

# Import enhanced configuration validation and repair
from config_validator import ConfigurationValidator
from config_autorepair import ConfigurationAutoRepair

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/rtpi-healer/healer.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('rtpi-healer')

class ContainerFailureTracker:
    """Tracks container failures and restart patterns"""
    def __init__(self):
        self.failures = {}
        self.restart_counts = {}
        self.last_restart_time = {}
        self.backoff_multipliers = {}
    
    def record_failure(self, container_name: str, failure_type: str):
        """Record a container failure"""
        key = f"{container_name}:{failure_type}"
        if key not in self.failures:
            self.failures[key] = []
        self.failures[key].append(datetime.now())
        
        # Clean old failures (older than 1 hour)
        hour_ago = datetime.now() - timedelta(hours=1)
        self.failures[key] = [f for f in self.failures[key] if f > hour_ago]
    
    def get_failure_count(self, container_name: str, failure_type: str) -> int:
        """Get failure count for a container/type in the last hour"""
        key = f"{container_name}:{failure_type}"
        return len(self.failures.get(key, []))
    
    def should_restart(self, container_name: str) -> bool:
        """Determine if container should be restarted based on backoff"""
        if container_name not in self.last_restart_time:
            return True
        
        backoff = self.backoff_multipliers.get(container_name, 1)
        min_wait = min(300, backoff * 30)  # Max 5 minutes
        
        time_since_last = (datetime.now() - self.last_restart_time[container_name]).total_seconds()
        return time_since_last >= min_wait
    
    def record_restart(self, container_name: str):
        """Record a container restart"""
        self.last_restart_time[container_name] = datetime.now()
        self.restart_counts[container_name] = self.restart_counts.get(container_name, 0) + 1
        self.backoff_multipliers[container_name] = min(8, self.backoff_multipliers.get(container_name, 1) * 2)

class RTHealerService:
    """Main self-healing service"""
    
    def __init__(self):
        self.docker_client = docker.from_env()
        self.failure_tracker = ContainerFailureTracker()
        self.running = True
        self.healing_actions = 0
        self.last_check_time = datetime.now()
        
        # Enhanced configuration validation and repair
        self.config_validator = ConfigurationValidator()
        self.config_autorepair = ConfigurationAutoRepair()
        self.last_config_validation = None
        
        # Container-specific healing strategies (containerized services only)
        self.healing_strategies = {
            'sysreptor-app': self._heal_sysreptor_app,
            'rtpi-orchestrator': self._heal_rtpi_orchestrator,
        }
    
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
    
    def _ensure_directory_permissions(self, path: str, uid: int = 1000, gid: int = 1000):
        """Ensure directory exists with correct permissions"""
        success, output = self._execute_command(f"mkdir -p {path}")
        if success:
            success, output = self._execute_command(f"chown -R {uid}:{gid} {path}")
            if success:
                success, output = self._execute_command(f"chmod -R 755 {path}")
        return success, output
    
    def _heal_kasm_guac(self, container) -> bool:
        """Heal kasm_guac container - primarily npm permission issues"""
        logger.info("Healing kasm_guac container...")
        
        # Fix npm cache permissions
        npm_paths = [
            "/opt/kasm/1.15.0/tmp/guac/.npm",
            "/opt/kasm/1.15.0/tmp/guac",
            "/opt/kasm/current/tmp/guac/.npm",
            "/opt/kasm/current/tmp/guac"
        ]
        
        for path in npm_paths:
            success, output = self._ensure_directory_permissions(path, 1000, 1000)
            if not success:
                logger.error(f"Failed to fix permissions for {path}: {output}")
                return False
        
        # Clear npm cache
        success, output = self._execute_command(
            "docker exec -u 1000 kasm_guac npm cache clean --force 2>/dev/null || true"
        )
        
        logger.info("kasm_guac healing completed")
        return True
    
    def _heal_kasm_agent(self, container) -> bool:
        """Heal kasm_agent container - missing config files"""
        logger.info("Healing kasm_agent container...")
        
        config_dir = "/opt/kasm/1.15.0/conf/app"
        config_file = f"{config_dir}/agent.app.config.yaml"
        
        # Ensure config directory exists
        success, output = self._ensure_directory_permissions(config_dir, 1000, 1000)
        if not success:
            logger.error(f"Failed to create config directory: {output}")
            return False
        
        # Create agent config if missing
        if not os.path.exists(config_file):
            agent_config = {
                'agent': {
                    'public_hostname': 'localhost',
                    'listen_port': 443,
                    'api_hostname': 'kasm_api',
                    'api_port': 8080,
                    'api_ssl': False,
                    'auto_scaling': {
                        'enabled': False
                    }
                }
            }
            
            try:
                with open(config_file, 'w') as f:
                    yaml.dump(agent_config, f)
                
                success, output = self._execute_command(f"chown 1000:1000 {config_file}")
                if not success:
                    logger.error(f"Failed to set config file permissions: {output}")
                    return False
                    
                logger.info(f"Created agent config: {config_file}")
            except Exception as e:
                logger.error(f"Failed to create agent config: {e}")
                return False
        
        return True
    
    def _heal_kasm_db(self, container) -> bool:
        """Heal kasm_db container - PostgreSQL config issues"""
        logger.info("Healing kasm_db container...")
        
        config_dir = "/opt/kasm/1.15.0/conf/database"
        success, output = self._ensure_directory_permissions(config_dir, 1000, 1000)
        if not success:
            logger.error(f"Failed to create database config directory: {output}")
            return False
        
        # Recreate postgresql.conf with proper format
        postgresql_conf = f"{config_dir}/postgresql.conf"
        pg_config = """# PostgreSQL Configuration for Kasm
# Generated by RTPI-PEN Self-Healing Service

# Connection settings
listen_addresses = '*'
port = 5432
max_connections = 100

# Memory settings
shared_buffers = 128MB
effective_cache_size = 512MB
work_mem = 4MB
maintenance_work_mem = 64MB

# WAL settings
wal_level = minimal
checkpoint_completion_target = 0.9

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = '/var/log/postgres'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_line_prefix = '%t [%p-%l] %q%u@%d '

# Authentication
password_encryption = md5
"""
        
        try:
            with open(postgresql_conf, 'w') as f:
                f.write(pg_config)
            
            success, output = self._execute_command(f"chown 1000:1000 {postgresql_conf}")
            if not success:
                logger.error(f"Failed to set PostgreSQL config permissions: {output}")
                return False
                
            logger.info("Recreated PostgreSQL configuration")
        except Exception as e:
            logger.error(f"Failed to create PostgreSQL config: {e}")
            return False
        
        return True
    
    def _heal_sysreptor_app(self, container) -> bool:
        """Heal sysreptor-app container - database connection issues"""
        logger.info("Healing sysreptor-app container...")
        
        # Test database connectivity
        try:
            conn = psycopg2.connect(
                host="sysreptor-db",
                database="sysreptor",
                user="sysreptor",
                password="sysreptorpassword",
                port=5432,
                connect_timeout=5
            )
            conn.close()
            logger.info("Database connectivity verified")
        except Exception as e:
            logger.error(f"Database connectivity issue: {e}")
            return False
        
        # Check if environment variables are properly set
        env_vars = {
            'POSTGRES_HOST': 'sysreptor-db',
            'POSTGRES_NAME': 'sysreptor',
            'POSTGRES_USER': 'sysreptor',
            'POSTGRES_PASSWORD': 'sysreptorpassword',
            'POSTGRES_PORT': '5432'
        }
        
        # Update container environment if needed
        try:
            container.reload()
            current_env = container.attrs['Config']['Env']
            env_dict = {item.split('=')[0]: item.split('=')[1] for item in current_env if '=' in item}
            
            needs_update = False
            for key, value in env_vars.items():
                if key not in env_dict or env_dict[key] != value:
                    needs_update = True
                    break
            
            if needs_update:
                logger.info("Environment variables need updating - container restart required")
                return False  # Will trigger restart with proper env
                
        except Exception as e:
            logger.error(f"Failed to check environment variables: {e}")
            return False
        
        return True
    
    def _heal_rtpi_orchestrator(self, container) -> bool:
        """Heal rtpi-orchestrator container - permission issues"""
        logger.info("Healing rtpi-orchestrator container...")
        
        data_dirs = [
            "/opt/rtpi-orchestrator/data",
            "/opt/rtpi-orchestrator/data/certs",
            "/opt/rtpi-orchestrator/data/portainer"
        ]
        
        for data_dir in data_dirs:
            success, output = self._ensure_directory_permissions(data_dir, 1000, 1000)
            if not success:
                logger.error(f"Failed to create data directory {data_dir}: {output}")
                return False
        
        logger.info("rtpi-orchestrator healing completed")
        return True
    
    def _heal_kasm_api(self, container) -> bool:
        """Heal kasm_api container"""
        logger.info("Healing kasm_api container...")
        
        # Ensure tmp directory exists with correct permissions
        tmp_dir = "/opt/kasm/1.15.0/tmp/api"
        success, output = self._ensure_directory_permissions(tmp_dir, 1000, 1000)
        if not success:
            logger.error(f"Failed to create API tmp directory: {output}")
            return False
        
        return True
    
    def _heal_kasm_manager(self, container) -> bool:
        """Heal kasm_manager container"""
        logger.info("Healing kasm_manager container...")
        
        # Ensure log directory exists
        log_dir = "/opt/kasm/1.15.0/log"
        success, output = self._ensure_directory_permissions(log_dir, 1000, 1000)
        if not success:
            logger.error(f"Failed to create manager log directory: {output}")
            return False
        
        return True
    
    def _heal_kasm_share(self, container) -> bool:
        """Heal kasm_share container"""
        logger.info("Healing kasm_share container...")
        
        # Ensure share directory exists
        share_dir = "/opt/kasm/1.15.0/share"
        success, output = self._ensure_directory_permissions(share_dir, 1000, 1000)
        if not success:
            logger.error(f"Failed to create share directory: {output}")
            return False
        
        return True
    
    def check_kasm_health(self) -> bool:
        """Check Kasm Workspaces health - Native installation only"""
        try:
            # Check if native Kasm installation is running
            if os.getenv('KASM_INSTALLED') == 'true':
                # Check systemctl status for native Kasm
                try:
                    result = subprocess.run(['systemctl', 'is-active', 'kasm'], 
                                          capture_output=True, text=True, timeout=10)
                    if result.returncode == 0 and result.stdout.strip() == 'active':
                        logger.info("✅ Native Kasm service is active")
                        
                        # Check Kasm API endpoint
                        try:
                            response = requests.get('https://localhost:8443/api/public/get_token', 
                                                  verify=False, timeout=10)
                            if response.status_code == 200:
                                logger.info("✅ Kasm Workspaces API is healthy")
                                return True
                        except requests.RequestException as e:
                            logger.warning(f"Kasm API check failed: {e}")
                            # Try to restart Kasm service
                            self._restart_native_kasm()
                            return False
                    else:
                        logger.warning(f"Native Kasm service is not active: {result.stdout.strip()}")
                        # Try to restart Kasm service
                        self._restart_native_kasm()
                        return False
                except subprocess.TimeoutExpired:
                    logger.warning("Kasm systemctl check timed out")
                    return False
                except Exception as e:
                    logger.warning(f"Error checking native Kasm service: {e}")
                    return False
            else:
                logger.info("Kasm not installed or running in legacy mode")
                return True  # Don't fail if Kasm is not configured
                    
        except Exception as e:
            logger.error(f"Error checking Kasm health: {e}")
            return False
    
    def _restart_native_kasm(self):
        """Restart native Kasm service"""
        try:
            logger.info("Attempting to restart native Kasm service...")
            result = subprocess.run(['systemctl', 'restart', 'kasm'], 
                                  capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                logger.info("✅ Native Kasm service restarted successfully")
                time.sleep(10)  # Wait for service to stabilize
            else:
                logger.error(f"Failed to restart Kasm service: {result.stderr}")
        except Exception as e:
            logger.error(f"Error restarting native Kasm service: {e}")
    
    def _get_container_status(self, container_name: str) -> Dict:
        """Get detailed container status"""
        try:
            container = self.docker_client.containers.get(container_name)
            return {
                'name': container.name,
                'status': container.status,
                'health': container.attrs.get('State', {}).get('Health', {}).get('Status', 'unknown'),
                'restart_count': container.attrs.get('RestartCount', 0),
                'exit_code': container.attrs.get('State', {}).get('ExitCode', 0),
                'started_at': container.attrs.get('State', {}).get('StartedAt', ''),
                'finished_at': container.attrs.get('State', {}).get('FinishedAt', '')
            }
        except docker.errors.NotFound:
            return {'name': container_name, 'status': 'not_found'}
        except Exception as e:
            logger.error(f"Error getting container status for {container_name}: {e}")
            return {'name': container_name, 'status': 'error', 'error': str(e)}
    
    def _restart_container(self, container_name: str) -> bool:
        """Restart a container with proper error handling and pre-startup validation"""
        try:
            container = self.docker_client.containers.get(container_name)
            
            if not self.failure_tracker.should_restart(container_name):
                logger.info(f"Container {container_name} in backoff period, skipping restart")
                return False
            
            # Perform pre-startup validation
            if not self._perform_prestart_validation(container_name):
                logger.error(f"Pre-startup validation failed for {container_name}, aborting restart")
                return False
            
            logger.info(f"Restarting container: {container_name}")
            container.restart()
            
            self.failure_tracker.record_restart(container_name)
            self.healing_actions += 1
            
            # Wait for container to stabilize
            time.sleep(10)
            
            # Check if restart was successful
            container.reload()
            if container.status == 'running':
                logger.info(f"Container {container_name} restarted successfully")
                return True
            else:
                logger.error(f"Container {container_name} failed to start after restart")
                return False
                
        except Exception as e:
            logger.error(f"Failed to restart container {container_name}: {e}")
            return False
    
    def _monitor_containers(self):
        """Monitor all containers and apply healing strategies"""
        try:
            containers = self.docker_client.containers.list(all=True)
            
            for container in containers:
                container_name = container.name
                
                # Skip our own container
                if container_name == 'rtpi-healer':
                    continue
                
                status = self._get_container_status(container_name)
                
                # Check if container is in restart loop
                if status['status'] in ['restarting', 'exited']:
                    restart_count = status.get('restart_count', 0)
                    
                    if restart_count > 3:  # Container has restarted multiple times
                        logger.warning(f"Container {container_name} in restart loop (count: {restart_count})")
                        self.failure_tracker.record_failure(container_name, 'restart_loop')
                        
                        # Apply container-specific healing strategy
                        if container_name in self.healing_strategies:
                            healing_func = self.healing_strategies[container_name]
                            try:
                                if healing_func(container):
                                    logger.info(f"Applied healing strategy for {container_name}")
                                    self._restart_container(container_name)
                                else:
                                    logger.error(f"Healing strategy failed for {container_name}")
                            except Exception as e:
                                logger.error(f"Error applying healing strategy for {container_name}: {e}")
                        else:
                            # Generic healing approach
                            logger.info(f"Applying generic healing for {container_name}")
                            self._restart_container(container_name)
                
                # Check container health
                if status.get('health') == 'unhealthy':
                    logger.warning(f"Container {container_name} is unhealthy")
                    self.failure_tracker.record_failure(container_name, 'unhealthy')
                    
                    # Apply healing strategy
                    if container_name in self.healing_strategies:
                        healing_func = self.healing_strategies[container_name]
                        try:
                            healing_func(container)
                        except Exception as e:
                            logger.error(f"Error healing unhealthy container {container_name}: {e}")
                
        except Exception as e:
            logger.error(f"Error monitoring containers: {e}")
    
    def _cleanup_logs(self):
        """Clean up old log files"""
        try:
            # Clean logs older than 7 days
            success, output = self._execute_command(
                "find /var/log/rtpi-healer -name '*.log' -mtime +7 -delete"
            )
            if success:
                logger.info("Log cleanup completed")
            else:
                logger.error(f"Log cleanup failed: {output}")
        except Exception as e:
            logger.error(f"Error during log cleanup: {e}")
    
    def _validate_configurations(self):
        """Proactively validate all service configurations"""
        try:
            logger.info("🔍 Starting proactive configuration validation...")
            
            # Run comprehensive validation
            validation_summary = self.config_validator.run_comprehensive_validation()
            self.last_config_validation = validation_summary
            
            # Check if any configurations failed validation
            if validation_summary['failed_checks'] > 0:
                logger.warning(f"⚠️ Configuration validation found {validation_summary['failed_checks']} issues")
                
                # Attempt automatic repairs
                logger.info("🔧 Attempting automatic configuration repair...")
                repair_result = self.config_autorepair.run_repair_cycle()
                
                if repair_result['overall_success']:
                    logger.info("✅ Configuration issues automatically resolved")
                    self.healing_actions += repair_result['repairs_performed']['successful_repairs'] if repair_result['repairs_performed'] else 0
                else:
                    logger.error("❌ Some configuration issues could not be automatically resolved")
                    
                    # Log details of failed repairs
                    if repair_result['repairs_performed']:
                        for detail in repair_result['repairs_performed']['repair_details']:
                            if detail['status'] != 'SUCCESS':
                                logger.error(f"Failed repair: {detail['action']} - {detail['message']}")
            else:
                logger.info("✅ All configuration validations passed")
                
        except Exception as e:
            logger.error(f"Error during configuration validation: {e}")
    
    def _perform_prestart_validation(self, container_name: str) -> bool:
        """Perform pre-startup configuration validation for specific containers"""
        try:
            logger.info(f"🔍 Pre-startup validation for {container_name}")
            
            # Container-specific validation
            if container_name == 'sysreptor-app':
                sysreptor_config = "/opt/rtpi-pen/configs/rtpi-sysreptor/app.env"
                validation_results = self.config_validator.validate_sysreptor_configuration(sysreptor_config)
                
                failed_validations = [r for r in validation_results if not r.passed]
                if failed_validations:
                    logger.warning(f"⚠️ SysReptor configuration issues detected, attempting repair...")
                    
                    # Attempt repairs
                    repair_summary = self.config_autorepair.repair_validation_failures(failed_validations)
                    
                    if repair_summary['successful_repairs'] > 0:
                        logger.info(f"✅ Repaired {repair_summary['successful_repairs']} SysReptor configuration issues")
                        return True
                    else:
                        logger.error("❌ Could not repair SysReptor configuration issues")
                        return False
                else:
                    logger.info("✅ SysReptor configuration validation passed")
                    return True
            
            # Add other container-specific validations as needed
            return True
            
        except Exception as e:
            logger.error(f"Error during pre-startup validation for {container_name}: {e}")
            return False
    
    def _backup_configurations(self):
        """Backup critical configurations"""
        try:
            backup_dir = f"/data/backups/{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            success, output = self._execute_command(f"mkdir -p {backup_dir}")
            if not success:
                logger.error(f"Failed to create backup directory: {output}")
                return
            
            # Backup critical configs
            configs_to_backup = [
                "/opt/kasm/1.17.0/conf",
                "/opt/rtpi-pen/configs",
                "/opt/rtpi-pen/docker-compose.yml"
            ]
            
            for config_path in configs_to_backup:
                if os.path.exists(config_path):
                    success, output = self._execute_command(
                        f"cp -r {config_path} {backup_dir}/"
                    )
                    if not success:
                        logger.error(f"Failed to backup {config_path}: {output}")
            
            logger.info(f"Configuration backup completed: {backup_dir}")
            
        except Exception as e:
            logger.error(f"Error during configuration backup: {e}")
    
    def get_status(self) -> Dict:
        """Get healer service status"""
        return {
            'status': 'running' if self.running else 'stopped',
            'healing_actions': self.healing_actions,
            'last_check': self.last_check_time.isoformat(),
            'uptime': (datetime.now() - self.last_check_time).total_seconds()
        }
    
    def run(self):
        """Main service loop"""
        logger.info("Starting RTPI-PEN Self-Healing Service")
        
        # Schedule periodic tasks
        schedule.every(30).seconds.do(self._monitor_containers)
        schedule.every(30).minutes.do(self._validate_configurations)  # Proactive config validation
        schedule.every(1).hours.do(self._cleanup_logs)
        schedule.every(6).hours.do(self._backup_configurations)
        
        # Start HTTP server for health checks
        def start_http_server():
            class HealthHandler(BaseHTTPRequestHandler):
                def do_GET(self):
                    if self.path == '/health':
                        self.send_response(200)
                        self.send_header('Content-type', 'application/json')
                        self.end_headers()
                        self.wfile.write(json.dumps(self.server.healer.get_status()).encode())
                    else:
                        self.send_response(404)
                        self.end_headers()
                
                def log_message(self, format, *args):
                    pass  # Suppress HTTP log messages
            
            server = HTTPServer(('', 8888), HealthHandler)
            server.healer = self
            server.serve_forever()
        
        http_thread = threading.Thread(target=start_http_server, daemon=True)
        http_thread.start()
        
        try:
            while self.running:
                schedule.run_pending()
                time.sleep(1)
                self.last_check_time = datetime.now()
        except KeyboardInterrupt:
            logger.info("Received shutdown signal")
            self.running = False
        except Exception as e:
            logger.error(f"Error in main loop: {e}")
            self.running = False

if __name__ == "__main__":
    healer = RTHealerService()
    healer.run()
