#!/usr/bin/env python3
"""
RTPI-PEN Orchestration Service
Manages container lifecycle, service dependencies, and integrates with Portainer
"""

import os
import sys
import time
import json
import logging
import requests
import threading
import subprocess
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from flask import Flask, jsonify, request
from concurrent.futures import ThreadPoolExecutor, as_completed

import docker
import schedule
import yaml
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/rtpi/orchestrator.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('rtpi-orchestrator')

class ServiceDependencyManager:
    """Manages service dependencies and startup order"""
    
    def __init__(self):
        self.dependencies = {
            'rtpi-database': [],
            'rtpi-cache': [],
            'rtpi-healer': ['rtpi-database', 'rtpi-cache'],
            'rtpi-proxy': ['rtpi-database'],
            'rtpi-tools': ['rtpi-database'],
            'sysreptor-db': [],
            'sysreptor-app': ['sysreptor-db'],
        }
        
        self.startup_order = [
            'rtpi-database',
            'rtpi-cache',
            'sysreptor-db',
            'rtpi-healer',
            'rtpi-proxy',
            'rtpi-tools',
            'sysreptor-app'
        ]
    
    def get_startup_order(self) -> List[str]:
        """Get the correct startup order for services"""
        return self.startup_order
    
    def get_dependencies(self, service_name: str) -> List[str]:
        """Get dependencies for a service"""
        return self.dependencies.get(service_name, [])
    
    def can_start_service(self, service_name: str, running_services: List[str]) -> bool:
        """Check if service can be started based on dependencies"""
        deps = self.get_dependencies(service_name)
        return all(dep in running_services for dep in deps)

