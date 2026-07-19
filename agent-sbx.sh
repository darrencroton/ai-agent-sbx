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
  agent-sbx.sh refresh <sandbox-name>
  agent-sbx.sh status

create uses SBX clone mode: agents work in a private in-VM clone and the host
checkout remains read-only. Re-run with the same sandbox name to reuse caches.
EOF
}

require_sbx() {
  command -v sbx >/dev/null || { echo "sbx is not installed or not on PATH." >&2; exit 1; }
}

install_private_file() {
  local sandbox_name="$1"
  local source_name="$2"
  local destination="$3"

  [[ -f "$SCRIPT_DIR/$source_name" ]] || return 0
  sbx exec "$sandbox_name" mkdir -p "$(dirname "$destination")"
  sbx cp "$SCRIPT_DIR/$source_name" "$sandbox_name:$destination"
}

install_private_files() {
  install_private_file "$1" "sandbox.bashrc" "/home/agent/.bashrc"
  install_private_file "$1" "sandbox.opencode" "/home/agent/.config/opencode/opencode.json"
  install_private_file "$1" "sandbox.qwen" "/home/agent/.qwen/settings.json"
}

load_config() {
  [[ -f "$CONFIG" ]] || { echo "Missing $CONFIG. Copy config.example.env and set the approved model hosts." >&2; exit 1; }
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG"
  set +a
  for host in "${MODEL_HOST_1:-}" "${MODEL_HOST_2:-}"; do
    [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "MODEL_HOST_1 and MODEL_HOST_2 must be hostnames only." >&2; exit 2; }
  done
  declare -p EXTRA_NETWORK_DOMAINS >/dev/null 2>&1 || EXTRA_NETWORK_DOMAINS=()
  declare -p READ_ONLY_PATHS >/dev/null 2>&1 || READ_ONLY_PATHS=()
  declare -p READ_WRITE_PATHS >/dev/null 2>&1 || READ_WRITE_PATHS=()
  extra_network_yaml=""
  for domain in "${EXTRA_NETWORK_DOMAINS[@]}"; do
    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "EXTRA_NETWORK_DOMAINS entries must be hostnames only." >&2; exit 2; }
    extra_network_yaml+="    - $domain"$'\n'
  done
  mount_args=()
  for path in "${READ_ONLY_PATHS[@]}"; do
    [[ "$path" == /* && -d "$path" && "$path" != "/" && "$path" != "$HOME" ]] || { echo "READ_ONLY_PATHS entries must be existing, non-home absolute directories." >&2; exit 2; }
    mount_args+=("$(cd "$path" && pwd -P):ro")
  done
  for path in "${READ_WRITE_PATHS[@]}"; do
    [[ "$path" == /* && -d "$path" && "$path" != "/" && "$path" != "$HOME" ]] || { echo "READ_WRITE_PATHS entries must be existing, non-home absolute directories." >&2; exit 2; }
    mount_args+=("$(cd "$path" && pwd -P)")
  done
}

prepare_kit() {
  load_config
  rendered_kit="$(mktemp -d)"
  cp -R "$KIT/." "$rendered_kit"
  MODEL_HOST_1="$MODEL_HOST_1" MODEL_HOST_2="$MODEL_HOST_2" EXTRA_NETWORK_YAML="$extra_network_yaml" perl -0pi -e 's/__MODEL_HOST_1__/$ENV{MODEL_HOST_1}/g; s/__MODEL_HOST_2__/$ENV{MODEL_HOST_2}/g; s/    # __EXTRA_NETWORK_DOMAINS__\n/$ENV{EXTRA_NETWORK_YAML}/g' "$rendered_kit/spec.yaml"
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
    sbx create --clone --name "$name" --kit "$rendered_kit" codex "$repo" "${mount_args[@]}"
    install_private_files "$name"
    echo "Created $name. Enter it with: $0 shell $name"
    ;;
  refresh)
    name="${2:-}"
    [[ -n "$name" ]] || { usage; exit 2; }
    require_sbx
    load_config
    domains=("chatgpt.com" "$MODEL_HOST_1" "$MODEL_HOST_2" "${EXTRA_NETWORK_DOMAINS[@]}")
    domain_list="$(IFS=,; echo "${domains[*]}")"
    sbx policy allow network --sandbox "$name" "$domain_list"
    echo "Refreshed the scoped network allowlist for $name."
    echo "Changing model hosts, credentials, tools, or READ_ONLY_PATHS/READ_WRITE_PATHS requires a new sandbox."
    ;;
  shell)
    name="${2:-}"
    [[ -n "$name" ]] || { usage; exit 2; }
    require_sbx
    install_private_files "$name"
    sbx exec -it "$name" bash
    ;;
  status)
    require_sbx
    sbx ls
    ;;
  -h|--help|help|'') usage ;;
  *) usage; exit 2 ;;
esac
