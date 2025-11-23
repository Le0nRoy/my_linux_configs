# Docker Daemon Hardening Guide

**Purpose**: Prevent `--pid=host` and other dangerous flags at the Docker daemon level
**Scope**: System-wide hardening (affects all Docker users)
**Date**: 2025-11-23

---

## Overview

Instead of blocking `--pid=host` at the wrapper level, we can enforce restrictions at the Docker daemon level. This provides deeper security and cannot be bypassed by calling `/usr/bin/docker` directly.

**Benefits**:
- ✅ Cannot be bypassed by wrapper avoidance
- ✅ Applies to all Docker users system-wide
- ✅ Enforced by Docker daemon itself
- ✅ More robust than application-level filtering

**Trade-offs**:
- ⚠️ Affects all users (not just AI agents)
- ⚠️ Requires root/sudo to configure
- ⚠️ May break existing workflows
- ⚠️ More complex to configure

---

## Option 1: Docker Authorization Plugin (Recommended)

### Overview

Docker supports authorization plugins that intercept API calls and enforce policies before executing commands.

### Popular Plugins

#### A. Authz Plugin (Simple, Built-in)

**Installation**:
```bash
# Install authz plugin (if not included in Docker)
sudo apt-get install docker-authz-plugin

# Or for Arch Linux
yay -S docker-authz-plugin
```

**Configuration** (`/etc/docker/daemon.json`):
```json
{
  "authorization-plugins": ["authz-broker"],
  "authz-broker-config": {
    "rules": [
      {
        "action": "deny",
        "matcher": ".*--pid.*",
        "reason": "PID namespace sharing blocked for security"
      }
    ]
  }
}
```

**Restart Docker**:
```bash
sudo systemctl restart docker
```

#### B. OPA (Open Policy Agent) - Most Flexible

**Installation**:
```bash
# Install OPA
sudo curl -L -o /usr/local/bin/opa https://openpolicyagent.org/downloads/latest/opa_linux_amd64
sudo chmod +x /usr/local/bin/opa

# Install Docker OPA plugin
sudo docker plugin install openpolicyagent/opa-docker-authz-v2:0.8 \
  opa-args="-policy-file /etc/docker/policies/authz.rego"
```

**Create Policy** (`/etc/docker/policies/authz.rego`):
```rego
package docker.authz

import data.docker

# Default deny all
default allow = false

# Allow all requests except those with --pid flag
allow {
    not contains_pid_flag
}

# Check if request contains --pid flag
contains_pid_flag {
    # Check in HostConfig for pid mode
    input.Body.HostConfig.PidMode != ""
}

contains_pid_flag {
    # Check in command arguments
    arg := input.Body.Cmd[_]
    contains(arg, "--pid")
}

# Helper function
contains(str, substr) {
    indexof(str, substr) != -1
}
```

**Enable Plugin** (`/etc/docker/daemon.json`):
```json
{
  "authorization-plugins": ["openpolicyagent/opa-docker-authz-v2:0.8"]
}
```

**Restart Docker**:
```bash
sudo systemctl restart docker
```

**Test**:
```bash
# Should be blocked
docker run --pid=host alpine ps aux
# Error: authorization denied by plugin openpolicyagent/opa-docker-authz-v2:0.8

# Should work
docker run alpine ps aux
```

---

## Option 2: AppArmor Profile (Linux Security Module)

### Overview

AppArmor can restrict what containers can do at the kernel level. Arch Linux uses AppArmor (not SELinux by default).

### Check AppArmor Status

```bash
# Check if AppArmor is enabled
sudo aa-status

# Check Docker's AppArmor profile
sudo aa-status | grep docker
```

### Create Custom AppArmor Profile

**Create profile** (`/etc/apparmor.d/docker-no-pid-host`):
```apparmor
#include <tunables/global>

profile docker-no-pid-host flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Allow most Docker operations
  #include <abstractions/docker>

  # Deny PID namespace sharing
  deny /proc/*/ns/pid r,
  deny /proc/*/ns/pid w,

  # Deny access to host PID namespace
  deny capability sys_ptrace,
  deny capability sys_admin,

  # Allow container-specific PID namespace
  /proc/*/ns/pid r,
  owner /proc/*/ns/pid rw,
}
```

