#!/usr/bin/env bash
# Create or enter a persistent SBX clone-mode workbench for one target repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$SCRIPT_DIR/kit"
CONFIG="$SCRIPT_DIR/config.env"

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

prepare_kit() {
  [[ -f "$CONFIG" ]] || { echo "Missing $CONFIG. Copy config.example.env and set the approved model hosts." >&2; exit 1; }
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG"
  set +a
  for host in "${MODEL_HOST_1:-}" "${MODEL_HOST_2:-}"; do
    [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "MODEL_HOST_1 and MODEL_HOST_2 must be hostnames only." >&2; exit 2; }
  done
  rendered_kit="$(mktemp -d)"
  cp -R "$KIT/." "$rendered_kit"
  MODEL_HOST_1="$MODEL_HOST_1" MODEL_HOST_2="$MODEL_HOST_2" perl -0pi -e 's/__MODEL_HOST_1__/$ENV{MODEL_HOST_1}/g; s/__MODEL_HOST_2__/$ENV{MODEL_HOST_2}/g' "$rendered_kit/spec.yaml"
}

case "${1:-}" in
  create)
    repo="${2:-}"
    [[ -n "$repo" && -d "$repo" ]] || { echo "create needs a Git worktree path." >&2; exit 2; }
    git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "create needs a Git worktree path." >&2; exit 2; }
    repo="$(cd "$repo" && pwd)"
    name="${3:-agent-$(basename "$repo")}" 
    require_sbx
    [[ -f "$KIT/spec.yaml" ]] || { echo "Missing kit: $KIT/spec.yaml" >&2; exit 1; }
    prepare_kit
    trap 'rm -rf "$rendered_kit"' EXIT
    sbx create --clone --name "$name" --kit "$rendered_kit" codex "$repo"
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
