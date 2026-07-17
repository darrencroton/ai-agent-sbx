# ai-agent-sbx

Agent SBX is a reusable Docker Sandboxes workbench for running Codex, Claude Code, Copilot CLI, OpenCode, and Qwen Code against a target Git repository. It is designed for Project Manager and Orchestrator workflows: one harness can implement a bounded slice while the others provide headless, read-only review evidence.

The workbench is persistent for dependency and tool caches, but each target repository is opened in SBX clone mode. Agents therefore work in a private in-VM clone; they do not receive a writable host mount.

## Contents

- `agent-sbx.sh` creates, enters, refreshes network rules for, and lists named workbenches.
- `kit/spec.yaml` is the local SBX mixin kit. It installs the additional harnesses, tmux, Python 3.13, and the shared `ai-agent-home`/`ai-agent-coder` skill catalogue.
- `config.example.env` is the non-secret model-host configuration template. Copy it to the ignored `config.env` before creating a workbench.
- `sandbox.bashrc` is an optional ignored private Bash profile for portable shell conveniences inside a workbench.

## Requirements

- Docker Sandboxes (`sbx`) 0.35 or newer, authenticated and running.
- A Git worktree to use as the target repository.
- Host-side credentials stored with `sbx secret`; no credential directories are mounted into the workbench.

On a new SBX installation, initialize the global network policy once. This kit is designed for deny-by-default policy:

```bash
sbx policy init deny-all
```

Validate the kit before first use and whenever it changes:

```bash
sbx kit validate kit
```

Create the local model-host configuration once. This file contains hostnames and your explicit project-access allowlists only; API credentials remain in SBX secrets. Do not overwrite an existing `config.env`.

```bash
[[ -f config.env ]] || cp config.example.env config.env
# Edit config.env and replace both example hostnames.
```

## Create and use a workbench

If your checkout does not preserve the executable bit, enable the launcher once:

```bash
chmod +x agent-sbx.sh
```

```bash
# Let the launcher derive a name such as agent-mimic.
./agent-sbx.sh create /absolute/path/to/target-repository

# Or choose a stable name explicitly.
./agent-sbx.sh create /absolute/path/to/target-repository my-mimic

# Open an interactive Bash terminal in the sandbox and its private clone.
./agent-sbx.sh shell my-mimic
```

`create` expects an existing local Git checkout (including a linked Git worktree). It does not modify that checkout or give the sandbox write access to it. In clone mode, SBX creates a separate private Git clone inside the VM for all work and leaves the host checkout available read-only at `/run/sandbox/source`. Commits made in the private clone can be fetched back through the sandbox remote before the sandbox is removed.

The target path is required. To work on a GitHub repository that is not on disk yet, clone it on the host first, then pass its local path. You can clone additional repositories inside a workbench, but those clones are not managed by SBX clone mode and will not receive a sandbox remote automatically.

The second `create` argument is the optional sandbox name. Without it, the launcher derives `agent-<repository-directory-name>`; for example, `~/Local/git-repos/mimic` becomes `agent-mimic`. Reuse a name to retain its VM-local caches and private clone; choose a new name for a clean environment.

The first creation downloads the official SBX image and installs the harnesses, so it can take several minutes. Leave the creating terminal attached until it reports `Created sandbox`; do not interrupt it or open a short-lived session during that initial bootstrap.

Inside the workbench, the installed CLIs are available on `PATH`. Project Manager requires Python 3.13 and is invoked through `uv`:

```bash
/home/agent/.local/bin/uv run --python 3.13 python \
  /home/agent/.agents/repos/ai-agent-coder/skills/project-manager/scripts/pm.py profiles
```

### Optional private shell profile

If `sandbox.bashrc` exists beside the launcher, it is copied to `/home/agent/.bashrc` whenever `create` or `shell` runs. The file is ignored by Git. The launcher therefore owns that sandbox file: edit the private host-side `sandbox.bashrc`, not the copy inside the VM. Use it only for portable shell convenience such as aliases and history settings; do not copy a full host `.zshrc`, credentials, SSH aliases, macOS paths, or host-control functions into the sandbox.

## Common SBX lifecycle commands

Run these on the host, not inside a sandbox:

```bash
# List sandboxes and their state.
./agent-sbx.sh status

# Re-enter a persistent sandbox.
./agent-sbx.sh shell my-mimic

# Stop a sandbox without deleting its private clone, caches, or login state.
sbx stop my-mimic

# Start it again by opening a shell.
./agent-sbx.sh shell my-mimic

# Apply the current config.env network allowlist to this existing sandbox.
./agent-sbx.sh refresh my-mimic
```

To permanently remove a clone-mode sandbox, first preserve any work that has not been integrated into the host repository:

```bash
# Fetch sandbox branches into refs/sandboxes/my-mimic/ on the host.
git fetch sandbox-my-mimic

# Permanently remove the sandbox, its private clone, caches, and login state.
sbx rm my-mimic
```

`sbx rm` is irreversible. SBX will warn if the sandbox has clone-mode commits that have not been fetched. `refresh` updates only an existing sandbox's scoped network rules. Model hosts and credentials, installed tools, and read-only/read-write path mounts are creation-time boundaries, so change those by creating a new named sandbox.

## Credentials