**Load profile**:
```bash
sudo apparmor_parser -r /etc/apparmor.d/docker-no-pid-host
```

**Configure Docker to use profile** (`/etc/docker/daemon.json`):
```json
{
  "security-opt": ["apparmor=docker-no-pid-host"]
}
```

**Restart Docker**:
```bash
sudo systemctl restart docker
```

### Limitations

- AppArmor profiles are complex to write correctly
- May have unintended side effects
- Requires deep understanding of Linux security modules
- Not as precise as authorization plugins for Docker-specific restrictions

---

## Option 3: Docker Daemon Configuration

### User Namespaces (Partial Solution)

Enabling user namespaces provides isolation but doesn't directly block `--pid=host`.

**Enable user namespaces** (`/etc/docker/daemon.json`):
```json
{
  "userns-remap": "default"
}
```

**Restart Docker**:
```bash
sudo systemctl restart docker
```

**Effect**:
- Containers run as unprivileged users
- Reduces damage from container escape
- Does NOT block `--pid=host` but limits its impact

### No Default Capabilities (Aggressive)

Remove dangerous capabilities by default:

**Configuration** (`/etc/docker/daemon.json`):
```json
{
  "default-capabilities": [
    "CHOWN",
    "DAC_OVERRIDE",
    "FSETID",
    "FOWNER",
    "MKNOD",
    "NET_RAW",
    "SETGID",
    "SETUID",
    "SETFCAP",
    "SETPCAP",
    "NET_BIND_SERVICE",
    "KILL",
    "AUDIT_WRITE"
  ]
}
```

**Removed (compared to default)**:
- `SYS_ADMIN` - Prevents privileged operations
- `SYS_PTRACE` - Prevents process tracing
- Others that enable dangerous operations

**Restart Docker**:
```bash
sudo systemctl restart docker
```

**Effect**:
- Reduces container privileges
- May break some legitimate use cases
- Does NOT directly block `--pid=host`

---

## Option 4: Seccomp Profile

### Overview

Seccomp (Secure Computing Mode) filters system calls that containers can make.

### Default Seccomp Profile

Docker has a default seccomp profile: `/usr/share/docker/seccomp.json`

### Custom Seccomp Profile

**Create profile** (`/etc/docker/seccomp-no-pid.json`):
```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_AARCH64",
    "SCMP_ARCH_ARM"
  ],
  "syscalls": [
    {
      "names": [
        "accept",
        "accept4",
        "access",
        "bind",
        "clone",
        "close",
        "connect",
        "dup",
        "dup2",
        "dup3",
        "execve",
        "exit",
        "exit_group",
        "fork",
        "futex",
        "getcwd",
        "getpid",
        "read",
        "write"
      ],
      "action": "SCMP_ACT_ALLOW"
    },
    {
      "names": [
        "setns",
        "unshare"
      ],
      "action": "SCMP_ACT_ERRNO",
      "comment": "Block namespace manipulation (including PID)"
    }
  ]
}
```

**Use profile**:
```bash
docker run --security-opt seccomp=/etc/docker/seccomp-no-pid.json alpine ps aux
```

**Set as default** (`/etc/docker/daemon.json`):
```json
{
  "seccomp-profile": "/etc/docker/seccomp-no-pid.json"
}
```

### Limitations

- Seccomp blocks syscalls, not Docker flags
- Blocking `setns` prevents many legitimate operations
- Very low-level, easy to break things
- Doesn't directly prevent `--pid=host` flag parsing

---

## Recommended Approach: OPA Authorization Plugin

### Why OPA is Best

1. **Precise**: Can block exactly `--pid` flag, nothing more
2. **Flexible**: Policy written in Rego language (easy to modify)
3. **Comprehensive**: Can enforce many policies beyond just `--pid`
4. **Auditable**: Logs policy violations
5. **Industry standard**: Used by Kubernetes and other systems

## ⚡ Quick Start: Automated Installer

**We provide an automated installation script that handles everything for you!**

```bash
# Run automated installer from chezmoi repo
sudo ~/.local/share/chezmoi/installators/install_opa_docker.bash

# That's it! OPA is installed, configured, and tested.
```

