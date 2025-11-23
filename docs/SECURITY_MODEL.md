# AI Agent Sandbox Security Model

**Version**: 1.0
**Last Updated**: 2025-11-23
**Status**: Active - Mitigation in Progress

---

## Executive Summary

The AI agent sandbox (Claude, Codex, Cursor) uses **bubblewrap** for process isolation and grants full Docker access for development functionality. Security testing revealed a **critical vulnerability** where containers using `--pid=host` can view and interact with all host system processes.

**Current Risk Level**: **HIGH**
- ✅ Strong filesystem isolation via bubblewrap
- ✅ Process namespace isolation for sandbox
- ⚠️ Docker containers can break PID isolation with `--pid=host`
- ⚠️ Unlimited resource usage (CPU, memory)
- ⚠️ Full network access

**Mitigation Status**: Implementation in progress to block `--pid` flags system-wide.

---

## Architecture

### Isolation Layers

```
┌─────────────────────────────────────────────────────────┐
│                     Host System                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │           Bubblewrap Sandbox (Layer 1)            │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │         AI Agent Process                    │  │  │
│  │  │  - Claude / Codex / Cursor                  │  │  │
│  │  │  - Limited filesystem view                  │  │  │
│  │  │  - Own PID namespace                        │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  │                       │                            │  │
│  │                       ├──> Docker Socket (shared) │  │
│  │                       │                            │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │  Docker Containers (Layer 2)                │  │  │
│  │  │  - Created by AI agent                      │  │  │
│  │  │  - Share host Docker daemon                 │  │  │
│  │  │  - Can use --pid=host ⚠️ VULNERABILITY     │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Trust Boundaries

1. **Host ↔ Sandbox**: Strong isolation via bubblewrap
2. **Sandbox ↔ Containers**: Weak isolation (shared Docker daemon)
3. **Container ↔ Host**: **BROKEN** when using `--pid=host`

---

## Critical Security Finding: Docker --pid=host

### Issue Description

**Severity**: 🔴 **CRITICAL**
**Discovered**: 2025-11-23
**Status**: ⚠️ Mitigation in progress

Docker containers created by AI agents with the `--pid=host` flag can:
- ✅ View ALL host system processes (tested: 307 processes visible)
- ✅ Read process information (PIDs, commands, users, resource usage)
- ✅ Send signals to host processes (tested: can signal PID 1)
- ⚠️ Potentially terminate critical host processes

### Proof of Concept

**Test 1: View host processes**
```bash
docker run --rm --pid=host alpine ps aux
# Result: Shows all 307 host processes including systemd, Firefox, etc.
```

**Test 2: Detect Firefox processes**
```bash
docker run --rm --pid=host alpine ps aux | grep firefox
# Result: Found 12 Firefox processes with full command lines
```

**Test 3: Signal host processes**
```bash
docker run --rm --pid=host alpine kill -0 1
# Result: SUCCESS - Can send test signal to PID 1 (systemd)
```

### Attack Scenarios

#### Scenario 1: Process Enumeration
```bash
# AI agent reconnaissance
docker run --rm --pid=host alpine ps aux > /tmp/host_processes.txt
# Impact: Information disclosure, service discovery, user activity monitoring
```

#### Scenario 2: Denial of Service
```bash
# Terminate critical processes
docker run --rm --pid=host alpine kill -9 [PID]
# Impact: System instability, service disruption
```

#### Scenario 3: Privacy Violation
```bash
# Monitor user activity via Firefox processes
docker run --rm --pid=host alpine sh -c \
  'while true; do ps aux | grep firefox; sleep 1; done'
