#!/usr/bin/env python3
"""
OpenClaw API Example - Python client for RemBotClawBot
Demonstrates how to interact with OpenClaw programmatically
"""

import json
import os
import subprocess
import sys
from typing import Dict, List, Optional, Any
from dataclasses import dataclass
from enum import Enum


class OpenClawCommand(Enum):
    """Available OpenClaw commands"""
    STATUS = "status"
    CONFIG = "config"
    SESSIONS = "sessions"
    CRON = "cron"
    GATEWAY = "gateway"
    HEALTH = "health"


@dataclass
class OpenClawResponse:
    """Response from OpenClaw command"""
    success: bool
    output: str
    error: Optional[str] = None
    return_code: int = 0


class OpenClawClient:
    """Client for interacting with OpenClaw via CLI"""
    
    def __init__(self, openclaw_path: str = "openclaw"):
        self.openclaw_path = openclaw_path
        
    def run_command(self, command: List[str]) -> OpenClawResponse:
        """Run an OpenClaw command"""
        try:
            cmd = [self.openclaw_path] + command
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=False
            )
            
            return OpenClawResponse(
                success=result.returncode == 0,
                output=result.stdout.strip(),
                error=result.stderr.strip() if result.stderr else None,
                return_code=result.returncode
            )
        except Exception as e:
            return OpenClawResponse(
                success=False,
                output="",
                error=str(e),
                return_code=1
            )
    
    def get_status(self) -> Dict[str, Any]:
        """Get OpenClaw system status"""
        response = self.run_command(["status"])
        
        if not response.success:
            return {"error": response.error}
        
        # Parse status output (simplified)
        status = {}
        lines = response.output.split('\n')
        
        for line in lines:
            if ':' in line:
                key, value = line.split(':', 1)
                status[key.strip()] = value.strip()
        
        return status
    
    def list_sessions(self) -> List[Dict[str, Any]]:
        """List active OpenClaw sessions"""
        response = self.run_command(["sessions", "list"])
        
        if not response.success:
            return []
        
        sessions = []
        # Simple parsing - actual implementation would need proper JSON parsing
        # if OpenClaw supports JSON output
        return sessions
    
    def cron_status(self) -> Dict[str, Any]:
        """Get cron job status"""
        response = self.run_command(["cron", "status"])
        
        if not response.success:
            return {"error": response.error}
        
        return {"output": response.output}
    
    def gateway_status(self) -> Dict[str, Any]:
        """Get gateway daemon status"""
        response = self.run_command(["gateway", "status"])
        
        if not response.success:
            return {"error": response.error}
        
        return {"output": response.output}
    
    def health_check(self) -> Dict[str, Any]:
        """Run health check"""
        response = self.run_command(["health"])
        
        if not response.success:
            return {"error": response.error}
        
        return {"output": response.output}


def check_system_health() -> Dict[str, Any]:
    """Comprehensive system health check"""
    client = OpenClawClient()
    results = {}
    
    print("Running system health checks...")
    
    # Check OpenClaw status
    print("1. Checking OpenClaw status...")
    status = client.get_status()
    results["openclaw_status"] = status
    
    # Check gateway
    print("2. Checking gateway...")
    gateway = client.gateway_status()
    results["gateway"] = gateway
    
    # Check cron jobs
    print("3. Checking cron jobs...")
    cron = client.cron_status()
    results["cron"] = cron
    
    # Check Git servers
    print("4. Checking Git servers...")
    git_servers = check_git_servers()
    results["git_servers"] = git_servers
    
    # Check disk space
    print("5. Checking disk space...")
    disk_info = check_disk_space()
    results["disk"] = disk_info
    
    # Check memory
    print("6. Checking memory...")
    memory_info = check_memory()
    results["memory"] = memory_info
    
    return results


def check_git_servers() -> Dict[str, Any]:
    """Check status of Git servers"""
    import socket
    
    servers = {
        "forgejo": {"port": 3001, "status": False},
        "gitea": {"port": 3000, "status": False}
    }
    
    for server_name, info in servers.items():
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2)
        
        try:
            result = sock.connect_ex(('localhost', info["port"]))
            info["status"] = result == 0
            sock.close()
        except:
            info["status"] = False
    
    return servers