**Features**:
- ✅ Automated installation (~5-10 minutes)
- ✅ Automatic backups
- ✅ Syntax validation
- ✅ Built-in testing
- ✅ Easy uninstall

See `docs/INSTALL_OPA.md` for detailed guide.

---

## Manual Installation (Advanced)

If you prefer manual installation, follow these steps:

### Complete OPA Setup

#### Step 1: Install OPA

```bash
# Download OPA binary
sudo curl -L -o /usr/local/bin/opa \
  https://openpolicyagent.org/downloads/latest/opa_linux_amd64

sudo chmod +x /usr/local/bin/opa

# Verify installation
opa version
```

#### Step 2: Install Docker OPA Plugin

```bash
# Install plugin
sudo docker plugin install openpolicyagent/opa-docker-authz-v2:0.8 \
  opa-args="-policy-file /etc/docker/policies/authz.rego -log-level=debug"

# Verify plugin
docker plugin ls
```

#### Step 3: Create Policy Directory

```bash
sudo mkdir -p /etc/docker/policies
```

#### Step 4: Create Comprehensive Policy

**File**: `/etc/docker/policies/authz.rego`

```rego
package docker.authz

import future.keywords.if
import future.keywords.in

# Default policy: deny unknown actions
default allow := false

# Allow Docker API calls by default
allow if {
    not blocked_action
}

# Block containers with PID namespace sharing
blocked_action if {
    # Check if request is creating/running a container
    input.Method == "POST"
    contains(input.Path, "/containers/create") or contains(input.Path, "/containers/run")

    # Check if --pid flag is present in HostConfig
    input.Body.HostConfig.PidMode != ""
    input.Body.HostConfig.PidMode != "private"
}

# Block containers with host network (optional - can enable separately)
# blocked_action if {
#     input.Method == "POST"
#     contains(input.Path, "/containers/create")
#     input.Body.HostConfig.NetworkMode == "host"
# }

# Block privileged containers (optional - can enable separately)
# blocked_action if {
#     input.Method == "POST"
#     contains(input.Path, "/containers/create")
#     input.Body.HostConfig.Privileged == true
# }

# Provide detailed error message
deny_reason := "PID namespace sharing (--pid) is blocked for security. See /docs/SECURITY_MODEL.md" if {
    blocked_action
}

# Allow read-only operations (ps, images, inspect, etc.)
allow if {
    input.Method == "GET"
}

# Allow version check
allow if {
    input.Path == "/version"
}

# Helper functions
contains(str, substr) if {
    indexof(str, substr) != -1
}
```

#### Step 5: Enable Plugin in Docker Daemon

**Edit** `/etc/docker/daemon.json`:
```json
{
  "authorization-plugins": ["openpolicyagent/opa-docker-authz-v2:0.8"],
  "log-level": "info"
}
```

#### Step 6: Restart Docker

```bash
sudo systemctl restart docker

# Check status
sudo systemctl status docker

# Check plugin
docker plugin ls
```

#### Step 7: Test Policy

```bash
# Should be BLOCKED
docker run --pid=host alpine ps aux
# Expected error: authorization denied by plugin

# Should work
docker run alpine ps aux
docker run --rm alpine echo "Hello"
docker ps
docker images
```

---

## Testing the Hardening

### Test Suite

```bash
#!/bin/bash
# Test Docker daemon hardening

echo "=== Docker Daemon Security Tests ==="

echo ""
echo "TEST 1: Normal container (should work)"
docker run --rm alpine echo "Success" && echo "✓ PASS" || echo "✗ FAIL"

echo ""
echo "TEST 2: Container with --pid=host (should FAIL)"
docker run --rm --pid=host alpine ps aux 2>&1 | grep -q "denied" && echo "✓ PASS - Blocked" || echo "✗ FAIL - Not blocked"

echo ""
echo "TEST 3: Container with --pid=container:name (should FAIL)"
docker run --rm --pid=container:test alpine ps aux 2>&1 | grep -q "denied" && echo "✓ PASS - Blocked" || echo "✗ FAIL - Not blocked"

echo ""
echo "TEST 4: Docker ps (should work)"
docker ps > /dev/null && echo "✓ PASS" || echo "✗ FAIL"

echo ""
echo "TEST 5: Docker images (should work)"
docker images > /dev/null && echo "✓ PASS" || echo "✗ FAIL"

echo ""
echo "TEST 6: Privileged container (should work unless blocked)"
docker run --rm --privileged alpine cat /proc/1/cgroup > /dev/null 2>&1 && echo "✓ PASS - Allowed" || echo "⚠ Blocked (if policy enables)"

echo ""
echo "=== Test Complete ==="
```