# Impact: Behavioral profiling, timing attacks
```

### Impact Assessment

| Category | Severity | Details |
|----------|----------|---------|
| Information Disclosure | **CRITICAL** | Full process list, commands, users visible |
| Process Control | **HIGH** | Can send signals, potential DOS |
| Privacy | **HIGH** | Can monitor user activity (Firefox tabs, etc.) |
| System Stability | **MEDIUM** | Can terminate processes, cause crashes |
| Privilege Escalation | **LOW** | Limited without additional exploits |

---

## Filesystem Isolation

### Bound Paths (Read-Only)

From `bin/ai_agent_universal_wrapper.bash`:

```bash
--ro-bind /usr /usr                    # System binaries
--ro-bind /lib /lib                    # System libraries
--ro-bind /lib64 /lib64                # 64-bit libraries
--ro-bind /bin /bin                    # Legacy binaries
--ro-bind /sbin /sbin                  # System binaries
--ro-bind /etc /etc                    # System configuration
--proc /proc                           # Process information
--dev /dev                             # Devices
--ro-bind /sys /sys                    # System information
```

### Bound Paths (Read-Write)

```bash
--bind $HOME $HOME                     # User home directory
--bind $WORKDIR $WORKDIR              # Current working directory
--tmpfs /tmp                           # Temporary files
--bind /run/docker.sock /run/docker.sock  # Docker socket
--bind /var/lib/docker /var/lib/docker    # Docker data
```

### Inaccessible Paths

- `/root` - Root user home
- Other users' home directories
- Unmounted filesystems
- Sensitive system paths not in bind list

### Test Results

✅ **PASSED**: Filesystem isolation working correctly
- Cannot access `/root` directory
- Cannot access other users' files
- Bind mounts correctly restrict access

---

## Process Isolation

### Bubblewrap Sandbox (Layer 1)

**Configuration**:
- New PID namespace: ✅ Yes
- New mount namespace: ✅ Yes
- New user namespace: ❌ No (runs as host user)
- New network namespace: ❌ No (uses host network)

**Test Results**:
- ✅ AI agent cannot see host processes from sandbox
- ✅ AI agent cannot kill host processes directly
- ✅ Process IDs are remapped within sandbox

### Docker Containers (Layer 2)

**Default behavior** (without --pid=host):
- ✅ Container has own PID namespace
- ✅ Cannot see host processes
- ✅ Strong isolation

**With --pid=host flag** ⚠️:
- ❌ Container shares host PID namespace
- ❌ Can see all 307 host processes
- ❌ Can send signals to host processes
- ❌ **BROKEN ISOLATION**

### Process Control Test Results

| Test | Result | Severity |
|------|--------|----------|
| Sandbox sees host processes | ❌ No (isolated) | ✅ PASS |
| Container (normal) sees host processes | ❌ No (isolated) | ✅ PASS |
| Container (--pid=host) sees host processes | ✅ **YES** (307 visible) | 🔴 **FAIL** |
| Container can signal host PID 1 | ✅ **YES** (tested) | 🔴 **FAIL** |

---

## Network Security

### Network Configuration

- **Sandbox**: Uses host network namespace
- **Containers**: Use Docker bridge network (default) or can use `--net=host`
- **Internet Access**: ✅ Full access (no filtering)

### Security Implications

⚠️ **No network isolation**:
- AI agents can make arbitrary network connections
- Can exfiltrate data over network
- Can download malicious payloads
- Can participate in DDoS attacks

**Design Decision**: Network access required for:
- API calls (OpenAI, Anthropic)
- Package downloads (pip, npm, cargo)
- Git operations
- Web browsing for research

**Mitigation**: None (by design)

---

## Docker Integration

### Docker Socket Sharing

**Configuration**:
```bash
--bind /run/docker.sock /run/docker.sock
--bind /var/lib/docker /var/lib/docker
```

**Security Implications**:
- ✅ AI agent has full Docker API access
- ✅ Can create/destroy containers
- ✅ Can pull images (visible to host)
- ⚠️ Can mount host paths (limited to sandbox binds)
- ⚠️ Can use `--pid=host` (VULNERABILITY)
- ⚠️ Can use `--privileged` flag
- ⚠️ No resource quotas on images

### Container Capabilities

**What containers CAN do**:
- Run with `--privileged` flag
- Use `--pid=host` to access host processes ⚠️
- Use `--net=host` to access host network
- Mount volumes from sandbox-accessible paths
- Pull unlimited images (no disk quota)

**What containers CANNOT do**:
- Access paths outside sandbox binds
- Escape bubblewrap filesystem restrictions
- Directly access host root filesystem

---

## Resource Limits

### Current Configuration

From wrapper scripts:
```bash
RLIMIT_AS=unlimited           # Address space (memory)
RLIMIT_CPU=unlimited          # CPU time
RLIMIT_NOFILE=4096           # Open file descriptors
RLIMIT_NPROC=4096            # Number of processes
```

### Security Analysis

| Resource | Limit | Risk | Mitigation |
|----------|-------|------|------------|
| Memory | Unlimited | **HIGH** - OOM possible | ⚠️ None |
| CPU | Unlimited | **HIGH** - 100% CPU usage | ⚠️ None |
| Processes | 4096 | **MEDIUM** - Fork bombs limited | ✅ Adequate |
| File descriptors | 4096 | **LOW** - Limited impact | ✅ Adequate |

### Resource Exhaustion Tests

✅ **Process limit**: Tested, fork bomb limited to 4096 processes
⚠️ **CPU exhaustion**: Possible, can consume 100% CPU
⚠️ **Memory exhaustion**: Possible, can trigger OOM killer
⚠️ **Disk exhaustion**: Possible via Docker images

---

## Threat Model

### In-Scope Threats (Protected Against)

| Threat | Protection | Status |
|--------|------------|--------|
| Direct filesystem escape | Bubblewrap bind mounts | ✅ Protected |
| Access to /root directory | Not bound in sandbox | ✅ Protected |
| Access other users' files | Not bound in sandbox | ✅ Protected |
| See host processes from sandbox | PID namespace isolation | ✅ Protected |
| Kill host processes directly | PID namespace isolation | ✅ Protected |

### Out-of-Scope Threats (NOT Protected)

| Threat | Severity | Status |
|--------|----------|--------|
| Docker --pid=host process visibility | **CRITICAL** | 🔴 **VULNERABLE** |
| Docker --pid=host signal injection | **HIGH** | 🔴 **VULNERABLE** |
| Network-based attacks | **MEDIUM** | ⚠️ By design |
| Resource exhaustion (CPU/memory) | **MEDIUM** | ⚠️ By design |
| Docker image disk usage | **LOW** | ⚠️ By design |
| Data exfiltration via network | **LOW** | ⚠️ By design |

---

## Mitigation Strategy: Block --pid Flag

### Solution Overview

**Goal**: Prevent Docker containers from using `--pid` or `--pid=host` flags system-wide

**Approach**: Intercept Docker commands in AI agent sandbox and reject `--pid` flags

**Implementation**: Wrapper script that validates Docker commands before execution

### Implementation Options

#### Option 1: Wrapper Script (Implemented ✅)

**Status**: Deployed in `bin/executable_docker_wrapper.bash`
- Blocks `--pid` at application level
- No root required
- Easy to disable
- Can be bypassed with `/usr/bin/docker`

#### Option 2: OPA Authorization Plugin (Automated Installer Available ✅)

**Status**: Automated installer ready in `installators/install_opa_docker.bash`
- Blocks `--pid` at Docker daemon level
- Cannot be bypassed
- System-wide enforcement
- Requires root access

**Quick Installation**:
```bash
# Run automated installer from chezmoi repo
sudo ~/.local/share/chezmoi/installators/install_opa_docker.bash
```

See `docs/INSTALL_OPA.md` for complete installation guide.

**Recommendation**: Install OPA for production-grade security. The installer is fully automated and takes ~5-10 minutes.

### Blocked Patterns

```bash
# These will be REJECTED:
docker run --pid=host ...
docker run --pid host ...
docker run --pid=container:name ...
docker create --pid=host ...