def check_disk_space() -> Dict[str, Any]:
    """Check disk space usage"""
    import shutil
    
    total, used, free = shutil.disk_usage("/")
    
    return {
        "total_gb": round(total / (2**30), 2),
        "used_gb": round(used / (2**30), 2),
        "free_gb": round(free / (2**30), 2),
        "percent_used": round((used / total) * 100, 2)
    }


def check_memory() -> Dict[str, Any]:
    """Check memory usage"""
    import psutil
    
    memory = psutil.virtual_memory()
    
    return {
        "total_gb": round(memory.total / (1024**3), 2),
        "available_gb": round(memory.available / (1024**3), 2),
        "percent_used": memory.percent,
        "used_gb": round(memory.used / (1024**3), 2),
        "free_gb": round(memory.free / (1024**3), 2)
    }


def generate_health_report(results: Dict[str, Any]) -> str:
    """Generate a human-readable health report"""
    report = ["=== System Health Report ==="]
    report.append(f"Generated: {results.get('timestamp', 'N/A')}")
    report.append("")
    
    # OpenClaw status
    report.append("1. OpenClaw System")
    status = results.get('openclaw_status', {})
    if 'error' in status:
        report.append(f"   Status: ERROR - {status['error']}")
    else:
        report.append(f"   Status: OPERATIONAL")
        for key, value in status.items():
            report.append(f"   {key}: {value}")
    
    # Gateway
    report.append("")
    report.append("2. Gateway")
    gateway = results.get('gateway', {})
    if 'running' in gateway.get('output', '').lower():
        report.append("   Status: RUNNING")
    else:
        report.append("   Status: ISSUES DETECTED")
    
    # Git servers
    report.append("")
    report.append("3. Git Servers")
    git_servers = results.get('git_servers', {})
    for server, info in git_servers.items():
        status = "✓ ONLINE" if info.get('status') else "✗ OFFLINE"
        report.append(f"   {server.capitalize()} (port {info.get('port', 'N/A')}): {status}")
    
    # Resources
    report.append("")
    report.append("4. System Resources")
    disk = results.get('disk', {})
    report.append(f"   Disk Usage: {disk.get('percent_used', 'N/A')}%")
    report.append(f"   Free Space: {disk.get('free_gb', 'N/A')} GB")
    
    memory = results.get('memory', {})
    report.append(f"   Memory Usage: {memory.get('percent_used', 'N/A')}%")
    report.append(f"   Available Memory: {memory.get('available_gb', 'N/A')} GB")
    
    return '\n'.join(report)


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="OpenClaw API Example")
    parser.add_argument("--health", action="store_true", help="Run full health check")
    parser.add_argument("--status", action="store_true", help="Check OpenClaw status")
    parser.add_argument("--git", action="store_true", help="Check Git servers")
    parser.add_argument("--report", action="store_true", help="Generate health report")
    
    args = parser.parse_args()
    
    if args.health:
        results = check_system_health()
        results['timestamp'] = subprocess.check_output(['date']).decode().strip()
        
        if args.report:
            print(generate_health_report(results))
        else:
            print(json.dumps(results, indent=2))
    
    elif args.status:
        client = OpenClawClient()
        status = client.get_status()
        print(json.dumps(status, indent=2))
    
    elif args.git:
        servers = check_git_servers()
        print(json.dumps(servers, indent=2))
    
    else:
        # Default: show help
        print(__doc__)
        print("\nAvailable commands:")
        print("  python3 openclaw_api_example.py --health    # Run full health check")
        print("  python3 openclaw_api_example.py --status    # Check OpenClaw status")
        print("  python3 openclaw_api_example.py --git       # Check Git servers")
        print("  python3 openclaw_api_example.py --health --report  # Generate readable report")


if __name__ == "__main__":
    main()