---

## Comparison: Wrapper vs Daemon Hardening

| Feature | Wrapper Script | OPA Plugin | AppArmor | Seccomp |
|---------|----------------|------------|----------|---------|
| Blocks --pid=host | ✅ Yes | ✅ Yes | ⚠️ Partial | ⚠️ Indirect |
| Can be bypassed | ⚠️ Yes (/usr/bin/docker) | ✅ No | ✅ No | ✅ No |
| System-wide | ❌ Sandbox only | ✅ All users | ✅ All users | ✅ All users |
| Requires root | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |
| Granular control | ✅ Yes | ✅ Yes | ⚠️ Moderate | ❌ Low-level |
| Easy to configure | ✅ Very easy | ⚠️ Moderate | ❌ Complex | ❌ Complex |
| Maintenance | ✅ Easy | ✅ Easy | ❌ Hard | ❌ Hard |
| Impact on system | ✅ Minimal | ⚠️ Moderate | ⚠️ Moderate | ⚠️ High |
| Flexibility | ✅ High | ✅ Very high | ⚠️ Moderate | ❌ Low |

---

## Recommended Strategy

### For Your Use Case (Personal Development)

**Two-Layer Security** (Defense in Depth):

1. **Layer 1: Wrapper Script** (Current)
   - Quick to implement ✅
   - No root required ✅
   - Affects only AI agents ✅
   - Easy to disable if needed ✅

2. **Layer 2: OPA Plugin** (Optional Enhancement)
   - System-wide protection ✅
   - Cannot be bypassed ✅
   - Professional solution ✅
   - Requires root access ⚠️

**Deployment Priority**:
- ✅ **NOW**: Deploy wrapper script (already implemented)
- ⏳ **LATER**: Consider OPA if you want system-wide hardening

### For Production Environments

**Must have**: OPA Authorization Plugin or equivalent
- System-wide enforcement
- Cannot be bypassed
- Auditable and compliant
- Industry best practice

---

## Rollback / Disable Hardening

### Disable OPA Plugin

```bash
# Disable plugin
sudo docker plugin disable openpolicyagent/opa-docker-authz-v2:0.8

# Remove from daemon.json
sudo vim /etc/docker/daemon.json
# Remove "authorization-plugins" line

# Restart Docker
sudo systemctl restart docker
```

### Disable AppArmor Profile

```bash
# Unload profile
sudo aa-disable /etc/apparmor.d/docker-no-pid-host

# Remove from daemon.json
sudo vim /etc/docker/daemon.json
# Remove "security-opt" line

# Restart Docker
sudo systemctl restart docker
```

---

## Documentation References

- **OPA Docker Authorization**: https://www.openpolicyagent.org/docs/latest/docker-authorization/
- **Docker Security**: https://docs.docker.com/engine/security/
- **AppArmor**: https://wiki.archlinux.org/title/AppArmor
- **Seccomp**: https://docs.docker.com/engine/security/seccomp/

---

## Summary

**Yes, daemon-level hardening is possible and recommended for production.**

**Quick Answer**:
- ✅ **Best solution**: OPA Authorization Plugin
- ✅ **Blocks**: `--pid=host` at Docker API level
- ✅ **Cannot be bypassed**: Enforced by daemon
- ⚠️ **Requires**: Root access, plugin installation

**For your setup**:
- Keep wrapper script (already done) ✓
- Optionally add OPA for system-wide hardening
- Test thoroughly before deploying

**Implementation time**:
- OPA: ~30-60 minutes setup
- Testing: ~15 minutes
- Documentation: Included above

Would you like me to help you set up OPA, or are you satisfied with the wrapper-based approach?
