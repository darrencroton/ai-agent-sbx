# ai-agent-sbx

Agent SBX is a reusable Docker Sandboxes workbench for running Codex, Claude Code, Copilot CLI, OpenCode, and Qwen Code against a target Git repository. It is designed for Project Manager and Orchestrator workflows: one harness can implement a bounded slice while the others provide headless, read-only review evidence.

The workbench is persistent for dependency and tool caches, but each target repository is opened in SBX clone mode. Agents therefore work in a private in-VM clone; they do not receive a writable host mount.

## Contents

- `agent-sbx.sh` creates, enters, and lists named workbenches.
- `kit/spec.yaml` is the local SBX mixin kit. It installs the additional harnesses, tmux, Python 3.13, and the shared `ai-agent-home`/`ai-agent-coder` skill catalogue.
- `config.example.env` is the non-secret model-host configuration template. Copy it to the ignored `config.env` before creating a workbench.

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

Create the local model-host configuration. This file contains hostnames only; API credentials remain in SBX secrets.

```bash
cp config.example.env config.env
# Edit config.env and replace both example hostnames.
```

## Create and use a workbench

```bash
./agent-sbx.sh create /absolute/path/to/target-repository
./agent-sbx.sh shell agent-target-repository
```

The sandbox name is optional. Reuse a name to retain its VM-local caches and private clone; choose a new name for a clean environment.

The first creation downloads the official SBX image and installs the harnesses, so it can take several minutes. Leave the creating terminal attached until it reports `Created sandbox`; do not interrupt it or open a short-lived session during that initial bootstrap.

Inside the workbench, the installed CLIs are available on `PATH`. Project Manager requires Python 3.13 and is invoked through `uv`:

```bash
/home/agent/.local/bin/uv run --python 3.13 python \
  /home/agent/.agents/repos/ai-agent-coder/skills/project-manager/scripts/pm.py profiles
```

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

### Interactive subscription and provider sign-in

After creating a workbench, open a shell in it and authenticate each harness/provider that will be used:

| Tool | First interactive action | Notes |
| --- | --- | --- |
| Codex | None after `sbx secret set -g openai --oauth` | OAuth is completed on the host before sandbox creation. |
| Claude Code | Run `claude`, then `/login` | A Claude subscription is OAuth state, not an Anthropic API key. |
| Copilot CLI | Run `copilot login` or `/login` | Complete the GitHub device/OAuth flow for the subscribed GitHub account. |
| OpenCode | Run `opencode`, then use its provider sign-in flow | Complete a provider login for each subscribed provider required, including GitHub Copilot models or OpenCode Go. |
| Qwen Code | Run `qwen`, then `/auth` | Choose and authenticate the intended provider. |

Do this before launching a harness through Project Manager. Interactive OAuth state belongs to the named workbench and is retained while that sandbox is retained. A new workbench needs its own initial sign-in; it does not copy host-side OpenCode, Qwen, Claude, or Copilot configuration directories.

A GitHub token stored as `sbx secret set -g github` is optional for `gh` and GitHub API automation. It is not the Copilot subscription itself. Similarly, only create an `anthropic` SBX secret when Anthropic API-key billing is intended.

## Model endpoints

Set the two approved Tailscale model-server hostnames in the ignored `config.env`. On creation, the launcher renders them into a temporary kit for both the network allowlist and `local-openai` injection entries. They are intentionally not a broad tailnet wildcard, and the public `kit/spec.yaml` never contains your hostnames.

OpenCode and Qwen Code each need an OpenAI-compatible provider entry that points at the required `/v1` endpoint and uses `LLAMA_SERVER_API_KEY`. Keep those client settings inside the workbench; do not copy host credential stores into it.

## Security model

- Clone mode keeps the host worktree read-only. Review and fetch the sandbox branch before integrating changes locally.
- Outbound network access is deny-by-default. `kit/spec.yaml` is the allowlist and should be reviewed like privileged build configuration.
- Kit installation commands run as root during sandbox creation. Keep this repository local and version-controlled; do not load unreviewed remote kits.
- SBX kits are Early Access. Revalidate the kit after upgrading SBX and recreate a workbench after changing the kit or global credentials.

## Maintenance

The kit composes `ai-agent-home` and `ai-agent-coder` using public HTTPS clones, avoiding a dependency on host SSH keys. Refresh an existing workbench only when a deliberate toolchain update is wanted; otherwise create a new named workbench from the updated kit.
