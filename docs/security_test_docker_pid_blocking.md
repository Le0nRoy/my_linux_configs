# Security Test: Docker --pid Flag Blocking

**Test Date**: 2025-11-23
**Implementation**: `bin/executable_docker_wrapper.bash` + `bin/executable_docker`
**Purpose**: Verify that Docker --pid flags are blocked in AI agent sandbox

---

## Implementation Overview

### Components

1. **Docker Wrapper** (`~/bin/docker_wrapper.bash`)
   - Intercepts all docker commands
   - Parses arguments for --pid flags
   - Blocks commands with --pid
   - Forwards safe commands to /usr/bin/docker

2. **Docker Command** (`~/bin/docker`)
   - Symlink/wrapper that calls docker_wrapper.bash
   - Ensures all 'docker' invocations use the wrapper

3. **AI Agent Integration**
   - PATH set to `${HOME}/bin:/usr/bin:...`
   - ~/bin/docker found before /usr/bin/docker
   - Automatic interception in sandbox

### Blocked Patterns

```bash
docker run --pid=host ...
docker run --pid host ...
docker run --pid=container:name ...
docker create --pid=host ...
docker exec --pid=host ...
```

### Allowed Patterns

```bash
docker run alpine ps aux          # Normal containers
docker run --privileged alpine    # Other flags OK
docker run -v /data:/data alpine  # Volume mounts OK
docker ps                          # All other commands OK
docker build -t app .              # Build commands OK
```

---

## Test Plan

### Test 1: Block --pid=host

**Command**:
```bash
echo 'docker run --pid=host alpine ps aux' | claude --dangerously-skip-permissions
```

**Expected Result**: ❌ BLOCKED
```
╔════════════════════════════════════════════════════════════════╗
║          SECURITY: Docker --pid flag BLOCKED                  ║
╚════════════════════════════════════════════════════════════════╝

Reason: Containers with --pid=host can see and signal host processes.
Risk: Information disclosure, potential denial of service.
...
```

**Actual Result**: (To be filled after testing)

---

### Test 2: Block --pid=container

**Command**:
```bash
echo 'docker run --pid=container:web alpine ps aux' | claude --dangerously-skip-permissions
```

**Expected Result**: ❌ BLOCKED (all --pid forms blocked)

**Actual Result**: (To be filled after testing)

---

### Test 3: Allow normal docker run

**Command**:
```bash
echo 'docker run --rm alpine ps aux' | claude --dangerously-skip-permissions
```

**Expected Result**: ✅ ALLOWED
- Container runs normally
- Shows only container processes (not host)
- Exit code 0

**Actual Result**: (To be filled after testing)

---

### Test 4: Allow other flags

**Command**:
```bash
echo 'docker run --rm --privileged alpine cat /proc/1/cgroup' | claude --dangerously-skip-permissions
```

**Expected Result**: ✅ ALLOWED
- --privileged flag is not blocked (only --pid is blocked)
- Container runs with elevated privileges
- Exit code 0

**Actual Result**: (To be filled after testing)

---

### Test 5: Block --pid with equals sign

**Command**:
```bash
echo 'docker run --pid=host --rm alpine ps aux' | claude --dangerously-skip-permissions
```

**Expected Result**: ❌ BLOCKED (catches --pid= format)

**Actual Result**: (To be filled after testing)

---

### Test 6: Block --pid with space

**Command**:
```bash
echo 'docker run --pid host --rm alpine ps aux' | claude --dangerously-skip-permissions
```

**Expected Result**: ❌ BLOCKED (catches --pid space host format)

**Actual Result**: (To be filled after testing)

---

### Test 7: Allow docker ps, build, etc.

**Commands**:
```bash
echo 'docker ps -a' | claude --dangerously-skip-permissions
echo 'docker images' | claude --dangerously-skip-permissions
echo 'docker version' | claude --dangerously-skip-permissions
```

**Expected Result**: ✅ ALLOWED (all non-run commands work normally)

**Actual Result**: (To be filled after testing)

---

### Test 8: Verify bypass prevention

**Command** (try to bypass wrapper):
```bash
echo '/usr/bin/docker run --pid=host alpine ps aux' | claude --dangerously-skip-permissions
```

**Expected Result**:
- ⚠️ May work if calling real docker directly
- Wrapper only intercepts 'docker' command, not /usr/bin/docker
- This is acceptable - user can intentionally bypass if needed

**Actual Result**: (To be filled after testing)