class ContainerOrchestrator:
    """Main container orchestration service"""
    
    def __init__(self):
        self.docker_client = docker.from_env()
        self.dependency_manager = ServiceDependencyManager()
        self.running = True
        self.orchestration_actions = 0
        self.last_health_check = datetime.now()
        
        # Portainer configuration
        self.portainer_url = "http://localhost:9000"
        self.portainer_token = None
        
        # Flask app for API endpoints
        self.app = Flask(__name__)
        self.setup_api_routes()
        
        # Service health tracking
        self.service_health = {}
        self.health_check_interval = 30  # seconds
        
        # Backup configuration
        self.backup_enabled = True
        self.backup_retention_days = 7
        
        # Auto-scaling configuration
        self.scaling_enabled = True
        self.scaling_thresholds = {
            'cpu_percent': 80,
            'memory_percent': 85,
            'response_time_ms': 2000
        }
    
    def setup_api_routes(self):
        """Setup Flask API routes"""
        
        @self.app.route('/health', methods=['GET'])
        def health_check():
            return jsonify({
                'status': 'healthy',
                'uptime': (datetime.now() - self.last_health_check).total_seconds(),
                'orchestration_actions': self.orchestration_actions,
                'service_health': self.service_health
            })
        
        @self.app.route('/services', methods=['GET'])
        def list_services():
            return jsonify(self.get_service_status())
        
        @self.app.route('/services/<service_name>/restart', methods=['POST'])
        def restart_service(service_name):
            success = self.restart_service(service_name)
            return jsonify({'success': success})
        
        @self.app.route('/services/<service_name>/scale', methods=['POST'])
        def scale_service(service_name):
            replicas = request.json.get('replicas', 1)
            success = self.scale_service(service_name, replicas)
            return jsonify({'success': success})
        
        @self.app.route('/backup/create', methods=['POST'])
        def create_backup():
            backup_id = self.create_backup()
            return jsonify({'backup_id': backup_id})
        
        @self.app.route('/backup/restore', methods=['POST'])
        def restore_backup():
            backup_id = request.json.get('backup_id')
            success = self.restore_backup(backup_id)
            return jsonify({'success': success})
    
    def authenticate_portainer(self):
        """Authenticate with Portainer API"""
        try:
            auth_url = f"{self.portainer_url}/api/auth"
            auth_data = {
                'username': 'admin',
                'password': 'rtpi-pen-admin'
            }
            
            response = requests.post(auth_url, json=auth_data, timeout=10)
            if response.status_code == 200:
                self.portainer_token = response.json().get('jwt')
                logger.info("Successfully authenticated with Portainer")
                return True
            else:
                logger.error(f"Failed to authenticate with Portainer: {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"Error authenticating with Portainer: {e}")
            return False
    
    def get_portainer_headers(self):
        """Get headers for Portainer API requests"""
        if not self.portainer_token:
            self.authenticate_portainer()
        
        return {
            'Authorization': f'Bearer {self.portainer_token}',
            'Content-Type': 'application/json'
        }
    
    def get_service_status(self) -> Dict:
        """Get status of all managed services"""
        services = {}
        
        try:
            containers = self.docker_client.containers.list(all=True)
            
            for container in containers:
                service_name = container.name
                
                # Skip system containers
                if service_name in ['rtpi-orchestrator']:
                    continue
                
                services[service_name] = {
                    'status': container.status,
                    'health': container.attrs.get('State', {}).get('Health', {}).get('Status', 'unknown'),
                    'restart_count': container.attrs.get('RestartCount', 0),
                    'created': container.attrs.get('Created', ''),
                    'started_at': container.attrs.get('State', {}).get('StartedAt', ''),
                    'image': container.image.tags[0] if container.image.tags else 'unknown'
                }
                
        except Exception as e:
            logger.error(f"Error getting service status: {e}")
        
        return services
    
    def restart_service(self, service_name: str) -> bool:
        """Restart a specific service"""
        try:
            container = self.docker_client.containers.get(service_name)
            
            logger.info(f"Restarting service: {service_name}")
            container.restart()
            
            self.orchestration_actions += 1
            
            # Wait for container to stabilize
            time.sleep(10)
            
            container.reload()
            if container.status == 'running':
                logger.info(f"Service {service_name} restarted successfully")
                return True
            else:
                logger.error(f"Service {service_name} failed to start after restart")
                return False
                
        except docker.errors.NotFound:
            logger.error(f"Service {service_name} not found")
            return False
        except Exception as e:
            logger.error(f"Error restarting service {service_name}: {e}")
            return False
    
    def scale_service(self, service_name: str, replicas: int) -> bool:
        """Scale a service to specified number of replicas"""
        try:
            # This is a simplified scaling implementation
            # In a production environment, you'd use Docker Swarm or Kubernetes
            
            if replicas <= 0:
                logger.error("Replica count must be positive")
                return False
            
            # For now, we'll handle basic scaling by starting/stopping containers
            containers = self.docker_client.containers.list(
                filters={'name': service_name}, all=True
            )
            
            current_replicas = len(containers)
            
            if current_replicas == replicas:
                logger.info(f"Service {service_name} already at {replicas} replicas")
                return True
            
            if replicas > current_replicas:
                # Scale up - start additional containers
                for i in range(replicas - current_replicas):
                    replica_name = f"{service_name}-replica-{i+1}"
                    # Implementation depends on service configuration
                    logger.info(f"Would start replica: {replica_name}")
            else:
                # Scale down - stop excess containers
                for i in range(current_replicas - replicas):
                    if containers:
                        container = containers.pop()
                        container.stop()
                        logger.info(f"Stopped replica: {container.name}")
            
            self.orchestration_actions += 1
            return True
            
        except Exception as e:
            logger.error(f"Error scaling service {service_name}: {e}")
            return False
    
    def check_service_health(self, service_name: str) -> Dict:
        """Check health of a specific service"""
        try:
            container = self.docker_client.containers.get(service_name)
            
            health_status = {
                'name': service_name,
                'status': container.status,
                'health': 'unknown',
                'last_check': datetime.now().isoformat()
            }
            
            # Get health check status
            health_state = container.attrs.get('State', {}).get('Health', {})
            if health_state:
                health_status['health'] = health_state.get('Status', 'unknown')
                health_status['failing_streak'] = health_state.get('FailingStreak', 0)
            
            # Additional health checks based on service type
            if service_name == 'rtpi-database':
                health_status['custom_checks'] = self._check_database_health()
            elif service_name == 'rtpi-cache':
                health_status['custom_checks'] = self._check_cache_health()
            elif service_name == 'rtpi-proxy':
                health_status['custom_checks'] = self._check_proxy_health()
            
            return health_status
            
        except docker.errors.NotFound:
            return {
                'name': service_name,
                'status': 'not_found',
                'health': 'not_found',
                'last_check': datetime.now().isoformat()
            }
        except Exception as e:
            logger.error(f"Error checking health for {service_name}: {e}")
            return {
                'name': service_name,
                'status': 'error',
                'health': 'error',
                'error': str(e),
                'last_check': datetime.now().isoformat()
            }
    
    def _check_database_health(self) -> Dict:
        """Check database specific health metrics"""
        try:
            # Test database connection
            result = subprocess.run([
                'docker', 'exec', 'rtpi-database', 'pg_isready', '-U', 'postgres'
            ], capture_output=True, text=True, timeout=10)
            
            return {
                'postgres_ready': result.returncode == 0,
                'postgres_output': result.stdout.strip()
            }
        except Exception as e:
            return {'error': str(e)}
    
    def _check_cache_health(self) -> Dict:
        """Check cache specific health metrics"""
        try:
            # Test Redis connection
            result = subprocess.run([
                'docker', 'exec', 'rtpi-cache', 'redis-cli', 'ping'
            ], capture_output=True, text=True, timeout=10)
            
            return {
                'redis_ping': result.stdout.strip() == 'PONG',
                'redis_output': result.stdout.strip()
            }
        except Exception as e:
            return {'error': str(e)}
    
    def _check_proxy_health(self) -> Dict:
        """Check proxy specific health metrics"""
        try:
            # Test nginx status
            result = subprocess.run([
                'docker', 'exec', 'rtpi-proxy', 'nginx', '-t'
            ], capture_output=True, text=True, timeout=10)
            
            return {
                'nginx_config_valid': result.returncode == 0,
                'nginx_output': result.stderr.strip()
            }
        except Exception as e:
            return {'error': str(e)}
    
    def perform_health_checks(self):
        """Perform health checks on all services"""
        try:
            services = self.get_service_status()
            
            for service_name in services:
                health_status = self.check_service_health(service_name)
                self.service_health[service_name] = health_status
                
                # Take action based on health status
                if health_status['health'] == 'unhealthy':
                    logger.warning(f"Service {service_name} is unhealthy")
                    
                    # Notify healer service
                    self._notify_healer(service_name, 'unhealthy')
                    
                elif health_status['status'] == 'exited':
                    logger.warning(f"Service {service_name} has exited")
                    
                    # Check if it should be restarted
                    if self._should_restart_service(service_name):
                        self.restart_service(service_name)
            
            self.last_health_check = datetime.now()
            
        except Exception as e:
            logger.error(f"Error performing health checks: {e}")
    
    def _should_restart_service(self, service_name: str) -> bool:
        """Determine if a service should be automatically restarted"""
        # Check restart policy and backoff
        try:
            container = self.docker_client.containers.get(service_name)
            restart_policy = container.attrs.get('HostConfig', {}).get('RestartPolicy', {})
            
            # If restart policy is set to always or unless-stopped, let Docker handle it
            if restart_policy.get('Name') in ['always', 'unless-stopped']:
                return False
            
            # Check if service has been failing repeatedly
            restart_count = container.attrs.get('RestartCount', 0)
            if restart_count > 5:  # Too many restarts
                logger.warning(f"Service {service_name} has restarted {restart_count} times")
                return False
            
            return True
            
        except Exception as e:
            logger.error(f"Error checking restart policy for {service_name}: {e}")
            return False
    
    def _notify_healer(self, service_name: str, issue_type: str):
        """Notify the healer service about an issue"""
        try:
            healer_url = "http://rtpi-healer:8888/heal"
            notification = {
                'service': service_name,
                'issue_type': issue_type,
                'timestamp': datetime.now().isoformat(),
                'orchestrator_id': 'rtpi-orchestrator'
            }
            
            response = requests.post(healer_url, json=notification, timeout=5)
            if response.status_code == 200:
                logger.info(f"Notified healer about {service_name} issue")
            else:
                logger.warning(f"Failed to notify healer: {response.status_code}")
                
        except Exception as e:
            logger.error(f"Error notifying healer: {e}")
    
    def create_backup(self) -> str:
        """Create a backup of Portainer data and configurations"""
        try:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            backup_id = f"rtpi-backup-{timestamp}"
            backup_path = f"/data/backups/{backup_id}"
            
            # Create backup directory
            os.makedirs(backup_path, exist_ok=True)
            
            # Backup Portainer data
            subprocess.run([
                'docker', 'exec', 'rtpi-orchestrator', 'tar', 'czf',
                f'{backup_path}/portainer-data.tar.gz', '/data'
            ], check=True)
            
            # Backup docker-compose files
            subprocess.run([
                'cp', '/opt/rtpi-pen/docker-compose.yml',
                f'{backup_path}/docker-compose.yml'
            ], check=True)
            
            # Create backup manifest
            manifest = {
                'backup_id': backup_id,
                'timestamp': timestamp,
                'services': list(self.get_service_status().keys()),
                'created_by': 'rtpi-orchestrator'
            }
            
            with open(f'{backup_path}/manifest.json', 'w') as f:
                json.dump(manifest, f, indent=2)
            
            logger.info(f"Created backup: {backup_id}")
            return backup_id
            
        except Exception as e:
            logger.error(f"Error creating backup: {e}")
            return None
    
    def restore_backup(self, backup_id: str) -> bool:
        """Restore from a backup"""
        try:
            backup_path = f"/data/backups/{backup_id}"
            
            if not os.path.exists(backup_path):
                logger.error(f"Backup {backup_id} not found")
                return False
            
            # Stop services
            logger.info("Stopping services for restore...")
            for service_name in reversed(self.dependency_manager.get_startup_order()):
                try:
                    container = self.docker_client.containers.get(service_name)
                    container.stop()
                    logger.info(f"Stopped {service_name}")
                except:
                    pass
            
            # Restore Portainer data
            subprocess.run([
                'docker', 'exec', 'rtpi-orchestrator', 'tar', 'xzf',
                f'{backup_path}/portainer-data.tar.gz', '-C', '/'
            ], check=True)
            
            # Restart services
            logger.info("Restarting services after restore...")
            for service_name in self.dependency_manager.get_startup_order():
                try:
                    container = self.docker_client.containers.get(service_name)
                    container.start()
                    logger.info(f"Started {service_name}")
                    time.sleep(5)  # Wait between starts
                except:
                    pass
            
            logger.info(f"Restored from backup: {backup_id}")
            return True
            
        except Exception as e:
            logger.error(f"Error restoring backup {backup_id}: {e}")
            return False
    
    def cleanup_old_backups(self):
        """Clean up old backups based on retention policy"""
        try:
            backup_dir = "/data/backups"
            if not os.path.exists(backup_dir):
                return
            
            cutoff_date = datetime.now() - timedelta(days=self.backup_retention_days)
            
            for backup_name in os.listdir(backup_dir):
                backup_path = os.path.join(backup_dir, backup_name)
                if os.path.isdir(backup_path):
                    # Check backup age
                    manifest_path = os.path.join(backup_path, 'manifest.json')
                    if os.path.exists(manifest_path):
                        try:
                            with open(manifest_path, 'r') as f:
                                manifest = json.load(f)
                            
                            backup_date = datetime.strptime(
                                manifest['timestamp'], '%Y%m%d_%H%M%S'
                            )
                            
                            if backup_date < cutoff_date:
                                subprocess.run(['rm', '-rf', backup_path], check=True)
                                logger.info(f"Removed old backup: {backup_name}")
                                
                        except Exception as e:
                            logger.error(f"Error checking backup {backup_name}: {e}")
            
        except Exception as e:
            logger.error(f"Error cleaning up backups: {e}")
    
    def run_api_server(self):
        """Run the Flask API server"""
        self.app.run(host='0.0.0.0', port=8080, debug=False)
    
    def run(self):
        """Main orchestrator loop"""
        logger.info("Starting RTPI-PEN Orchestrator Service")
        
        # Schedule periodic tasks
        schedule.every(self.health_check_interval).seconds.do(self.perform_health_checks)
        schedule.every(1).hours.do(self.cleanup_old_backups)
        schedule.every(6).hours.do(self.create_backup)
        
        # Start API server in separate thread
        api_thread = threading.Thread(target=self.run_api_server, daemon=True)
        api_thread.start()
        
        try:
            while self.running:
                schedule.run_pending()
                time.sleep(1)
        except KeyboardInterrupt:
            logger.info("Received shutdown signal")
            self.running = False
        except Exception as e:
            logger.error(f"Error in main loop: {e}")
            self.running = False

if __name__ == "__main__":
    orchestrator = ContainerOrchestrator()
    orchestrator.run()
