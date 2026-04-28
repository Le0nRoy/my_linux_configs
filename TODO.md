# TODO - System Development Tasks

This file tracks ongoing development tasks for the dotfiles system and AI agent configuration.

**Last Updated**: 2026-04-08

---

## Active Tasks

### ✅ 1. Create AI Tools Pipeline (Completed 2026-04-08)

Implemented a skills-based orchestration framework replacing the previous preset/MCP/agent-roles approach.

**What was built**:
- `orchestrator-mode` skill: multi-phase workflow (plan → implement → test → review → docs → finalize)
- `bulletproof` skill: 12-stage verified dev workflow (submodule at `dot_agents/skills/bulletproof/`)
- Supporting skills: `writing-plans`, `implementing-tasks`, `planning-tests`, `writing-automated-tests`, `updating-documentation`, `subagent-driven-development`, `executing-plans`, `requesting-code-review`, `using-git-worktrees`, `finishing-a-development-branch`, `find-skills`
- `claude_wrapper`: interactive menu with orchestrate/bulletproof/plain/resume options
- `run_always_register-agent-skills.bash`: chezmoi hook linking `~/.claude/skills` → `~/.agents/skills/`
- Orchestrator and bulletproof system prompts in `bin/ai_wrapper_data/`

---

### ✅ 2. Complete xrandr Screen Management System (Completed 2025-12-05)

Comprehensive Xorg display management with automatic detection, configuration saving/loading, and rofi interface.

**See**: [docs/completed/2025-12-05-xrandr-screen-management.md](docs/completed/2025-12-05-xrandr-screen-management.md)
**Documentation**: [docs/xrandr-manager.md](docs/xrandr-manager.md)

---

### ✅ 3. Refactor helper.bash (Completed 2025-11-18)

Split monolithic helper.bash into 7 focused modules while maintaining backward compatibility.

**See**: [docs/completed/2025-11-18-helper-bash-refactor.md](docs/completed/2025-11-18-helper-bash-refactor.md)
**Documentation**: [bin/helper/README.md](bin/helper/README.md)

---

### 4. Unrestricted Sandbox Access

**Status**: Partially complete
**Priority**: High
**Description**: Allow AI agents full access within their sandboxes while maintaining sandbox security

**Completed**:
- ✅ Set all RLIMIT_* to unlimited in wrapper scripts
- ✅ Docker access enabled
- ✅ kind/Kubernetes access enabled

**Remaining**:
- Security testing of sandbox isolation
- Verify namespace isolation works correctly
- Test escape scenarios (security audit)
- Document security boundaries

