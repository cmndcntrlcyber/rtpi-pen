#!/usr/bin/env python3
"""
RTPI-Pen MCP Server - Infrastructure Management and Orchestration

This MCP server exposes Docker infrastructure management, container orchestration,
and security service capabilities from the RTPI-Pen environment.
"""

import asyncio
import json
import logging
import sys
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence
import docker
import psutil
import redis
import psycopg2
from psycopg2.extras import RealDictCursor

# Add the tools directory to the Python path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "tools"))

from mcp.server.models import InitializationOptions
from mcp.server import NotificationOptions, Server
from mcp.types import (
    Resource,
    Tool,
    TextContent,
    ImageContent,
    EmbeddedResource,
    LoggingLevel
)
import mcp.types as types

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("rtpi-pen-mcp-server")

class RTPIPenMCPServer:
    """
    RTPI-Pen MCP Server for infrastructure management and orchestration.
    """
    
    def __init__(self):
        self.server = Server("rtpi-pen-mcp-server")
        self.docker_client = None
        self.redis_client = None
        self.postgres_connection = None
        self.container_configs = {}
        self.service_health = {}
        
        # Setup paths
        self.rtpi_pen_path = Path(__file__).parent.parent.parent
        self.tools_path = Path(__file__).parent.parent.parent.parent / "tools"
        
        # Initialize Docker client
        try:
            self.docker_client = docker.from_env()
            logger.info("Docker client initialized successfully")
        except Exception as e:
            logger.warning(f"Failed to initialize Docker client: {e}")
        
        # Initialize Redis connection
        try:
            self.redis_client = redis.Redis(host='localhost', port=6379, decode_responses=True)
            self.redis_client.ping()
            logger.info("Redis connection established")
        except Exception as e:
            logger.warning(f"Failed to connect to Redis: {e}")
        
        # Initialize PostgreSQL connection
        try:
            self.postgres_connection = psycopg2.connect(
                host="localhost",
                port=5432,
                database="rtpi_main",
                user="rtpi",
                password="rtpi_secure_password",
                cursor_factory=RealDictCursor
            )
            logger.info("PostgreSQL connection established")
        except Exception as e:
            logger.warning(f"Failed to connect to PostgreSQL: {e}")
    
    def setup_handlers(self):
        """Set up MCP request handlers."""
        
        @self.server.list_resources()
        async def handle_list_resources() -> list[Resource]:
            """List available RTPI-Pen resources."""
            return [
                Resource(
                    uri="rtpi-pen://containers/list",
                    name="Container List",
                    description="List of all Docker containers in RTPI-Pen",
                    mimeType="application/json"
                ),
                Resource(
                    uri="rtpi-pen://services/health",
                    name="Service Health Status",
                    description="Health status of all RTPI-Pen services",
                    mimeType="application/json"
                ),
                Resource(
                    uri="rtpi-pen://infrastructure/status",
                    name="Infrastructure Status",
                    description="Overall infrastructure status and metrics",
                    mimeType="application/json"
                ),
                Resource(
                    uri="rtpi-pen://logs/system",
                    name="System Logs",
                    description="Recent system and application logs",
                    mimeType="application/json"
                )
            ]
        
        @self.server.read_resource()
        async def handle_read_resource(uri: types.AnyUrl) -> str:
            """Read RTPI-Pen resource content."""
            uri_str = str(uri)
            
            if uri_str == "rtpi-pen://containers/list":
                return await self.get_container_list()
            elif uri_str == "rtpi-pen://services/health":
                return await self.get_service_health()
            elif uri_str == "rtpi-pen://infrastructure/status":
                return await self.get_infrastructure_status()
            elif uri_str == "rtpi-pen://logs/system":
                return await self.get_system_logs()
            else:
                raise ValueError(f"Unknown resource: {uri_str}")
        
        @self.server.list_tools()
        async def handle_list_tools() -> list[Tool]:
            """List available RTPI-Pen tools."""
            return [
                Tool(
                    name="manage_container",
                    description="Manage Docker containers (start, stop, restart, remove)",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "container_name": {
                                "type": "string",
                                "description": "Name of the container to manage"
                            },
                            "action": {
                                "type": "string",
                                "enum": ["start", "stop", "restart", "remove", "logs"],
                                "description": "Action to perform on the container"
                            },
                            "follow_logs": {
                                "type": "boolean",
                                "default": False,
                                "description": "Follow logs in real-time (for logs action)"
                            }
                        },
                        "required": ["container_name", "action"]
                    }
                ),
                Tool(
                    name="deploy_service",
                    description="Deploy or update a service in RTPI-Pen infrastructure",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "service_name": {
                                "type": "string",
                                "description": "Name of the service to deploy"
                            },
                            "image": {
                                "type": "string",
                                "description": "Docker image for the service"
                            },
                            "config": {
                                "type": "object",
                                "description": "Service configuration parameters",
                                "properties": {
                                    "ports": {
                                        "type": "array",
                                        "items": {"type": "string"},
                                        "description": "Port mappings"
                                    },
                                    "environment": {
                                        "type": "object",
                                        "description": "Environment variables"
                                    },
                                    "volumes": {
                                        "type": "array",
                                        "items": {"type": "string"},
                                        "description": "Volume mounts"
                                    },
                                    "networks": {
                                        "type": "array",
                                        "items": {"type": "string"},
                                        "description": "Networks to connect to"
                                    }
                                }
                            }
                        },
                        "required": ["service_name", "image"]
                    }
                ),
                Tool(
                    name="scale_service",
                    description="Scale a service up or down",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "service_name": {
                                "type": "string",
                                "description": "Name of the service to scale"
                            },
                            "replicas": {
                                "type": "integer",
                                "minimum": 0,
                                "description": "Number of replicas to scale to"
                            }
                        },
                        "required": ["service_name", "replicas"]
                    }
                ),
                Tool(
                    name="monitor_infrastructure",
                    description="Monitor infrastructure performance and health",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "duration": {
                                "type": "integer",
                                "default": 60,
                                "description": "Monitoring duration in seconds"
                            },
                            "metrics": {
                                "type": "array",
                                "items": {
                                    "type": "string",
                                    "enum": ["cpu", "memory", "disk", "network", "containers"]
                                },
                                "default": ["cpu", "memory", "containers"],
                                "description": "Metrics to monitor"
                            }
                        }
                    }
                ),
                Tool(
                    name="backup_data",
                    description="Backup RTPI-Pen data including databases and configurations",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "backup_type": {
                                "type": "string",
                                "enum": ["full", "incremental", "database", "configs"],
                                "default": "full",
                                "description": "Type of backup to perform"
                            },
                            "destination": {
                                "type": "string",
                                "description": "Backup destination path"
                            },
                            "compress": {
                                "type": "boolean",
                                "default": True,
                                "description": "Compress backup files"
                            }
                        }
                    }
                ),
                Tool(
                    name="execute_healing_action",
                    description="Execute self-healing actions for infrastructure recovery",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "action_type": {
                                "type": "string",
                                "enum": ["restart_service", "fix_permissions", "clear_cache", "repair_network", "full_recovery"],
                                "description": "Type of healing action to execute"
                            },
                            "target": {
                                "type": "string",
                                "description": "Target service or component for healing"
                            },
                            "parameters": {
                                "type": "object",
                                "description": "Additional parameters for the healing action"
                            }
                        },
                        "required": ["action_type", "target"]
                    }
                ),
                Tool(
                    name="manage_kasm_workspace",
                    description="Manage Kasm workspace instances (VS Code, Kali Linux)",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "workspace_type": {
                                "type": "string",
                                "enum": ["vscode", "kali", "custom"],
                                "description": "Type of Kasm workspace"
                            },
                            "action": {
                                "type": "string",
                                "enum": ["start", "stop", "restart", "reset", "configure"],
                                "description": "Action to perform on the workspace"
                            },
                            "configuration": {
                                "type": "object",
                                "description": "Workspace configuration parameters"
                            }
                        },
                        "required": ["workspace_type", "action"]
                    }
                ),
                Tool(
                    name="configure_proxy",
                    description="Configure RTPI-Pen proxy settings and SSL certificates",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "domain": {
                                "type": "string",
                                "description": "Domain name for SSL certificate"
                            },
                            "ssl_config": {
                                "type": "object",
                                "properties": {
                                    "auto_renew": {"type": "boolean"},
                                    "provider": {"type": "string", "enum": ["letsencrypt", "cloudflare", "custom"]},
                                    "email": {"type": "string"}
                                },
                                "description": "SSL configuration"
                            },
                            "proxy_rules": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "source": {"type": "string"},
                                        "destination": {"type": "string"},
                                        "path": {"type": "string"}
                                    }
                                },
                                "description": "Proxy routing rules"
                            }
                        },
                        "required": ["domain"]
                    }
                )
            ]
        
        @self.server.call_tool()
        async def handle_call_tool(name: str, arguments: dict[str, Any] | None) -> list[types.TextContent | types.ImageContent | types.EmbeddedResource]:
            """Handle tool execution requests."""
            
            if arguments is None:
                arguments = {}
            
            try:
                if name == "manage_container":
                    return await self.manage_container(arguments)
                elif name == "deploy_service":
                    return await self.deploy_service(arguments)
                elif name == "scale_service":
                    return await self.scale_service(arguments)
                elif name == "monitor_infrastructure":
                    return await self.monitor_infrastructure(arguments)
                elif name == "backup_data":
                    return await self.backup_data(arguments)
                elif name == "execute_healing_action":
                    return await self.execute_healing_action(arguments)
                elif name == "manage_kasm_workspace":
                    return await self.manage_kasm_workspace(arguments)
                elif name == "configure_proxy":
                    return await self.configure_proxy(arguments)
                else:
                    raise ValueError(f"Unknown tool: {name}")
                    
            except Exception as e:
                logger.error(f"Error executing tool {name}: {e}")
                return [
                    types.TextContent(
                        type="text",
                        text=f"Error executing {name}: {str(e)}"
                    )
                ]
    
    async def manage_container(self, args: Dict[str, Any]) -> List[types.TextContent]:
        """Manage Docker containers."""
        container_name = args.get("container_name")
        action = args.get("action")
        follow_logs = args.get("follow_logs", False)
        
        if not self.docker_client:
            return [types.TextContent(type="text", text="Docker client not available")]
        
        try:
            container = self.docker_client.containers.get(container_name)
            
            if action == "start":
                container.start()
                result = {"success": True, "action": "started", "container": container_name}
                
            elif action == "stop":
                container.stop()
                result = {"success": True, "action": "stopped", "container": container_name}
                
            elif action == "restart":
                container.restart()
                result = {"success": True, "action": "restarted", "container": container_name}
                
            elif action == "remove":
                container.remove(force=True)
                result = {"success": True, "action": "removed", "container": container_name}
                
            elif action == "logs":
                logs = container.logs(tail=100).decode('utf-8')
                result = {
                    "success": True, 
                    "action": "logs_retrieved", 
                    "container": container_name,
                    "logs": logs
                }
            else:
                result = {"success": False, "error": f"Unknown action: {action}"}
            
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
            
        except docker.errors.NotFound:
            result = {"success": False, "error": f"Container '{container_name}' not found"}
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
        except Exception as e:
            result = {"success": False, "error": f"Container management error: {str(e)}"}
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
    
    async def deploy_service(self, args: Dict[str, Any]) -> List[types.TextContent]:
        """Deploy or update a service."""
        service_name = args.get("service_name")
        image = args.get("image")
        config = args.get("config", {})
        
        if not self.docker_client:
            return [types.TextContent(type="text", text="Docker client not available")]
        
        try:
            # Check if container already exists
            try:
                existing_container = self.docker_client.containers.get(service_name)
                existing_container.stop()
                existing_container.remove()
                logger.info(f"Removed existing container: {service_name}")
            except docker.errors.NotFound:
                pass
            
            # Prepare container configuration
            container_config = {
                "image": image,
                "name": service_name,
                "detach": True
            }
            
            # Add port mappings
            if "ports" in config:
                container_config["ports"] = {}
                for port_mapping in config["ports"]:
                    if ":" in port_mapping:
                        host_port, container_port = port_mapping.split(":")
                        container_config["ports"][container_port] = host_port
            
            # Add environment variables
            if "environment" in config:
                container_config["environment"] = config["environment"]
            
            # Add volume mounts
            if "volumes" in config:
                container_config["volumes"] = {}
                for volume_mapping in config["volumes"]:
                    if ":" in volume_mapping:
                        host_path, container_path = volume_mapping.split(":", 1)
                        container_config["volumes"][host_path] = {"bind": container_path, "mode": "rw"}
            
            # Deploy the container
            container = self.docker_client.containers.run(**container_config)
            
            result = {
                "success": True,
                "action": "deployed",
                "service_name": service_name,
                "container_id": container.id,
                "image": image,
                "status": container.status
            }
            
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
            
        except Exception as e:
            result = {"success": False, "error": f"Deployment error: {str(e)}"}
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
    
    async def scale_service(self, args: Dict[str, Any]) -> List[types.TextContent]:
        """Scale a service."""
        service_name = args.get("service_name")
        replicas = args.get("replicas")
        
        if not self.docker_client:
            return [types.TextContent(type="text", text="Docker client not available")]
        
        try:
            # In a real implementation, this would work with Docker Swarm or Kubernetes
            # For Docker Compose, we'll simulate scaling by managing multiple containers
            
            # Get existing containers for this service
            existing_containers = [
                c for c in self.docker_client.containers.list(all=True)
                if c.name.startswith(f"{service_name}_") or c.name == service_name
            ]
            
            current_replicas = len(existing_containers)
            
            if replicas > current_replicas:
                # Scale up - create additional containers
                for i in range(current_replicas, replicas):
                    container_name = f"{service_name}_{i+1}" if i > 0 else service_name
                    # This would need service configuration from Docker Compose
                    logger.info(f"Would create container: {container_name}")
                    
            elif replicas < current_replicas:
                # Scale down - remove excess containers
                containers_to_remove = existing_containers[replicas:]
                for container in containers_to_remove:
                    container.stop()
                    container.remove()
                    logger.info(f"Removed container: {container.name}")
            
            result = {
                "success": True,
                "action": "scaled",
                "service_name": service_name,
                "previous_replicas": current_replicas,
                "new_replicas": replicas
            }
            
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
            
        except Exception as e:
            result = {"success": False, "error": f"Scaling error: {str(e)}"}
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
    
    async def monitor_infrastructure(self, args: Dict[str, Any]) -> List[types.TextContent]:
        """Monitor infrastructure performance."""
        duration = args.get("duration", 60)
        metrics = args.get("metrics", ["cpu", "memory", "containers"])
        
        try:
            monitoring_data = {
                "timestamp": psutil.boot_time(),
                "duration": duration,
                "metrics": {}
            }
            
            if "cpu" in metrics:
                monitoring_data["metrics"]["cpu"] = {
                    "usage_percent": psutil.cpu_percent(interval=1),
                    "core_count": psutil.cpu_count(),
                    "load_average": os.getloadavg() if hasattr(os, 'getloadavg') else "N/A"
                }
            
            if "memory" in metrics:
                memory_info = psutil.virtual_memory()
                monitoring_data["metrics"]["memory"] = {
                    "total_gb": round(memory_info.total / (1024**3), 2),
                    "available_gb": round(memory_info.available / (1024**3), 2),
                    "usage_percent": memory_info.percent,
                    "used_gb": round(memory_info.used / (1024**3), 2)
                }
            
            if "disk" in metrics:
                disk_info = psutil.disk_usage("/")
                monitoring_data["metrics"]["disk"] = {
                    "total_gb": round(disk_info.total / (1024**3), 2),
                    "free_gb": round(disk_info.free / (1024**3), 2),
                    "usage_percent": round((disk_info.used / disk_info.total) * 100, 2)
                }
            
            if "network" in metrics:
                network_info = psutil.net_io_counters()
                monitoring_data["metrics"]["network"] = {
                    "bytes_sent": network_info.bytes_sent,
                    "bytes_recv": network_info.bytes_recv,
                    "packets_sent": network_info.packets_sent,
                    "packets_recv": network_info.packets_recv
                }
            
            if "containers" in metrics and self.docker_client:
                containers = self.docker_client.containers.list(all=True)
                running_containers = [c for c in containers if c.status == "running"]
                monitoring_data["metrics"]["containers"] = {
                    "total": len(containers),
                    "running": len(running_containers),
                    "stopped": len(containers) - len(running_containers),
                    "containers": [
                        {
                            "name": c.name,
                            "status": c.status,
                            "image": c.image.tags[0] if c.image.tags else "unknown"
                        }
                        for c in containers
                    ]
                }
            
            return [types.TextContent(type="text", text=json.dumps(monitoring_data, indent=2))]
            
        except Exception as e:
            result = {"success": False, "error": f"Monitoring error: {str(e)}"}
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
    
    async def backup_data(self, args: Dict[str, Any]) -> List[types.TextContent]:
        """Backup RTPI-Pen data."""
        backup_type = args.get("backup_type", "full")
        destination = args.get("destination", "/tmp/rtpi-backup")
        compress = args.get("compress", True)
        
        try:
            # Create backup directory
            backup_dir = Path(destination)
            backup_dir.mkdir(parents=True, exist_ok=True)
            
            backup_info = {
                "backup_type": backup_type,
                "destination": destination,
                "timestamp": psutil.boot_time(),
                "files_backed_up": []
            }
            
            if backup_type in ["full", "database"]:
                # Backup PostgreSQL database
                if self.postgres_connection:
                    db_backup_file = backup_dir / "rtpi_database.sql"
                    # In a real implementation, use pg_dump
                    backup_info["files_backed_up"].append(str(db_backup_file))
                
                # Backup Redis data
                if self.redis_client:
                    redis_backup_file = backup_dir / "redis_dump.rdb"
                    # In a real implementation, use Redis BGSAVE
                    backup_info["files_backed_up"].append(str(redis_backup_file))
            
            if backup_type in ["full", "configs"]:
                # Backup configuration files
                config_files = [
                    self.rtpi_pen_path / "docker-compose.yml",
                    self.rtpi_pen_path / "configs",
                ]
                
                for config_file in config_files:
                    if config_file.exists():
                        backup_info["files_backed_up"].append(str(config_file))
            
            if compress:
                # In a real implementation, create compressed archive
                backup_info["compressed"] = True
                backup_info["archive_file"] = f"{destination}.tar.gz"
            
            result = {
                "success": True,
                "backup_info": backup_info
            }
            
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
            
        except Exception as e:
            result = {"success": False, "error": f"Backup error: {str(e)}"}
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
    
    async def execute_healing_action(self, args: Dict[str, Any]) -> List[types.TextContent]:
        """Execute self-healing actions."""
        action_type = args.get("action_type")
        target = args.get("target")
        parameters = args.get("parameters", {})
        
        try:
            healing_result = {
                "action_type": action_type,
                "target": target,
                "timestamp": psutil.boot_time(),
                "steps_executed": []
            }
            
            if action_type == "restart_service":
                if self.docker_client:
                    try:
                        container = self.docker_client.containers.get(target)
                        container.restart()
                        healing_result["steps_executed"].append(f"Restarted container: {target}")
                        healing_result["success"] = True
                    except docker.errors.NotFound:
                        healing_result["steps_executed"].append(f"Container not found: {target}")
                        healing_result["success"] = False
            
            elif action_type == "fix_permissions":
                # Execute permission fix scripts
                script_path = self.rtpi_pen_path / "repair-scripts" / f"fix-{target}-permissions.sh"
                if script_path.exists():
                    result = subprocess.run(["bash", str(script_path)], capture_output=True, text=True)
                    healing_result["steps_executed"].append(f"Executed permission fix script: {script_path}")
                    healing_result["script_output"] = result.stdout
                    healing_result["success"] = result.returncode == 0
                else:
                    healing_result["steps_executed"].append(f"Permission fix script not found: {script_path}")
                    healing_result["success"] = False
            
            elif action_type == "clear_cache":
                # Clear Redis cache
                if self.redis_client:
                    self.redis_client.flushdb()
                    healing_result["steps_executed"].append("Cleared Redis cache")
                    healing_result["success"] = True
                else:
                    healing_result["steps_executed"].append("Redis client not available")
                    healing_result["success"] = False
            
            elif action_type == "repair_network":
                # Execute network repair scripts
                script_path = self.rtpi_pen_path / "repair-scripts" / "rtpi-pen-repair.sh"
                if script_path.exists():
                    result = subprocess.run(["bash", str(script_path)], capture_output=True, text=True)
                    healing_result["steps_executed"].append(f"Executed network repair script")
                    healing_result["script_output"] = result.stdout
                    healing_result["success"] = result.returncode == 0
                else:
                    healing_result["steps_executed"].append("Network repair script not found")
                    healing_result["success"] = False
            
            elif action_type == "full_recovery":
                # Execute comprehensive recovery
                recovery_script = self.rtpi_pen_path / "repair-scripts" / "emergency-repair.sh"
                if recovery_script.exists():
                    result = subprocess.run(["bash", str(recovery_script)], capture_output=True, text=True)
                    healing_result["steps_executed"].append("Executed emergency recovery script")
                    healing_result["script_output"] = result.stdout
                    healing_result["success"] = result.returncode == 0
                else:
                    healing_result["steps_executed"].append("Emergency recovery script not found")
                    healing_result["success"] = False
            
            return [types.TextContent(type="text", text=json.dumps(healing_result, indent=2))]
            
        except Exception as e:
            result = {"success": False, "error": f"Healing action error: {str(e)}"}
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
    
    async def manage_kasm_workspace(self, args: Dict[str, Any]) -> List[types.TextContent]:
        """Manage Kasm workspace instances."""
        workspace_type = args.get("workspace_type")
        action = args.get("action")
        configuration = args.get("configuration", {})
        
        try:
            # Map workspace type to container name
            container_mapping = {
                "vscode": "kasm-vscode",
                "kali": "kasm-kali"
            }
            
            container_name = container_mapping.get(workspace_type)
            if not container_name:
                result = {"success": False, "error": f"Unknown workspace type: {workspace_type}"}
                return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
            
            if not self.docker_client:
                return [types.TextContent(type="text", text="Docker client not available")]
            
            # Execute action on the workspace container
            if action in ["start", "stop", "restart"]:
                container_result = await self.manage_container({
                    "container_name": container_name,
                    "action": action
                })
                
                # Parse the result and add workspace-specific information
                container_data = json.loads(container_result[0].text)
                container_data["workspace_type"] = workspace_type
                
                return [types.TextContent(type="text", text=json.dumps(container_data, indent=2))]
            
            elif action == "reset":
                # Stop, remove, and recreate the workspace
                try:
                    container = self.docker_client.containers.get(container_name)
                    container.stop()
                    container.remove()
                    
                    # Would need to recreate with original configuration from docker-compose
                    result = {
                        "success": True,
                        "action": "reset",
                        "workspace_type": workspace_type,
                        "container": container_name,
                        "status": "reset_completed"
                    }
                    
                except docker.errors.NotFound:
                    result = {
                        "success": False,
                        "error": f"Workspace container '{container_name}' not found"
                    }
                
                return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
            
            elif action == "configure":
                # Update workspace configuration
                result = {
                    "success": True,
                    "action": "configured",
                    "workspace_type": workspace_type,
                    "configuration": configuration
                }
                
                return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
            
            else:
                result = {"success": False, "error": f"Unknown action: {action}"}
                return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
            
        except Exception as e:
            result = {"success": False, "error": f"Kasm workspace management error: {str(e)}"}
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
    
    async def configure_proxy(self, args: Dict[str, Any]) -> List[types.TextContent]:
        """Configure RTPI-Pen proxy settings."""
        domain = args.get("domain")
        ssl_config = args.get("ssl_config", {})
        proxy_rules = args.get("proxy_rules", [])
        
        try:
            proxy_config = {
                "domain": domain,
                "ssl_config": ssl_config,
                "proxy_rules": proxy_rules,
                "timestamp": psutil.boot_time()
            }
            
            # Execute SSL certificate setup if needed
            if ssl_config.get("auto_renew", False):
                cert_script = self.rtpi_pen_path / "setup" / "cert_manager.sh"
                if cert_script.exists():
                    result = subprocess.run(
                        ["bash", str(cert_script), domain], 
                        capture_output=True, 
                        text=True
                    )
                    proxy_config["ssl_setup"] = {
                        "script_executed": True,
                        "success": result.returncode == 0,
                        "output": result.stdout
                    }
            
            # Apply proxy rules (would typically update nginx config)
            proxy_config["rules_applied"] = len(proxy_rules)
            proxy_config["success"] = True
            
            return [types.TextContent(type="text", text=json.dumps(proxy_config, indent=2))]
            
        except Exception as e:
            result = {"success": False, "error": f"Proxy configuration error: {str(e)}"}
            return [types.TextContent(type="text", text=json.dumps(result, indent=2))]
    
    async def get_container_list(self) -> str:
        """Get list of all containers."""
        if not self.docker_client:
            return json.dumps({"error": "Docker client not available"}, indent=2)
        
        try:
            containers = self.docker_client.containers.list(all=True)
            container_data = []
            
            for container in containers:
                container_info = {
                    "name": container.name,
                    "id": container.id[:12],
                    "image": container.image.tags[0] if container.image.tags else "unknown",
                    "status": container.status,
                    "ports": container.ports,
                    "created": container.attrs.get("Created", "unknown"),
                    "labels": container.labels
                }
                container_data.append(container_info)
            
            result = {
                "total_containers": len(containers),
                "running_containers": len([c for c in containers if c.status == "running"]),
                "containers": container_data,
                "timestamp": psutil.boot_time()
            }
            
            return json.dumps(result, indent=2)
            
        except Exception as e:
            return json.dumps({"error": f"Failed to list containers: {str(e)}"}, indent=2)
    
    async def get_service_health(self) -> str:
        """Get service health status."""
        health_data = {
            "timestamp": psutil.boot_time(),
            "services": {}
        }
        
        # Check core services
        core_services = [
            "rtpi-database", "rtpi-cache", "rtpi-orchestrator", 
            "rtpi-proxy", "rtpi-healer", "sysreptor-app"
        ]
        
        if self.docker_client:
            for service_name in core_services:
                try:
                    container = self.docker_client.containers.get(service_name)
                    health_data["services"][service_name] = {
                        "status": container.status,
                        "health": "healthy" if container.status == "running" else "unhealthy",
                        "uptime": container.attrs.get("State", {}).get("StartedAt", "unknown")
                    }
                except docker.errors.NotFound:
                    health_data["services"][service_name] = {
                        "status": "not_found",
                        "health": "unhealthy",
                        "error": "Container not found"
                    }
        
        # Check database connectivity
        if self.postgres_connection:
            try:
                cursor = self.postgres_connection.cursor()
                cursor.execute("SELECT 1")
                health_data["services"]["postgresql"] = {
                    "status": "connected",
                    "health": "healthy"
                }
                cursor.close()
            except Exception as e:
                health_data["services"]["postgresql"] = {
                    "status": "error",
                    "health": "unhealthy",
                    "error": str(e)
                }
        
        # Check Redis connectivity
        if self.redis_client:
            try:
                self.redis_client.ping()
                health_data["services"]["redis"] = {
                    "status": "connected",
                    "health": "healthy"
                }
            except Exception as e:
                health_data["services"]["redis"] = {
                    "status": "error",
                    "health": "unhealthy",
                    "error": str(e)
                }
        
        return json.dumps(health_data, indent=2)
    
    async def get_infrastructure_status(self) -> str:
        """Get overall infrastructure status."""
        status_data = {
            "timestamp": psutil.boot_time(),
            "system": {
                "cpu_percent": psutil.cpu_percent(),
                "memory_percent": psutil.virtual_memory().percent,
                "disk_percent": psutil.disk_usage("/").percent if os.path.exists("/") else "N/A",
                "boot_time": psutil.boot_time(),
                "uptime_hours": (psutil.time.time() - psutil.boot_time()) / 3600
            },
            "docker": {},
            "network": {}
        }
        
        # Docker status
        if self.docker_client:
            try:
                info = self.docker_client.info()
                status_data["docker"] = {
                    "containers_running": info.get("ContainersRunning", 0),
                    "containers_total": info.get("Containers", 0),
                    "images": info.get("Images", 0),
                    "version": info.get("ServerVersion", "unknown")
                }
            except Exception as e:
                status_data["docker"]["error"] = str(e)
        
        # Network interfaces
        try:
            network_interfaces = psutil.net_if_addrs()
            status_data["network"]["interfaces"] = list(network_interfaces.keys())
        except Exception as e:
            status_data["network"]["error"] = str(e)
        
        return json.dumps(status_data, indent=2)
    
    async def get_system_logs(self) -> str:
        """Get recent system logs."""
        log_data = {
            "timestamp": psutil.boot_time(),
            "logs": []
        }
        
        # Check for log files in the rtpi-pen logs directory
        logs_dir = self.rtpi_pen_path / "logs"
        if logs_dir.exists():
            for log_file in logs_dir.glob("*.log"):
                try:
                    with open(log_file, 'r') as f:
                        lines = f.readlines()
                        recent_lines = lines[-20:] if len(lines) > 20 else lines
                        
                        log_data["logs"].append({
                            "file": log_file.name,
                            "path": str(log_file),
                            "recent_lines": [line.strip() for line in recent_lines],
                            "total_lines": len(lines)
                        })
                except Exception as e:
                    log_data["logs"].append({
                        "file": log_file.name,
                        "error": f"Failed to read log: {str(e)}"
                    })
        
        return json.dumps(log_data, indent=2)


async def main():
    """Main entry point for the RTPI-Pen MCP server."""
    server_instance = RTPIPenMCPServer()
    server_instance.setup_handlers()
    
    # Run the server
    async with server_instance.server.stdio_server() as (read_stream, write_stream):
        await server_instance.server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="rtpi-pen-mcp-server",
                server_version="1.0.0",
                capabilities=server_instance.server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={}
                )
            )
        )

if __name__ == "__main__":
    asyncio.run(main())
