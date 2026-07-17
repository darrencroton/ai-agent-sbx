#!/usr/bin/env bash
# Create or enter a persistent SBX clone-mode workbench for one target repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$SCRIPT_DIR/kit"

usage() {
  cat <<'EOF'
Usage:
  agent-sbx.sh create <target-repo> [sandbox-name]
  agent-sbx.sh shell <sandbox-name>
  agent-sbx.sh status

create uses SBX clone mode: agents work in a private in-VM clone and the host
checkout remains read-only. Re-run with the same sandbox name to reuse caches.
EOF
}

require_sbx() {
  command -v sbx >/dev/null || { echo "sbx is not installed or not on PATH." >&2; exit 1; }
}

case "${1:-}" in
  create)
    repo="${2:-}"
    [[ -n "$repo" && -d "$repo/.git" ]] || { echo "create needs a Git worktree path." >&2; exit 2; }
    repo="$(cd "$repo" && pwd)"
    name="${3:-agent-$(basename "$repo")}" 
    require_sbx
    [[ -f "$KIT/spec.yaml" ]] || { echo "Missing kit: $KIT/spec.yaml" >&2; exit 1; }
    sbx create --clone --name "$name" --kit "$KIT" codex "$repo"
    echo "Created $name. Enter it with: $0 shell $name"
    ;;
  shell)
    name="${2:-}"
    [[ -n "$name" ]] || { usage; exit 2; }
    require_sbx
    sbx exec -it "$name" bash
    ;;
  status)
    require_sbx
    sbx ls
    ;;
  -h|--help|help|'') usage ;;
  *) usage; exit 2 ;;
esac