**Security Testing Tasks**:
- [ ] Test filesystem isolation (can't access outside binds)
- [ ] Test process isolation (can't see/kill host processes)
- [ ] Test network isolation options
- [ ] Verify Docker-in-Docker security
- [ ] Test resource exhaustion scenarios
- [ ] Document security model

---

### 5. GitLab CI Integration

**Status**: Not started
**Priority**: Medium
**Description**: Enable AI agents to interact with GitLab CI/CD pipelines

**Requirements**:
- Read .gitlab-ci.yml configuration
- Trigger pipeline runs
- Monitor pipeline status
- Access job logs and artifacts
- Suggest CI/CD improvements

**Considerations**:
- API token management (security)
- Rate limiting
- Which operations should be allowed
- Integration with existing wrappers

---

### 6. Neovim Configuration

**Status**: Not started
**Priority**: Low
**Description**: Create comprehensive nvim configuration as PyCharm alternative

**Features Needed**:
- LSP integration (language servers)
- Code completion and IntelliSense
- Debugging support
- Git integration
- Project navigation
- Terminal integration
- Plugin management (lazy.nvim or packer.nvim)

**Must Match PyCharm Features**:
- Refactoring tools
- Find usages
- Go to definition/implementation
- Code generation
- Testing integration

---

### 7. System Installation Script

**Status**: Not started
**Priority**: Medium
**Description**: Create automated installation script for setting up the complete system on a fresh machine

**Should Install/Configure**:
- Base system packages
- chezmoi and dotfiles
- AI agent tools (Claude, Codex, Cursor)
- Docker and kind
- Development tools (compilers, runtimes)
- Shell configuration
- i3wm and related tools

**Features**:
- Idempotent (safe to run multiple times)
- Modular (select which components to install)
- Distribution-aware (Arch vs other distros)
- Backup existing configs before replacing

---

### 8. Automate upgrade_system Function

**Status**: Not started
**Priority**: Low
**Description**: Enhance and automate the `upgrade_system` function in helper.bash

**Goals**:
- Clean package cache automatically
- Remove orphaned packages
- Update all package databases
- Handle AUR packages
- Clean old kernels (keep 2 most recent)
- Clear temp files
- Restart services if needed

**Safety Features**:
- Dry-run mode
- Confirmation prompts for destructive operations
- Backup capability before major changes
- Rollback support

---

### ✅ 9. Unify AI Agent Rules (Completed 2025-12-18)

Made AGENTS.md the single source of truth; CLAUDE.md now redirects with summary.

**See**: [docs/completed/2025-12-18-unify-ai-agent-rules.md](docs/completed/2025-12-18-unify-ai-agent-rules.md)

---

### 10. Create a fully sandboxed environment for AI agents

**Status**: Not started
**Priority**: Low
**Description**: Instead of current sandbox system with access to the host network create a sandbox, which still gets host directories mounted, however has own network, with own docker daemon running. Access to the internet should persist in the sandbox. Sandbox should consume as low resources, as possible, but must have 0 possibility to harm host system. Also while developing this feature need always double check, that no secrets are mounted to the sandboxes (instead of development/testing secrets).

---

### 11. PulseAudio/PipeWire Audio Profiles Manager

**Status**: Not started
**Priority**: Medium
**Description**: Create audio routing profiles with dmenu interface for managing which applications output to which audio sinks

**Use Cases**:
- Gaming: Game audio to headphones, Discord/music to speakers
- Streaming: Capture specific apps while monitoring on headphones
- Music production: Route DAW to specific interface, system sounds elsewhere
- Video calls: Meeting audio to headphones, other apps to speakers

**Features Needed**:
- Save/load named audio routing profiles
- dmenu interface for profile selection
- Per-application sink assignment
- Move running applications between sinks
- Set default sink for new applications
- Show current audio routing status

**Implementation Ideas**:
```bash
# Profile format (JSON or simple config)
# ~/.config/audio-profiles/gaming.conf
default_sink=speakers
app:firefox=headphones
app:discord=speakers
app:steam*=headphones

# CLI commands
audio_profile.bash list              # List profiles
audio_profile.bash load <name>       # Apply profile
audio_profile.bash save <name>       # Save current routing
audio_profile.bash dmenu             # Interactive menu
audio_profile.bash move <app> <sink> # Move single app
audio_profile.bash status            # Show current routing
```

**Technical Considerations**:
- Use `pactl` for PulseAudio or `wpctl` for PipeWire
- Detect which sound server is running
- Handle sink-inputs (running streams) vs clients
- Match applications by name pattern (regex/glob)
- Handle apps that start after profile is loaded

**Related Tools**:
- `pactl list sink-inputs` - List running audio streams
- `pactl move-sink-input` - Move stream to different sink
- `pactl set-default-sink` - Set default output
- `wpctl` - PipeWire equivalent commands

---

### 12. Improve AI Sandboxing with Read-Only Mode

**Status**: Not started
**Priority**: High
**Description**: Create a read-only AI agent mode with system-wide access but strict security boundaries

**Features**:

#### 12.1 Read-Only System Access Mode
- Configure external sandbox (bubblewrap) to enforce read-only access
- NOT controlled by AI agent internal settings (agent cannot override)
- Full system read access for information gathering
- No write capabilities anywhere

#### 12.2 Exclude Directories with Secrets
- Automatically exclude sensitive directories from bind mounts:
  - `${HOME}/.ssh` - SSH keys and known_hosts
  - `/Job/secrets` - Work-related secrets
  - `${HOME}/.kube` - Kubernetes credentials
  - `${HOME}/.config/gcloud` - GCP credentials
  - `${HOME}/.aws` - AWS credentials
  - `${HOME}/.gnupg` - GPG keys
  - `${HOME}/.password-store` - pass password manager
  - Add configurable list for additional paths

#### 12.3 Alternative User Execution (Optional)
- Explore running AI agent as different user
- User would have read-only access to specific files
- More robust isolation than bubblewrap alone
- May require sudo/polkit configuration

**Implementation Notes**:
- Create new wrapper: `executable_claude_ro_wrapper.bash`
- Use `--ro-bind` for all mounts
- Create exclusion list config file: `~/.config/ai-sandbox/secrets-exclusion.conf`
- Document which directories are excluded and why

---

### 13. Verify Sandboxed Agent Subagent Capabilities

**Status**: Not started
**Priority**: High
**Description**: Verify and document subagent orchestration capabilities for sandboxed AI agents

**Requirements**:

#### 13.1 Workdir Read-Write Subagents
- Sandboxed RW agent can spawn subagents in workdir
- Subagents inherit workdir write access
- Subagents can access subdirectories of workdir

#### 13.2 System-Wide Read-Only Subagents
- RW agent can spawn RO subagents with system-wide access
- RO subagents can gather information from:
  - Installed packages (`pacman -Q`, `dpkg -l`)
  - System configurations (`/etc/`)
  - Hardware info (`lspci`, `lsusb`, `sensors`)
  - Display info (`xrandr`, Xorg configs)
  - GPU info (`nvidia-smi`, `nvidia-settings`)
  - Network configuration

#### 13.3 Information Collection Use Cases
- Collect system state to improve dotfiles scripts:
  - `xrandr` screen management
  - Proton game launcher configuration
  - Hardware sensors reading
  - NVIDIA GPU info retrieval
  - System installation reproduction script
- RO subagent gathers info, passes to RW agent on-demand
- RW agent uses info to enhance scripts

#### 13.4 Subagent Limits
- Maximum concurrent subagents must be configurable
- Default limit: TBD (suggest: 3-5)
- Configuration location: `~/.config/ai-sandbox/subagent-limits.conf`
- Prevent resource exhaustion from runaway subagent spawning

**Testing Plan**:
- [ ] Test RW agent spawning RW subagent in workdir
- [ ] Test RW agent spawning RO system-wide subagent
- [ ] Test RO subagent cannot write anywhere
- [ ] Test subagent limit enforcement
- [ ] Test information passing between subagents and parent
- [ ] Document orchestration patterns

**Related Tasks**: Task 10 (Fully sandboxed environment), Task 12 (RO mode)

---

### 14. Migrate AI Rules to Standalone Repository

**Status**: Not started
**Priority**: Medium
**Description**: Extract AI agent rules and skills into a standalone `ai-rules` git repository, connected to the dotfiles repo as a submodule. This decouples AI workflow definitions from system configuration.

**Plan**: [docs/plans/2026-04-02-ai-rules-repository-migration.md](docs/plans/2026-04-02-ai-rules-repository-migration.md)

**Key tasks**:
1. Create `~/projects/ai-rules/` repo with `AGENTS.md` and `skills/`
2. Add `ai-rules` as submodule in the dotfiles repo at `dot_agents/`
3. Update `run_always_register-agent-skills.bash` for submodule init
4. Update wrapper prompts and docs to reflect new paths

**Open questions before starting**:
- Where will `ai-rules` be hosted? (GitHub/GitLab/private)
- Should it be public?
- Confirm bulletproof submodule remote URL

---

## Task Management Rules

### When Starting a Task
1. Update status from "Not started" to "In progress"
2. Add your name/agent and date started
3. Create subtasks if needed
4. Update priority if circumstances changed

### During Task Execution
1. Update progress regularly
2. Document blockers and decisions
3. Add notes about unexpected findings
4. Link to related commits/branches

### When Task is Complete
1. Mark status as "Completed"
2. Add completion date
3. Move full task description to `docs/completed/YYYY-MM-DD-task-name.md`
4. Leave brief summary in TODO with link to docs
5. Update related documentation (AGENTS.md, CLAUDE.md, etc.)

### Task Decomposition
When a task is broken down into smaller tasks:
1. Update this file with subtasks
2. Link parent and child tasks
3. Consider if subtasks warrant separate doc entries

---

## Notes

- This file should be updated by both user and AI agents
- Check this file when starting new work to see if task has prior progress
- Completed task documentation goes to `docs/completed/` directory
- `docs/` directory is ignored by chezmoi (see .chezmoiignore)
