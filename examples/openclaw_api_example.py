#!/usr/bin/env python3
"""
OpenClaw API Example - Python client for RemBotClawBot
Demonstrates how to interact with OpenClaw programmatically
"""

import json
import os
import subprocess
import sys
from datetime import datetime
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
    if isinstance(status, dict) and 'error' in status:
        report.append(f"   Status: ERROR - {status['error']}")
    elif isinstance(status, dict) and status:
        report.append("   Status: OPERATIONAL")
        for key, value in status.items():
            report.append(f"   {key}: {value}")
    else:
        report.append("   Status: UNKNOWN")
    
    # Gateway
    report.append("")
    report.append("2. Gateway")
    gateway = results.get('gateway', {})
    gateway_output = gateway.get('output', '') if isinstance(gateway, dict) else ''
    if isinstance(gateway_output, str) and 'running' in gateway_output.lower():
        report.append("   Status: RUNNING")
    elif gateway_output:
        report.append(f"   Status: {gateway_output}")
    else:
        report.append("   Status: UNKNOWN")
    
    # Git servers
    report.append("")
    report.append("3. Git Servers")
    git_servers = results.get('git_servers', {})
    for server, info in git_servers.items():
        status_label = "✓ ONLINE" if info.get('status') else "✗ OFFLINE"
        report.append(f"   {server.capitalize()} (port {info.get('port', 'N/A')}): {status_label}")
    
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


def generate_html_report(results: Dict[str, Any]) -> str:
    """Generate an HTML health report"""
    timestamp = results.get('timestamp', 'N/A')
    disk = results.get('disk', {})
    memory = results.get('memory', {})
    git_servers = results.get('git_servers', {})
    gateway = results.get('gateway', {})
    gateway_output = gateway.get('output', '') if isinstance(gateway, dict) else ''
    openclaw_status = results.get('openclaw_status', {})

    forgejo = git_servers.get('forgejo', {})
    gitea = git_servers.get('gitea', {})
    forgejo_status = "Online" if forgejo.get('status') else "Offline"
    gitea_status = "Online" if gitea.get('status') else "Offline"

    html = f"""
<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <title>RemBot Health Report</title>
  <style>
    body {{ font-family: 'Inter', system-ui, -apple-system, sans-serif; margin: 2rem; background: #0f172a; color: #e2e8f0; }}
    h1 {{ font-size: 1.75rem; margin-bottom: 0.5rem; }}
    .timestamp {{ color: #94a3b8; margin-bottom: 1.5rem; }}
    section {{ margin-bottom: 2rem; padding: 1.5rem; background: #1e293b; border-radius: 1rem; box-shadow: 0 8px 20px rgba(15,23,42,0.6); }}
    table {{ width: 100%; border-collapse: collapse; margin-top: 1rem; }}
    th, td {{ padding: 0.75rem 1rem; border-bottom: 1px solid #334155; text-align: left; }}
    th {{ color: #94a3b8; text-transform: uppercase; font-size: 0.75rem; letter-spacing: 0.08em; }}
    .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1rem; margin-top: 1rem; }}
    .card {{ background: #0f172a; padding: 1rem; border-radius: 0.75rem; border: 1px solid #1f2937; }}
    .value {{ font-size: 1.5rem; font-weight: 600; }}
    .label {{ color: #94a3b8; text-transform: uppercase; letter-spacing: 0.08em; font-size: 0.7rem; }}
  </style>
</head>
<body>
  <h1>RemBot Infrastructure Health</h1>
  <div class=\"timestamp\">Generated: {timestamp}</div>

  <section>
    <h2>Platform Status</h2>
    <div class=\"grid\">
      <div class=\"card\">
        <div class=\"label\">OpenClaw</div>
        <div class=\"value\">{openclaw_status.get('Status', 'Unknown')}</div>
      </div>
      <div class=\"card\">
        <div class=\"label\">Gateway</div>
        <div class=\"value\">{gateway_output or 'Unknown'}</div>
      </div>
      <div class=\"card\">
        <div class=\"label\">Forgejo</div>
        <div class=\"value\">{forgejo_status}</div>
      </div>
      <div class=\"card\">
        <div class=\"label\">Gitea</div>
        <div class=\"value\">{gitea_status}</div>
      </div>
    </div>
  </section>

  <section>
    <h2>Resource Utilization</h2>
    <div class=\"grid\">
      <div class=\"card\">
        <div class=\"label\">Disk Usage</div>
        <div class=\"value\">{disk.get('percent_used', 'N/A')}%</div>
        <div>{disk.get('used_gb', 'N/A')} GB / {disk.get('total_gb', 'N/A')} GB</div>
      </div>
      <div class=\"card\">
        <div class=\"label\">Memory Usage</div>
        <div class=\"value\">{memory.get('percent_used', 'N/A')}%</div>
        <div>{memory.get('used_gb', 'N/A')} GB / {memory.get('total_gb', 'N/A')} GB</div>
      </div>
    </div>
  </section>

  <section>
    <h2>Git Services</h2>
    <table>
      <thead>
        <tr><th>Service</th><th>Port</th><th>Status</th></tr>
      </thead>
      <tbody>
        <tr><td>Forgejo</td><td>{forgejo.get('port', '3001')}</td><td>{forgejo_status}</td></tr>
        <tr><td>Gitea</td><td>{gitea.get('port', '3000')}</td><td>{gitea_status}</td></tr>
      </tbody>
    </table>
  </section>
</body>
</html>
"""

    return html

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="OpenClaw API Example")
    parser.add_argument("--health", action="store_true", help="Run full health check")
    parser.add_argument("--status", action="store_true", help="Check OpenClaw status")
    parser.add_argument("--git", action="store_true", help="Check Git servers")
    parser.add_argument("--report", action="store_true", help="Generate text health report")
    parser.add_argument("--html", action="store_true", help="Generate HTML health report")
    parser.add_argument("--json", action="store_true", help="Force JSON output (default)")
    
    args = parser.parse_args()
    
    if args.health:
        results = check_system_health()
        results['timestamp'] = datetime.utcnow().isoformat() + "Z"
        
        if args.html:
            output = generate_html_report(results)
        elif args.report:
            output = generate_health_report(results)
        else:
            output = json.dumps(results, indent=2)
        
        if args.json and not args.html and not args.report:
            output = json.dumps(results, indent=2)
        
        print(output)
    
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
        print("  python3 openclaw_api_example.py --health            # Run full health check")
        print("  python3 openclaw_api_example.py --status            # Check OpenClaw status")
        print("  python3 openclaw_api_example.py --git               # Check Git servers")
        print("  python3 openclaw_api_example.py --health --report   # Generate text report")
        print("  python3 openclaw_api_example.py --health --html     # Generate HTML dashboard")
        print("  python3 openclaw_api_example.py --health --json     # Force JSON output")


if __name__ == "__main__":
    main()