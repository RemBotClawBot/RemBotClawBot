#!/usr/bin/env bash
# generate-health-report.sh
# Wrapper around examples/openclaw_api_example.py that exports timestamped
# health reports (JSON, text, HTML) and optionally sends summaries to webhooks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/reports}"
FORMATS="${FORMATS:-json,html,text}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
WEBHOOK_URL="${WEBHOOK_URL:-}"
VERBOSE=${VERBOSE:-1}

usage() {
  cat <<'USAGE'
Usage: generate-health-report.sh [options]

Options:
  -o, --output-dir <dir>     Directory for generated reports (default: ./reports)
  -f, --formats <list>       Comma-separated formats: json,html,text (default: json,html,text)
  -r, --retention-days <n>   Delete reports older than N days (default: 14)
  -w, --webhook <url>        POST summary payload to webhook URL
  -q, --quiet                Suppress console output (except errors)
  -h, --help                 Show this help message

Environment overrides:
  PYTHON_BIN, OUTPUT_DIR, FORMATS, RETENTION_DAYS, WEBHOOK_URL, VERBOSE

Examples:
  ./scripts/generate-health-report.sh -o /var/reports -f json,html
  OUTPUT_DIR=/srv/reports WEBHOOK_URL=https://hooks.slack.com/... ./scripts/generate-health-report.sh
USAGE
}

log() {
  if [[ "$VERBOSE" -gt 0 ]]; then
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: missing required command '$1'" >&2
    exit 1
  fi
}

check_python_module() {
  local module="$1"
  if ! "$PYTHON_BIN" - <<PY >/dev/null 2>&1
import importlib
import sys
try:
    importlib.import_module("$module")
except ImportError:
    sys.exit(1)
PY
  then
    echo "Error: Python module '$module' is required. Install via 'pip install $module'." >&2
    exit 1
  fi
}

# Parse CLI args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -f|--formats)
      FORMATS="$2"
      shift 2
      ;;
    -r|--retention-days)
      RETENTION_DAYS="$2"
      shift 2
      ;;
    -w|--webhook)
      WEBHOOK_URL="$2"
      shift 2
      ;;
    -q|--quiet)
      VERBOSE=0
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command "$PYTHON_BIN"
require_command "date"
require_command "mkdir"
require_command "find"

check_python_module "psutil"

API_SCRIPT="$REPO_ROOT/examples/openclaw_api_example.py"
if [[ ! -f "$API_SCRIPT" ]]; then
  echo "Error: Cannot locate examples/openclaw_api_example.py in $REPO_ROOT" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
TIMESTAMP="$(date -u '+%Y%m%d-%H%M%SZ')"
FORMATS_LIST=${FORMATS//,/ }
OUTPUT_PATHS=()
JSON_FILE=""

for format in $FORMATS_LIST; do
  case "$format" in
    json)
      TARGET="$OUTPUT_DIR/health-$TIMESTAMP.json"
      log "Generating JSON report -> $TARGET"
      if "$PYTHON_BIN" "$API_SCRIPT" --health --json >"$TARGET"; then
        OUTPUT_PATHS+=("$TARGET")
        JSON_FILE="$TARGET"
      else
        echo "Warning: failed to generate JSON report" >&2
      fi
      ;;
    html)
      TARGET="$OUTPUT_DIR/health-$TIMESTAMP.html"
      log "Generating HTML report -> $TARGET"
      if "$PYTHON_BIN" "$API_SCRIPT" --health --html >"$TARGET"; then
        OUTPUT_PATHS+=("$TARGET")
      else
        echo "Warning: failed to generate HTML report" >&2
      fi
      ;;
    text|txt|report)
      TARGET="$OUTPUT_DIR/health-$TIMESTAMP.txt"
      log "Generating text report -> $TARGET"
      if "$PYTHON_BIN" "$API_SCRIPT" --health --report >"$TARGET"; then
        OUTPUT_PATHS+=("$TARGET")
      else
        echo "Warning: failed to generate text report" >&2
      fi
      ;;
    *)
      echo "Warning: unsupported format '$format' (use json, html, text)" >&2
      ;;
  esac
done

# Prune old reports
if [[ -n "$RETENTION_DAYS" ]]; then
  log "Pruning reports older than $RETENTION_DAYS days from $OUTPUT_DIR"
  find "$OUTPUT_DIR" -type f -mtime "+$RETENTION_DAYS" -print -delete || true
fi

# Optional webhook notification
if [[ -n "$WEBHOOK_URL" && -n "$JSON_FILE" && -f "$JSON_FILE" ]]; then
  log "Sending webhook summary"
  export HEALTH_JSON="$JSON_FILE"
  SUMMARY_PAYLOAD=$("$PYTHON_BIN" - <<'PY'
import json
import os
from pathlib import Path
import datetime

path = Path(os.environ['HEALTH_JSON'])
data = json.loads(path.read_text())

def get_status():
    status = data.get('openclaw_status', {})
    if isinstance(status, dict) and status:
        return status.get('Status', 'unknown')
    return 'unknown'

def get_disk():
    disk = data.get('disk', {})
    return disk.get('percent_used')

def get_memory():
    memory = data.get('memory', {})
    return memory.get('percent_used')

def get_git(server):
    info = data.get('git_servers', {}).get(server, {})
    return 'online' if info.get('status') else 'offline'

payload = {
    "text": "RemBot health report generated",
    "timestamp": datetime.datetime.utcnow().isoformat() + 'Z',
    "openclaw_status": get_status(),
    "disk_used_percent": get_disk(),
    "memory_used_percent": get_memory(),
    "forgejo": get_git('forgejo'),
    "gitea": get_git('gitea'),
    "report": str(path)
}
print(json.dumps(payload))
PY
  )
  curl -sS -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$SUMMARY_PAYLOAD" >/dev/null || echo "Warning: webhook notification failed" >&2
fi

log "Generated reports:"
for path in "${OUTPUT_PATHS[@]:-}"; do
  [[ -n "$path" ]] && echo "  - $path"
done
