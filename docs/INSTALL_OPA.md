# OPA Installation Guide

**Script**: `installators/install_opa_docker.bash`
**Purpose**: Automated installation and configuration of OPA for Docker authorization
**Time**: ~5-10 minutes (mostly downloads and restarts)

---

## Quick Start

### Installation (One Command)

```bash
# The installer is in the chezmoi repo at:
# ~/.local/share/chezmoi/installators/install_opa_docker.bash

# Run installer with sudo
sudo ~/.local/share/chezmoi/installators/install_opa_docker.bash
```

That's it! The script will:
1. ✅ Check prerequisites
2. ✅ Install OPA binary
3. ✅ Create security policy
4. ✅ Install Docker plugin
5. ✅ Configure Docker daemon
6. ✅ Restart Docker
7. ✅ Run tests

---

## What Gets Installed

### 1. OPA Binary
- **Location**: `/usr/local/bin/opa`
- **Size**: ~50MB
- **Purpose**: Policy engine for authorization decisions

### 2. OPA Policy
- **Location**: `/etc/docker/policies/authz.rego`
- **Purpose**: Defines what Docker operations are blocked
- **Default**: Blocks `--pid=host` and `--pid=container:*`

### 3. Docker Plugin
- **Name**: `openpolicyagent/opa-docker-authz-v2:0.8`
- **Purpose**: Connects Docker daemon to OPA for authorization

### 4. Docker Configuration
- **Location**: `/etc/docker/daemon.json`
- **Backup**: Automatic backup with timestamp
- **Changes**: Adds authorization plugin

---

## Usage

### Install OPA
```bash
sudo ~/.local/share/chezmoi/installators/install_opa_docker.bash
```

### Check Status
```bash
sudo ~/.local/share/chezmoi/installators/install_opa_docker.bash --status
```

### Uninstall OPA
```bash
sudo ~/.local/share/chezmoi/installators/install_opa_docker.bash --uninstall
```

### Show Help
```bash
~/.local/share/chezmoi/installators/install_opa_docker.bash --help
```

---

## What Gets Blocked

After installation, these commands will **fail**:

```bash
# Blocked: PID namespace sharing
docker run --pid=host alpine ps aux
# Error: SECURITY: --pid flag is blocked...

docker run --pid=container:web alpine ps aux
# Error: SECURITY: --pid flag is blocked...
```

## What Still Works

All normal Docker operations continue to work:

```bash
# Allowed: Normal containers
docker run --rm alpine echo "Hello"
docker run -d nginx

# Allowed: Volume mounts
docker run -v /data:/data alpine ls /data

# Allowed: Privileged containers (if needed)
docker run --privileged alpine cat /proc/1/cgroup

# Allowed: All read operations
docker ps
docker images
docker inspect
docker logs
```

---

## Customizing the Policy

### Edit Policy File

```bash
sudo vim /etc/docker/policies/authz.rego
```

### Example: Also Block Privileged Containers

Uncomment these lines in the policy:
```rego
# Uncomment to block privileged containers
allow := false if {
    is_container_create_or_run
    input.Body.HostConfig.Privileged == true
}
```

### Example: Also Block Host Network Mode

Uncomment these lines:
```rego
# Uncomment to block host network mode
allow := false if {
    is_container_create_or_run
    input.Body.HostConfig.NetworkMode == "host"
}
```

### Apply Changes

```bash
# Restart Docker to reload policy
sudo systemctl restart docker

# Test new policy
docker run --privileged alpine echo test
# Should be blocked if you enabled that rule
```

---

## Verification Tests

### Run Automated Tests

The installer runs these tests automatically, but you can repeat them:

```bash
# Test 1: Normal container (should work)
docker run --rm alpine echo "Success"

# Test 2: --pid=host (should be blocked)
docker run --rm --pid=host alpine ps aux
# Expected: Error about authorization denied

# Test 3: Docker ps (should work)
docker ps
```

### Manual Verification

```bash
# Check OPA is installed
opa version

# Check plugin is enabled
docker plugin ls | grep opa

# Check daemon configuration
sudo cat /etc/docker/daemon.json

# Check policy exists
sudo cat /etc/docker/policies/authz.rego

# View Docker logs for OPA decisions
sudo journalctl -u docker -f
# Then run: docker run --pid=host alpine ps aux
# You should see OPA denying the request
```

---

## Troubleshooting

### Issue: Installation fails at plugin installation

**Symptom**: Error during `docker plugin install`

**Solution**:
```bash
# Remove partial installation
docker plugin disable openpolicyagent/opa-docker-authz-v2:0.8 || true
docker plugin rm openpolicyagent/opa-docker-authz-v2:0.8 || true

# Try again
sudo ~/bin/install_opa_docker.bash
```

### Issue: Docker fails to start after installation

**Symptom**: Docker daemon won't start after restart

**Solution**:
```bash
# Check Docker logs
sudo journalctl -xeu docker

# Restore backup configuration
sudo cp /etc/docker/daemon.json.backup-* /etc/docker/daemon.json

# Restart Docker
sudo systemctl restart docker

# Check if Docker starts
docker ps
```

### Issue: Normal containers are blocked

**Symptom**: Even simple `docker run` commands fail

**Solution**:
```bash
# Check OPA policy syntax
sudo opa check /etc/docker/policies/authz.rego

# View policy for errors
sudo cat /etc/docker/policies/authz.rego

# Temporarily disable OPA
sudo ~/bin/install_opa_docker.bash --uninstall

# Then investigate and reinstall with corrected policy
```

### Issue: --pid=host is NOT blocked

**Symptom**: Containers with `--pid=host` still work