# These will be ALLOWED:
docker run alpine ps aux
docker run -v /data:/data alpine
docker run --privileged alpine  # (other flags allowed)
```

### User Communication

When `--pid` flag is blocked:
```
ERROR: Docker --pid flag is blocked for security reasons.
Reason: Containers with --pid=host can see and signal host processes.
Security Risk: Information disclosure, potential DOS attacks.
See: docs/SECURITY_MODEL.md for details.

If you need --pid access, run Docker outside the AI agent sandbox.
```

---

## Security Recommendations

### Immediate Actions (In Progress)

1. ✅ **Document Docker --pid=host vulnerability**
   - Completed: `docs/security_test_results_docker_pid_host.md`
   - Completed: This document (SECURITY_MODEL.md)
   - Completed: TODO.md updated with findings

2. 🔧 **Implement --pid flag blocking** (In Progress)
   - Create Docker wrapper script
   - Integrate into AI agent wrappers
   - Test blocking mechanism

3. ⏳ **Update documentation** (Pending)
   - Add warnings to AGENTS.md
   - Update CLAUDE.md with security notes
   - Document blocking behavior

### Future Improvements

4. **Add Resource Limits** (Recommended)
   - Set RLIMIT_AS to prevent OOM (e.g., 16GB)
   - Set RLIMIT_CPU to prevent CPU exhaustion (e.g., 600s)
   - Implement disk quotas for Docker images

5. **Separate Docker Daemon** (Optional)
   - Use dedicated Docker daemon for AI agents
   - Isolate from host system
   - Implement AppArmor/SELinux policies

6. **Network Namespace Isolation** (Optional)
   - Move sandbox to separate network namespace
   - Implement network filtering/proxy
   - Reduce attack surface

7. **Monitoring and Logging** (Recommended)
   - Log all Docker commands executed by AI agents
   - Alert on suspicious patterns
   - Implement audit trail

---

## Risk Assessment

### Overall Security Posture

**Before Mitigation**: **HIGH RISK**
- 🔴 Critical vulnerability (Docker --pid=host)
- ⚠️ Unlimited resources (CPU, memory)
- ⚠️ Full network access

**After Mitigation**: **MEDIUM RISK** (expected)
- ✅ Docker --pid=host blocked
- ⚠️ Unlimited resources (accepted trade-off)
- ⚠️ Full network access (required for functionality)

### Acceptable Use Cases

✅ **Appropriate for**:
- Personal development environments
- Trusted AI agents (official Claude, Codex, Cursor)
- Learning and experimentation
- Development workstations

❌ **NOT appropriate for**:
- Production deployments
- Multi-tenant environments
- Untrusted code execution
- Public-facing services
- Security-critical systems

---

## Testing Results Summary

| Test Category | Status | Details |
|---------------|--------|---------|
| Filesystem isolation | ✅ PASS | Cannot access outside binds |
| Process isolation (sandbox) | ✅ PASS | Cannot see host processes |
| Process isolation (Docker normal) | ✅ PASS | Containers isolated |
| Process isolation (Docker --pid=host) | 🔴 **FAIL** | Can see 307 host processes |
| Signal capability (--pid=host) | 🔴 **FAIL** | Can signal host PID 1 |
| Network isolation | ⚠️ N/A | No isolation by design |
| Resource limits (NPROC) | ✅ PASS | Fork bombs limited |
| Resource limits (CPU/memory) | ⚠️ N/A | Unlimited by design |
| Docker image quotas | ⚠️ N/A | No quotas by design |

**Critical Issues Found**: 1 (Docker --pid=host)
**Mitigation Status**: Implementation in progress

---

## Conclusion

The AI agent sandbox provides **strong filesystem and process isolation** through bubblewrap, but grants extensive Docker privileges for development functionality. Security testing revealed a **critical vulnerability** where Docker containers using `--pid=host` can break process isolation and access host system processes.

**Current Risk Level**: **HIGH** (before mitigation)
**Target Risk Level**: **MEDIUM** (after blocking --pid)

**Mitigation in Progress**:
- Implementing Docker command wrapper to block `--pid` flags
- Documentation completed
- Testing pending

**Intended Use**:
- ✅ Personal development with trusted AI agents
- ✅ Experimentation and learning
- ❌ Production environments
- ❌ Untrusted code execution

---

**Document Status**: ✅ Complete
**Next Steps**:
1. Implement Docker wrapper to block --pid flags
2. Test blocking mechanism
3. Update AGENTS.md and CLAUDE.md
4. Mark TODO.md security task as complete

**Review Schedule**: After each significant change to sandbox configuration

---

**Last Updated**: 2025-11-23
**Author**: Claude (AI Agent) + User Review
**Version**: 1.0
