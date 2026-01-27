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
│    (claude_wrapper.bash, codex_wrapper.bash, etc.)          │
│                                                             │
│    Sets: RLIMIT_*, agent-specific bind mounts               │
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

### Claude Wrapper

**File**: `bin/executable_claude_wrapper.bash`

```bash
# Binds:
# - ~/.claude (Claude's data directory)
# - Working directory (read-write)
# - ~/AGENTS.md, ~/CLAUDE.md (read-only)
```

### Codex Wrapper

**File**: `bin/executable_codex_wrapper.bash`

```bash
# Binds:
# - ~/.codex (Codex's data directory)
# - Working directory (read-write)
# - ~/AGENTS.md, ~/CLAUDE.md (read-only)
```

### Cursor Wrapper

**File**: `bin/executable_cursor_agent_wrapper.bash`

```bash
# Binds:
# - ~/.cursor (Cursor's data directory)
# - Working directory (read-write)
# - ~/AGENTS.md, ~/CLAUDE.md (read-only)
```

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