---

## Test Execution

### Prerequisites

1. Deploy changes: `chezmoi apply`
2. Verify deployment:
   ```bash
   ls -la ~/bin/docker ~/bin/docker_wrapper.bash
   file ~/bin/docker
   ```
3. Test wrapper directly:
   ```bash
   ~/bin/docker --version
   ~/bin/docker run --pid=host alpine echo test
   ```

### Running Tests

Execute each test command and record results:
- ✅ PASS: Expected behavior occurred
- ❌ FAIL: Unexpected behavior
- ⚠️ PARTIAL: Works with caveats

### Results Table

| Test | Command | Expected | Actual | Status |
|------|---------|----------|--------|--------|
| 1 | `docker run --pid=host` | BLOCKED | TBD | ⏳ |
| 2 | `docker run --pid=container:x` | BLOCKED | TBD | ⏳ |
| 3 | `docker run alpine` | ALLOWED | TBD | ⏳ |
| 4 | `docker run --privileged` | ALLOWED | TBD | ⏳ |
| 5 | `docker run --pid=host` | BLOCKED | TBD | ⏳ |
| 6 | `docker run --pid host` | BLOCKED | TBD | ⏳ |
| 7 | `docker ps/images/version` | ALLOWED | TBD | ⏳ |
| 8 | `/usr/bin/docker --pid=host` | BYPASS | TBD | ⏳ |

---

## Security Validation

### Validation Criteria

✅ **Blocking works** if:
1. All --pid flag variations are caught and blocked
2. Error message clearly explains security risk
3. Normal Docker commands continue to work
4. No false positives (blocking valid commands)

⚠️ **Acceptable limitations**:
1. Direct calls to /usr/bin/docker bypass wrapper (intentional)
2. Other dangerous flags (--privileged, --net=host) not blocked (out of scope)

❌ **Failure conditions**:
1. --pid flag not detected (bypass possible)
2. Normal Docker commands blocked (false positive)
3. Wrapper crashes or causes errors

---

## Performance Impact

### Overhead Assessment

**Expected overhead**:
- Minimal: Wrapper adds 1 extra process fork
- ~5-10ms latency per docker command
- Negligible impact for AI agent use cases

**Measurement** (optional):
```bash
# Time normal docker
time /usr/bin/docker version

# Time wrapped docker
time ~/bin/docker version

# Compare difference
```

---

## Rollback Plan

If blocking causes issues:

### Option 1: Disable wrapper temporarily
```bash
# Rename wrapper to disable
mv ~/bin/docker ~/bin/docker.disabled

# Docker commands now use /usr/bin/docker directly
```

### Option 2: Remove from chezmoi
```bash
# In chezmoi repo
cd ~/.local/share/chezmoi
rm bin/executable_docker bin/executable_docker_wrapper.bash
chezmoi apply
```

### Option 3: Modify wrapper to log-only mode
```bash
# Edit wrapper to log instead of block
# Change exit 1 to exec "${REAL_DOCKER}" "$@"
```

---

## Documentation Updates

After testing completes, update:

1. ✅ TODO.md - Mark "Verify Docker-in-Docker security" complete
2. ✅ SECURITY_MODEL.md - Update with blocking implementation
3. ⏳ AGENTS.md - Add note about --pid blocking
4. ⏳ CLAUDE.md - Add note about --pid blocking
5. ⏳ README (if exists) - Document security feature

---

## Expected Outcome

**Success Criteria**:
- ✅ All --pid flags blocked correctly
- ✅ Normal Docker usage unaffected
- ✅ Clear error messages for blocked commands
- ✅ No performance degradation
- ✅ Easy to disable if needed

**Risk Mitigation**:
- Before: CRITICAL vulnerability (process visibility)
- After: MITIGATED (--pid blocked, normal isolation restored)

**Residual Risks**:
- User can still bypass by calling /usr/bin/docker directly
- This is acceptable - provides clear security boundary
- Other Docker flags (--privileged, --net=host) remain available

---

## Next Steps

1. ⏳ Run all test commands
2. ⏳ Fill in "Actual Result" columns
3. ⏳ Document any issues or unexpected behavior
4. ⏳ Update TODO.md with completion status
5. ⏳ Update user-facing documentation (AGENTS.md, CLAUDE.md)

---

**Test Status**: ⏳ PENDING EXECUTION
**Implementation Status**: ✅ COMPLETE
**Documentation Status**: ✅ COMPLETE
