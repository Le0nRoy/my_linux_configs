# AI Agent Sandboxing Architecture

This document describes the sandboxing infrastructure for Claude, Codex, Cursor, and Hermes. Wrapper sources live in the `ai-wrapper` submodule and are deployed by the parent hook to `~/ai-wrapper`; systemd user units live in this parent repository. Documentation and tests are not deployed by chezmoi.

Hermes has a separate strict Linux profile. The implementation is under review and has not been deployed or fully tested end-to-end here. Descriptions of its source contracts are not claims of successful provider login, private Desktop operation, or live worker restart recovery.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Universal Wrapper](#universal-wrapper)
- [Agent-Specific Wrappers](#agent-specific-wrappers)
- [Managed Hermes Profile](#managed-hermes-profile)
- [Resource Limits](#resource-limits)
- [Filesystem Access](#filesystem-access)
- [Docker and Kubernetes](#docker-and-kubernetes)
- [Security Model](#security-model)
- [Troubleshooting](#troubleshooting)

## Overview

On Linux, AI agents run in bubblewrap namespaces with selected filesystem mounts. The ordinary wrappers also support a macOS `sandbox-exec` backend; Hermes requires Linux.

- **bubblewrap (bwrap)**: Namespace isolation and filesystem binding
- **Protected Hermes registrations**: Fixed runtime/state/workspace paths and per-profile worker capabilities
- **Systemd user slices**: Aggregate limits for supervised Hermes services and workers

The former `prlimit`/`setpriv` execution chain is no longer used. Host network access remains shared, and security depends on the selected policy, mounts, and exposed services.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     User Terminal                           │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              Agent-Specific Wrapper                         │
│    (executable_claude_wrapper.bash, etc.)                   │
│                                                             │
│    Sources agent lib and selects sandbox policy            │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              Agent-Specific Lib                             │
│    (bin/ai_wrapper_data/claude_wrapper_lib.bash, etc.)      │
│                                                             │
│    Sets: AI_WRAPPER_AGENT_NAME, AI_AGENT_COMMAND,           │
│          AI_SYSTEM_PROMPT_FLAG, AI_RESUME_ARGS              │
│    Sources: ai_wrapper_lib.bash                             │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              ai_wrapper_lib.bash (shared)                   │
│                                                             │
│    - Interactive menu (orchestrate/bulletproof/start/resume)│
│    - Prompt loading (orchestrator-prompt, bulletproof)      │
│    - Session dispatch via run_sandboxed_agent               │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│           ai_agent_universal_wrapper.bash                   │
│                                                             │
│    - Validates environment                                  │
│    - Builds bubblewrap arguments                            │
│    - Dispatches to default or strict Hermes policy          │
│    - Executes with bubblewrap on Linux                     │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   Sandboxed Environment                     │
│                                                             │
│    - Isolated namespaces (user, pid, mount, etc.)           │
│    - Limited filesystem view                                │
│    - Hermes supervised units use aggregate cgroup limits   │
│    - Network access (shared)                                │
└─────────────────────────────────────────────────────────────┘
```

## Universal Wrapper

**Source**: `ai-wrapper/bin/ai_agent_universal_wrapper.bash`
**Deployed**: `~/ai-wrapper/bin/ai_agent_universal_wrapper.bash`

The universal wrapper dispatches the ordinary agents to an OS-specific backend. `AI_SANDBOX_AGENT_PROFILE=hermes` selects the separate Linux policy implemented by the Hermes launcher/library; it does not inherit default mounts or passthrough flags.

### Usage

The wrapper is sourced by agent-specific scripts:

```bash
source "$HOME/ai-wrapper/bin/ai_agent_universal_wrapper.bash"

run_sandboxed_agent "claude" \
    -- --bind "${HOME}/.claude" "${HOME}/.claude" \
    -- "$@"
```

### Command Format

```
run_sandboxed_agent COMMAND -- [BWRAP_FLAGS...] -- [CMD_ARGS...]
```

- `COMMAND`: The program to run inside the sandbox
- `BWRAP_FLAGS`: Additional bubblewrap arguments for the ordinary Linux policy; Hermes uses only validated profile mounts and rejects additional bind flags
- `CMD_ARGS`: Arguments passed to the command

## Agent-Specific Wrappers

Each agent has two files: an executable entry-point and an agent-specific lib.

### Shared Menu Library

**Source**: `ai-wrapper/bin/ai_wrapper_data/ai_wrapper_lib.bash`

Sourced by all agent libs. Provides the interactive session menu, prompt loading,
and session dispatch. Requires the calling lib to set:

| Variable | Purpose | Example |
|---|---|---|
| `AI_WRAPPER_AGENT_NAME` | Display name | `"Claude CLI"` |
| `AI_AGENT_COMMAND` | Binary to run | `"claude"` |
| `AI_SYSTEM_PROMPT_FLAG` | System prompt injection flag | `"--append-system-prompt"` |
| `AI_RESUME_ARGS` | Args for resume mode | `(--resume)` |
| `WRAPPER_HELP` | Path to help file | `codex-help.md` |

### Claude Wrapper

**Files**: `ai-wrapper/bin/executable_claude_wrapper.bash`, `ai-wrapper/bin/ai_wrapper_data/claude_wrapper_lib.bash`

```bash
# Binds:
# - ~/.claude (Claude's data directory)
# - Working directory (read-write)
# - ~/AGENTS.md, ~/CLAUDE.md (read-only)
```

### Codex Wrapper

**Files**: `ai-wrapper/bin/executable_codex_wrapper.bash`, `ai-wrapper/bin/ai_wrapper_data/codex_wrapper_lib.bash`

```bash
# Binds:
# - ~/.codex (Codex's data directory)
# - Working directory (read-write)
# - ~/AGENTS.md, ~/CLAUDE.md (read-only)
```

Consult the agent-specific library for its current prompt, account-selection, and resume arguments.

### Cursor Wrapper

**Files**: `ai-wrapper/bin/executable_cursor_agent_wrapper.bash`, `ai-wrapper/bin/ai_wrapper_data/cursor_wrapper_lib.bash`

```bash
# Binds:
# - ~/.cursor (Cursor's data directory)
# - Working directory (read-write)
# - ~/AGENTS.md, ~/CLAUDE.md (read-only)
```

These ordinary wrappers use the default policy described below. Hermes has its own policy and registration flow.

## Managed Hermes Profile

**Sources**: `ai-wrapper/bin/executable_hermes_wrapper.bash`, `ai-wrapper/bin/executable_setup_hermes.bash`, and `ai-wrapper/bin/ai_wrapper_data/hermes_sandbox/`
**Commands**: `~/ai-wrapper/bin/hermes_wrapper.bash` and `~/ai-wrapper/bin/setup_hermes.bash`
**Feature documentation**: [Hermes sandbox](../ai-wrapper/docs/features/hermes-sandbox.md)

The current adapter targets upstream commit `19cb1cbfedeafaca099be6ff0141a28a6c516c0f`. Runtime entry verifies the checkout/source pin before loading Hermes. Required isolation setup has no unsandboxed fallback.

### Setup and Diagnosis

Linux namespaces, Git, bubblewrap, and the reviewed runtime Python are prerequisites. Runtime execution also requires `systemd-run` and a working systemd user manager for mandatory scope budgets. The current preparer requires `/usr/bin/python3` version `3.14.7`; Desktop additionally requires Xpra, Xvfb, xauth, fonts, system shared libraries, and a packaged Desktop with the protected attach-only backend compatibility gates. Host prerequisites are declared and never installed automatically with sudo.

With an existing workspace and private runtime/state parent directories:

```bash
mkdir -p -m 700 "$HOME/.local/share/hermes-runtimes" "$HOME/.local/share/hermes-sandbox/profiles"
~/ai-wrapper/bin/setup_hermes.bash prepare --profile work \
    --runtime "$HOME/.local/share/hermes-runtimes/19cb1cb" \
    --workspace "$HOME/projects/my-project" --dry-run
```

Remove `--dry-run` to explicitly prepare and register. Preparation fetches the fixed upstream pin, validates inputs, installs frozen Python dependencies/private browser assets, and builds the adapted packaged Desktop/web UI inside staging bubblewrap namespaces. Reviewed source-only dependencies use an explicit build allowlist and lock-derived constraints. Native builds may require declared compiler tools, but host build hooks are not run. Successful preparation publishes a new runtime without overwriting an existing destination or starting services. Selected extras and optional dependency exclusions appear in the dry-run/manifest; full live provisioning remains unverified here.

An existing reviewed runtime with its preparation manifest and PM seed can be registered without installation:

```bash
~/ai-wrapper/bin/setup_hermes.bash init --profile work \
    --runtime "$HOME/.local/share/hermes-runtimes/19cb1cb" \
    --workspace "$HOME/projects/my-project"
~/ai-wrapper/bin/setup_hermes.bash doctor --profile work
~/ai-wrapper/bin/hermes_wrapper.bash --profile work
~/ai-wrapper/bin/hermes_wrapper.bash --profile work serve --port 9119
~/ai-wrapper/bin/hermes_wrapper.bash --profile work desktop
```

Choose preparation or registration as appropriate; existing profiles are not overwritten. `register` aliases `init`. `--state DIR` overrides the default `~/.local/share/hermes-sandbox/profiles/NAME`. The profile doctor checks registration, expected revision, adapters, and bubblewrap/systemd-run/socket availability; it does not exercise the user manager or prove a live provider session or runtime integrity by itself.

### Policy and Filesystem Boundary

Profiles use one to 64 lowercase letters/digits/underscores/hyphens and start with a letter or digit. `~/.config/hermes-sandbox/profiles/NAME.json` contains exactly `version: 1`, `runtime`, `state`, and `workspace`. Registry directories are private `0700`; registration creates a separate mode-`0600` `NAME.token` with a random 64-character hexadecimal worker capability.

Canonical absolute paths are required. Symlinks, broad home/system binds, host credential trees, overlapping runtime/state/workspace paths, writable control/policy overlap, and another profile's writable storage are refused. Only a read-only runtime may be shared between registrations.

| Resource | Hermes policy |
|---|---|
| Application checkout and compatibility adapter | Read-only |
| Registered profile state and workspace | Read-write |
| Home, `/tmp`, `/var`, `/run`, processes, devices | Private namespace view |
| System binaries/libraries and selected `/etc` files | Read-only |
| Profile worker token, broker socket, worker snapshot | Selected read-only mounts |
| Desktop transport | Fresh private display socket directory |
| Host D-Bus, systemd runtime, Docker, SSH-agent, host display/browser credentials | Not mounted |

The network namespace is shared and unrestricted. Host loopback/LAN services and Linux abstract AF_UNIX sockets remain reachable; filesystem/process namespace isolation does not restrict that access. This is not full network or host-GUI access isolation.

### Private Desktop and Shared State

The complete Desktop application runs inside bubblewrap under a private Xpra/Xvfb session. The host Xpra client renders the window; the Electron PTY, preview automation, and private browser execute within the profile. Host `DISPLAY`, X11 authentication cookies, and display sockets are not intentionally passed through or mounted. The shared network can nevertheless expose a host X11 abstract socket: `xhost +local` or local-UID trust may admit the sandbox process. Use cookie-authenticated host X11 without local `xhost` grants. Host-native GUI remote mode alone would not confine the PTY or preview and is not the implemented boundary.

Clipboard, drag-and-drop/file transfer, host file/URL opening, audio, and other convenience bridges are disabled deliberately. Adding reviewed bridges is deferred; confined DesktopPTY and preview/`drive_preview` remain core requirements. Xpra/Xvfb were unavailable during development, so the live Desktop workflow still needs acceptance validation.

All frontends/workers select the registered `HERMES_HOME`. Native profile `ROOT` and identity variables are pinned to that state, with native profile lookup/listing/serve restricted to the selected registration or its `default` alias. Native cross-profile multiplexing is not available within this authority; separate registered CLI/gateway instances use their own state/workspace/capability. Managed profile creation/edits and reviewed runtime pin upgrades happen on the host, not through native `hermes update` against the read-only checkout.

Service leases prevent duplicate backend/gateway owners by kind while allowing independent CLI sessions. The state adapter preserves native memory/skill/auth/session transactions and adds configuration locking with three-way conflict checks, admitted-history refresh under the native turn lease, and skill-cache refresh. On the first confined launch, the adapter validates the read-only preparation manifest and atomically seeds a writable PM store at the selected profile's `state/tools`, preserving any existing store and remapping browser paths even for a shared runtime. Setup does not copy/install that seed on the host. These locks coordinate participating processes; they do not protect state integrity against malicious commands with write access. Cross-interface recall, learned skills, session handoff, and live browser/provider workflows still require core acceptance checks.

### Cron/Kanban Supervision

The parent supplies `hermes-control.service`, `hermes-serve@.service`, `hermes-gateway@.service`, `hermes.slice`, and `hermes-workers.slice`. The trusted host broker accesses systemd; profile processes receive only the selected local socket/capability, without host D-Bus.

Requests accept only typed `launch`, `status`, and `cancel` operations for registered `cron`/`kanban` task and attempt IDs. UID verification is combined with a per-profile capability; sharing the host UID does not grant a confined profile another profile's authority. Registry changes require a broker restart.

The broker copies worker input to a protected immutable snapshot and launches a fixed wrapper entry into a fresh sandbox. Workers have independent transient service units with `Restart=no` and `RemainAfterExit=yes`; persisted accepted/adopted/finished records support reconciliation after broker/gateway interruption. Uncertain launches are not replayed. Removed units can produce unknown outcomes. The 1,024-record cap applies to the recent ledger: at capacity, a persisted finished record is moved atomically to protected archival storage, retaining its identity/result/audit hashes for lookup and replay protection. Active/uncertain records are not archived. Matching host snapshot cleanup and confirmed terminal-unit stopping happen only after durable archival; retained cleanup failures may need host maintenance. Archived identities grow on disk over time, a deliberate idempotence tradeoff rather than a lifetime completed-job ceiling. Live restart, cancellation, archival, and result-delivery validation remains outstanding.

Service startup is explicit after deployment/profile setup; see the feature guide for host commands and spool initialization. No live installation or service activation was performed for this documentation work.

### Privacy, Exclusions, and Optional Pack

Private profile state contains user sessions, memory, history, learned code, browser logins, and provider/messaging keys. Its permissions exclude other host users, but those files remain readable and writable inside the profile. Configure profile-specific credentials rather than passing host agent homes or shell secrets. Visible credentials/data can be exfiltrated over the shared network; this design provides no zero-exfiltration guarantee.

Managed Hermes entry points exclude MCP and computer-use from Hermes dispatch and force terminal execution to the local confined backend. Those application-level restrictions are cooperative: a malicious terminal Python/script can bypass tool-selection policy or call network APIs while remaining inside bubblewrap's filesystem/process boundary. They are not a network or arbitrary-code restriction.

The optional catalog supports explicit `hermes_wrapper.bash --profile work addons list` and `addons install NAME`. Two GitHub references are commit/digest pinned; paid/personal packs accept local reviewed archives only. Installation stages inert content without executing installers. `codex-limits` is currently deferred pending a safe adapter; the entire CLIProxyAPI/account-pool subsystem remains deferred.

See [TODO task 15](../TODO.md#15-hermes-sandbox-deferred-options) for MCP/computer-use, egress enforcement, confined Docker/SSH replacements, plugin isolation, private-GUI convenience bridges, live business connectors/importers, and optional add-on verification follow-ups. Core Desktop, shared-state, and worker requirements have not been silently moved to that list.

## Resource Limits

The universal wrapper no longer enforces `RLIMIT_*` through `prlimit`. The parent `hermes.slice` instead sets `CPUQuota=200%`, `MemoryHigh=3G`, `MemoryMax=4G`, and `TasksMax=512`; `hermes-workers.slice` groups independent worker units below it. Interactive CLI/backend/gateway and private Desktop server launches require systemd user scopes in `hermes.slice`, with per-scope `MemoryMax=6G`, `CPUQuota=200%`, and `TasksMax=512`; deployed aggregate limits apply in addition. The host Xpra renderer is outside that scope. These are source contracts, not a claim that the limits are active on this machine.

## Filesystem Access

This section describes the ordinary Linux policy, not the strict Hermes mounts above. Agent wrappers may add their own state/worktree mounts and opt-in credentials.

### Default Read-Only Mounts

```
/usr           # System binaries and libraries
/bin           # Essential binaries
/lib, /lib64   # Shared libraries
/etc           # System configuration
/etc/ssl       # SSL certificates
/etc/hosts     # Host resolution
/etc/resolv.conf   # DNS configuration
```

### Default Read-Write Mounts

```
/tmp           # Temporary files (tmpfs)
/var           # Variable data (tmpfs)
/proc          # Process information
/dev           # Device files
${WORKDIR}     # Current working directory
```

### Agent Data Directories

Each agent gets its data directory mounted read-write:
- Claude: `~/.claude`
- Codex: `~/.codex`
- Cursor: `~/.cursor`

### System-Wide Rules (Read-Only)

When present, these host rule files are mounted read-only by the ordinary Linux policy:
- `~/AGENTS.md`
- `~/CLAUDE.md`

## Docker and Kubernetes

### Docker Access

The ordinary Linux policy exposes host Docker paths only when `AI_SANDBOX_ALLOW_DOCKER=1` and the paths exist. Docker environment/config passthrough has its own `AI_SANDBOX_PASS_DOCKER` flag. Hermes does not expose these paths:

```bash
# Docker socket (read-write)
/run/docker.sock

# Docker runtime directory
/run/docker

# Docker data directory
/var/lib/docker

# Containerd socket (if exists)
/run/containerd/containerd.sock
```

### Kubernetes (kind) Access

For local Kubernetes development:

```text
# kind configuration
~/.kind

# kubectl configuration (mounted from kind_dot_kube)
~/.kube (from ~/kind_dot_kube)
```

### First-Time kind Setup

If kind is not installed in the sandbox:

```bash
# Run inside sandbox
~/ai-wrapper/bin/setup_kind.bash

# Verify
kind version
kubectl version --client
```

## Security Model

### Namespace Isolation

The sandbox uses bubblewrap's namespace features:

```bash
--unshare-all   # Unshare all namespaces
--share-net     # But share network (for internet access)
```

This provides:
- **User namespace**: Isolated user/group mappings
- **PID namespace**: Can't see host processes
- **Mount namespace**: Isolated filesystem view
- **IPC namespace**: Isolated inter-process communication
- **UTS namespace**: Isolated hostname

### Policy-Specific Restrictions

Hermes adds a private home, fixed validated mounts, a cleared environment, and `--cap-drop ALL`. The current wrappers do not use the former external `setpriv` command. The default policy can expose broader host runtime sockets and explicitly opted-in credentials; it must not be described as equivalent to the Hermes profile.

### Path Validation

The wrapper validates all bind mount paths:

```bash
BWRAP_STRICT=1  # Fail on missing paths
BWRAP_STRICT=0  # Warn and skip missing paths (default)
```

### Ordinary Wrapper Capabilities

- Read/write files in the working directory
- Read/write their own data directory
- Access the network
- Run Docker containers when host Docker access is explicitly enabled
- Create Kubernetes clusters (via kind)
- Execute programs from /usr, /bin

### Boundary Limits

Namespaces restrict the directly visible filesystem and processes. This is not an absolute host-safety guarantee: writable mounts, host services exposed through sockets or shared networking, supplied credentials, and kernel/runtime defects can expand impact. The default policy mounts the host user runtime directory when available, so a blanket claim that host IPC is inaccessible would be incorrect. A read-only credential/socket mount does not prevent reading credentials or invoking operations offered by its service.

## Exit Code Translation

The wrapper translates common error codes:

| Code | Meaning | Common Cause |
|------|---------|--------------|
| 126 | Not executable | Permission issue |
| 127 | Not found | Missing command or library |
| 137 | Killed (SIGKILL) | Resource limit exceeded |
| 139 | Segfault | Bug or incompatibility |
| 143 | Terminated (SIGTERM) | External termination |

## Troubleshooting

### "User namespaces not enabled"

```bash
# Check current setting
sysctl kernel.unprivileged_userns_clone

# Enable (requires root)
echo 'kernel.unprivileged_userns_clone = 1' | sudo tee /etc/sysctl.d/00-unpriv-ns.conf
sudo sysctl --system
```

### "Command not found inside sandbox"

The command must exist in the bind-mounted paths. Check:
- Is it in `/usr/bin` or `/bin`?
- Is it in `~/bin` (which is mounted)?

### "Bind source path does not exist"

The wrapper skips missing bind paths by default. To fail instead:

```bash
BWRAP_STRICT=1 run_sandboxed_agent ...
```

### Docker Not Working

1. Check Docker socket exists: `ls -la /run/docker.sock`
2. Check user is in docker group: `groups`
3. Check Docker daemon is running: `systemctl status docker`

### Resource Limit Exceeded

The wrappers no longer set `RLIMIT_*` limits. For Hermes, inspect `hermes.slice`, the execution scope/worker unit, and the user journal for cgroup memory/task limits or process failures. An exit code such as 137 alone does not prove which limit caused termination. Review the parent slice and protected scope settings rather than changing obsolete wrapper rlimit variables.

### Hermes Prerequisites or Credentials Missing

Use `setup_hermes.bash doctor --profile NAME` for profile diagnosis and the [feature guide](../ai-wrapper/docs/features/hermes-sandbox.md#prerequisites) for pre-registration checks. Execution requires a working systemd user manager as well as bubblewrap. Private Desktop additionally requires the declared host dependencies and adapted package; do not mount host GUI sockets to bypass that requirement. Provider credentials must be configured inside the selected profile.

## Related Documentation

- [Repository Overview](repository-overview.md)
- [AGENTS.md](../AGENTS.md) - AI agent rules and guidelines
- [bubblewrap documentation](https://github.com/containers/bubblewrap)