SBX stores global service credentials in the host OS keychain. They are injected by the host proxy only for the domains declared by the base agent or `kit/spec.yaml`; the VM receives a non-secret placeholder rather than the raw value.

There are two authentication paths:

- **SBX-managed credentials** are configured on the host before creating a workbench. Use these for Codex OAuth and for API keys that must never enter the VM.
- **Interactive subscription sign-in** is completed once inside each persistent workbench. The relevant CLI stores its own OAuth state in that workbench, then Project Manager can reuse the authenticated CLI for later headless sessions.

### Host-side SBX credentials

Set only the services that require host-side proxy injection:

```bash
# Codex OAuth on the host.
sbx secret set -g openai --oauth

# OpenAI-compatible local model servers declared by this kit.
sbx secret set -g local-openai
```

Enter a secret value only at the interactive prompt. Do not supply it on a command line, save it in this repository, or mount a host configuration directory. After changing a global secret, create a new workbench for it to take effect.

`local-openai` supplies the placeholder environment variable `LLAMA_SERVER_API_KEY` and injects it as an `Authorization: Bearer` header solely for the configured model hosts. It is optional when those hosts do not require authentication.

### Subscription and provider sign-in

Complete the Codex OAuth step on the host before creating a workbench. After creating it, open a shell inside it and authenticate each other harness/provider that will be used:

| Tool | Where to authenticate | First action | Notes |
| --- | --- | --- | --- |
| Codex | Host, before creation | `sbx secret set -g openai --oauth` | OAuth is injected into the sandbox by SBX; do not run `sbx` inside the sandbox. |
| Claude Code | Inside the sandbox | Run `claude`, then `/login` | A Claude subscription is OAuth state, not an Anthropic API key. |
| Copilot CLI | Inside the sandbox | Run `copilot login` or `/login` | Complete the GitHub device/OAuth flow for the subscribed GitHub account. |
| OpenCode | Inside the sandbox | Run `opencode`, then use its provider sign-in flow | Complete a provider login for each subscribed provider required, including GitHub Copilot models or OpenCode Go. |
| Qwen Code | Inside the sandbox | Run `qwen`, then `/auth` | Choose and authenticate the intended provider. |

Do this before launching a harness through Project Manager. Interactive OAuth state belongs to the named workbench and is retained while that sandbox is retained. A new workbench needs its own initial sign-in; it does not copy host-side OpenCode, Qwen, Claude, or Copilot configuration directories.

A GitHub token stored as `sbx secret set -g github` is optional for `gh` and GitHub API automation. It is not the Copilot subscription itself. Similarly, only create an `anthropic` SBX secret when Anthropic API-key billing is intended.

## Model endpoints

Set the two approved Tailscale model-server hostnames in the ignored `config.env`. On creation, the launcher renders them into a temporary kit for both the network allowlist and `local-openai` injection entries. They are intentionally not a broad tailnet wildcard, and the public `kit/spec.yaml` never contains your hostnames.

OpenCode and Qwen Code each need an OpenAI-compatible provider entry that points at the required `/v1` endpoint and uses `LLAMA_SERVER_API_KEY`. Keep those client settings inside the workbench; do not copy host credential stores into it.

## Project-specific network and data access

`config.env` is also the private, explicit allowlist for project-specific access. It supports three Bash arrays:

```bash
# Hosts needed by an additional provider or documented project download.
EXTRA_NETWORK_DOMAINS=("example-provider.com" "data.example.org")

# Large immutable simulation inputs, exposed read-only in the sandbox.
READ_ONLY_PATHS=("/absolute/path/to/simulation-data")

# A dedicated results directory, exposed read/write in the sandbox.
READ_WRITE_PATHS=("/absolute/path/to/mimic-results")
```

Every configured path must already exist, be absolute, and cannot be `/` or the entire home directory. Paths retain their absolute location inside the sandbox. Prefer a read-only data directory and a separate read/write results directory; do not mount a broad parent directory just for convenience. `chatgpt.com` is already included for Codex.

Configuration changes have two different effects: after changing only `EXTRA_NETWORK_DOMAINS`, run `./agent-sbx.sh refresh <sandbox-name>` to apply the additional scoped network rules to an existing sandbox. After changing model hosts, model credentials, or either path array, create a new named sandbox because those are creation-time boundaries.

## Security model

- Clone mode keeps the host worktree read-only. Review and fetch the sandbox branch before integrating changes locally.
- Outbound network access is deny-by-default. The public `kit/spec.yaml` plus the private values rendered from `config.env` form the allowlist and should be reviewed like privileged build configuration.
- Kit installation commands run as root during sandbox creation. Keep this repository local and version-controlled; do not load unreviewed remote kits.
- SBX kits are Early Access. Revalidate the kit after upgrading SBX and recreate a workbench after changing the kit or global credentials.

## Maintenance

The kit composes `ai-agent-home` and `ai-agent-coder` using public HTTPS clones, avoiding a dependency on host SSH keys. Use `refresh` only to apply an updated network allowlist to an existing sandbox. Create a new named workbench after a kit, toolchain, mount, model-host, or credential change.

Qwen Code is configured to use the system `rg` binary rather than its bundled ARM64 ripgrep binary. This avoids a known `jemalloc: Unsupported system page size` failure in some Linux ARM64 microVMs.
