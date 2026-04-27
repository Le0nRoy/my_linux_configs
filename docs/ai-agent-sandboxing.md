# AI Agent Sandboxing Architecture

This document describes the sandboxing infrastructure for AI development assistants (Claude, Codex, Cursor).

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Universal Wrapper](#universal-wrapper)
- [Agent-Specific Wrappers](#agent-specific-wrappers)
- [Resource Limits](#resource-limits)
- [Filesystem Access](#filesystem-access)
- [Docker and Kubernetes](#docker-and-kubernetes)
- [Security Model](#security-model)
- [Troubleshooting](#troubleshooting)

## Overview

AI agents run in isolated sandboxes using:

- **bubblewrap (bwrap)**: Namespace isolation and filesystem binding
- **prlimit**: Resource limits (CPU, memory, file descriptors)
- **setpriv**: Privilege restriction

This provides defense-in-depth while allowing productive development work.

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
│    Sources agent lib, sets RLIMIT_* and bind mounts         │
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
│    - Executes with setpriv + bwrap + prlimit                │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   Sandboxed Environment                     │
│                                                             │
│    - Isolated namespaces (user, pid, mount, etc.)           │
│    - Limited filesystem view                                │
│    - Resource-constrained                                   │
│    - Network access (shared)                                │
└─────────────────────────────────────────────────────────────┘
```

## Universal Wrapper

**File**: `bin/ai_agent_universal_wrapper.bash`

The universal wrapper provides the core sandboxing logic used by all agent wrappers.

### Usage

The wrapper is sourced by agent-specific scripts:

```bash
source ai_agent_universal_wrapper.bash

RLIMIT_AS=$((8*1024*1024*1024))   # 8GB address space
RLIMIT_CPU=3600                    # 1 hour CPU time
RLIMIT_NOFILE=4096                 # File descriptors
RLIMIT_NPROC=256                   # Processes

run_sandboxed_agent "claude" \
    -- --bind "${HOME}/.claude" "${HOME}/.claude" \
    -- "$@"
```

### Command Format

```
run_sandboxed_agent COMMAND -- [BWRAP_FLAGS...] -- [CMD_ARGS...]
```

- `COMMAND`: The program to run inside the sandbox
- `BWRAP_FLAGS`: Additional bubblewrap arguments (bind mounts, etc.)
- `CMD_ARGS`: Arguments passed to the command

## Agent-Specific Wrappers

Each agent has two files: an executable entry-point and an agent-specific lib.

### Shared Menu Library

**File**: `bin/ai_wrapper_data/ai_wrapper_lib.bash`

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

**Files**: `bin/executable_claude_wrapper.bash`, `bin/ai_wrapper_data/claude_wrapper_lib.bash`

```bash
# Binds:
# - ~/.claude (Claude's data directory)
# - Working directory (read-write)
# - ~/AGENTS.md, ~/CLAUDE.md (read-only)
```

### Codex Wrapper

**Files**: `bin/executable_codex_wrapper.bash`, `bin/ai_wrapper_data/codex_wrapper_lib.bash`

```bash
# Binds:
# - ~/.codex (Codex's data directory)
# - Working directory (read-write)
# - ~/AGENTS.md, ~/CLAUDE.md (read-only)
```

Note: `AI_SYSTEM_PROMPT_FLAG` is not yet set — orchestration starts a plain session
until the correct Codex CLI flag is confirmed.

### Cursor Wrapper

**Files**: `bin/executable_cursor_agent_wrapper.bash`, `bin/ai_wrapper_data/cursor_wrapper_lib.bash`

```bash
# Binds:
# - ~/.cursor (Cursor's data directory)
# - Working directory (read-write)
# - ~/AGENTS.md, ~/CLAUDE.md (read-only)
```

Note: `AI_SYSTEM_PROMPT_FLAG` is not yet set — orchestration starts a plain session
until the correct cursor-agent CLI flag is confirmed.

## Resource Limits

Resource limits are enforced via `prlimit`:

| Limit | Variable | Default | Purpose |
|-------|----------|---------|---------|
| Address Space | `RLIMIT_AS` | Unlimited | Max virtual memory |
| CPU Time | `RLIMIT_CPU` | Unlimited | Max CPU seconds |
| Open Files | `RLIMIT_NOFILE` | Unlimited | Max file descriptors |
| Processes | `RLIMIT_NPROC` | Unlimited | Max processes/threads |

**Note**: Current configuration sets all limits to unlimited for maximum flexibility while maintaining namespace isolation.

## Filesystem Access

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

AI agent rules are always mounted read-only:
- `~/AGENTS.md`
- `~/CLAUDE.md`

## Docker and Kubernetes

### Docker Access

The sandbox provides Docker access when available:

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

```bash
# kind configuration
~/.kind

# kubectl configuration (mounted from kind_dot_kube)
~/.kube (from ~/kind_dot_kube)
```

### First-Time kind Setup

If kind is not installed in the sandbox:

```bash
# Run inside sandbox
~/bin/setup_kind.bash

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

### Privilege Restriction

```bash
setpriv --no-new-privs --inh-caps=-all
```

- `--no-new-privs`: Prevents privilege escalation via setuid
- `--inh-caps=-all`: Drops all inheritable capabilities

### Path Validation

The wrapper validates all bind mount paths:

```bash
BWRAP_STRICT=1  # Fail on missing paths
BWRAP_STRICT=0  # Warn and skip missing paths (default)
```

### What Agents CAN Do

- Read/write files in the working directory
- Read/write their own data directory
- Access the network
- Run Docker containers
- Create Kubernetes clusters (via kind)
- Execute programs from /usr, /bin

### What Agents CANNOT Do

- Access files outside bind-mounted paths
- See or signal host processes
- Access host IPC resources
- Mount filesystems
- Change system configuration
- Escalate privileges

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

If the agent is killed (exit 137), check which limit was hit:
- Address space (RLIMIT_AS)
- CPU time (RLIMIT_CPU)
- Open files (RLIMIT_NOFILE)
- Processes (RLIMIT_NPROC)

Increase the limit in the agent-specific wrapper.

## Related Documentation

- [Repository Overview](repository-overview.md)
- [AGENTS.md](../AGENTS.md) - AI agent rules and guidelines
- [bubblewrap documentation](https://github.com/containers/bubblewrap)