**Solution**:
```bash
# Check plugin status
docker plugin ls | grep opa
# Should show "enabled: true"

# Check daemon config
sudo cat /etc/docker/daemon.json
# Should have "authorization-plugins"

# Check OPA policy
sudo cat /etc/docker/policies/authz.rego
# Verify has_pid_namespace_sharing rule exists

# Restart Docker
sudo systemctl restart docker

# Test again
docker run --pid=host alpine ps aux
```

---

## Rollback / Uninstall

### Quick Uninstall

```bash
sudo ~/bin/install_opa_docker.bash --uninstall
```

This will:
1. Disable and remove Docker plugin
2. Restore original daemon.json from backup
3. Restart Docker

**Note**: OPA binary and policies are kept for reference. To remove completely:
```bash
sudo rm /usr/local/bin/opa
sudo rm -rf /etc/docker/policies
```

### Manual Rollback

If the uninstall script fails:

```bash
# 1. Disable plugin
docker plugin disable openpolicyagent/opa-docker-authz-v2:0.8
docker plugin rm openpolicyagent/opa-docker-authz-v2:0.8

# 2. Restore daemon config
sudo cp /etc/docker/daemon.json.backup-* /etc/docker/daemon.json

# 3. Restart Docker
sudo systemctl restart docker

# 4. Verify
docker ps
docker run --pid=host alpine ps aux  # Should work again
```

---

## Performance Impact

### Expected Overhead

- **Latency**: +5-15ms per Docker command (OPA policy evaluation)
- **Memory**: +50-100MB (OPA process and plugin)
- **CPU**: Negligible (OPA is very efficient)

### Measurement

```bash
# Test without OPA (after uninstall)
time docker run --rm alpine echo "test"

# Test with OPA (after install)
time docker run --rm alpine echo "test"

# Compare times
```

**Typical results**:
- Without OPA: ~0.5-1 second
- With OPA: ~0.5-1.02 seconds
- **Impact**: ~10-20ms (negligible for most use cases)

---

## Security Considerations

### What OPA Protects Against

✅ **Protected**:
- Cannot bypass with `/usr/bin/docker` (enforced at daemon level)
- Applies to all users on the system
- Cannot be disabled without root access
- Policy violations are logged

### What OPA Does NOT Protect Against

⚠️ **Not Protected**:
- Compromised Docker daemon (attacker with root on host)
- Kernel exploits
- Other container escape vectors (beyond --pid)
- Resource exhaustion (unless policy extended)

### Defense in Depth

**Recommended layering**:
1. ✅ OPA policy (Docker API level) - **This installation**
2. ✅ Wrapper script (application level) - Already deployed
3. ⏳ AppArmor/SELinux (kernel level) - Optional enhancement
4. ⏳ User namespaces - Optional enhancement

---

## Integration with AI Agents

### How It Works with AI Agent Sandbox

**Before OPA**:
- Wrapper script blocks `--pid` in sandbox
- Can be bypassed with `/usr/bin/docker`

**After OPA**:
- OPA blocks `--pid` at daemon level
- Cannot be bypassed (not even with `/usr/bin/docker`)
- Wrapper script becomes redundant (but harmless)

### Testing with AI Agents

After installation, test with Claude:

```bash
# Should be blocked by OPA
echo 'docker run --pid=host alpine ps aux' | claude --dangerously-skip-permissions
# Expected: Error from Docker daemon (not wrapper)

# Should work normally
echo 'docker run --rm alpine ps aux' | claude --dangerously-skip-permissions
# Expected: Success
```

---

## Maintenance

### Updating OPA

```bash
# Download new version
sudo curl -L -o /usr/local/bin/opa \
  https://openpolicyagent.org/downloads/latest/opa_linux_amd64
sudo chmod +x /usr/local/bin/opa

# Restart Docker to reload
sudo systemctl restart docker

# Verify
opa version
```

### Updating Policy

```bash
# Edit policy
sudo vim /etc/docker/policies/authz.rego

# Validate syntax
sudo opa check /etc/docker/policies/authz.rego

# Apply changes
sudo systemctl restart docker

# Test
docker run --rm alpine echo "test"
```

### Monitoring

```bash
# View OPA decisions in Docker logs
sudo journalctl -u docker -f | grep -i opa

# View denied requests
sudo journalctl -u docker | grep -i "denied by plugin"

# Count denied requests
sudo journalctl -u docker --since today | grep -c "denied by plugin"
```

---

## FAQ

**Q: Will this break my existing Docker workflows?**
A: No, only `--pid` flags are blocked. All other Docker operations work normally.

**Q: Can I temporarily disable OPA?**
A: Yes: `sudo docker plugin disable openpolicyagent/opa-docker-authz-v2:0.8`

**Q: Does OPA work with Docker Compose?**
A: Yes, Docker Compose uses the Docker API, so OPA policies apply.

**Q: Can I whitelist specific containers to use --pid?**
A: Yes, you can extend the policy to allow specific containers based on image name, labels, or other criteria.

**Q: What if I need --pid for debugging?**
A: Temporarily uninstall OPA, debug, then reinstall. Or extend the policy to allow specific cases.

**Q: Does this affect Docker performance?**
A: Minimal impact: ~10-20ms latency per command (imperceptible for most use cases).

**Q: Can users still create privileged containers?**
A: Yes, by default only `--pid` is blocked. Uncomment policy rules to block other flags.

---

## Next Steps

After successful installation:

1. ✅ Test with your workflows
2. ✅ Update TODO.md to mark OPA as installed
3. ✅ Document which systems have OPA installed
4. ⏳ Consider extending policy for additional restrictions
5. ⏳ Set up monitoring/alerting for policy violations

---

**Installation Complete!**

Your Docker daemon now enforces OPA policies. The `--pid=host` vulnerability is mitigated at the daemon level.

See `docs/SECURITY_MODEL.md` for complete security documentation.
