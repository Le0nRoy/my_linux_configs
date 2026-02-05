# Claude Wrapper Help

This wrapper provides interactive menus for connecting MCPs (Model Context Protocol servers)
and skills to your Claude CLI session.

## Menu Navigation

- **Number keys**: Select/toggle items
- **b** or **back**: Return to previous menu
- **r** or **reset**: Clear all selections in current menu
- **d** or **done**: Confirm selections and return to main menu

## Available MCPs

### Kubernetes (RO)
Read-only access to Kubernetes clusters.

**Capabilities**:
- View pods, deployments, services
- Read pod logs
- Inspect cluster resources
- List namespaces

**Setup**:
The wrapper will automatically prompt you to configure Kubernetes access when you
select this MCP for the first time. You can also run the setup manually:

```bash
# Interactive setup (recommended)
setup_ai_kube_access.bash

# Setup for specific context
setup_ai_kube_access.bash my-cluster-context

# Check if already configured
setup_ai_kube_access.bash --check

# Test existing configuration
setup_ai_kube_access.bash --test

# Refresh expired token
setup_ai_kube_access.bash my-cluster-context --refresh

# List available contexts
setup_ai_kube_access.bash --list
```

**Configuration**:
- Config stored at: `~/.kube/ai-agent-config`
- Creates a ServiceAccount with read-only permissions (pods, logs, namespaces)
- Token valid for 1 year (can be refreshed with `--refresh`)

**Requirements**:
- kubectl installed and configured with cluster access
- Permission to create ServiceAccount and ClusterRoleBinding in target cluster

### GitLab (RO)
Read-only access to GitLab instance.

**Capabilities**:
- View CI/CD jobs and pipelines
- Read merge request comments
- Access project information

**Setup**:
1. Create GitLab Personal Access Token with `read_api` scope
2. Set environment variable: `export GITLAB_TOKEN=<your-token>`
3. GitLab URL is configured per-project (stored in `.claude-wrapper/gitlab-url`)

### Docker (RW)
Full access to local Docker daemon.

**Capabilities**:
- List and manage containers
- Build and manage images
- Access volumes and networks

**Setup**:
1. Ensure Docker daemon is running
2. Add user to `docker` group: `sudo usermod -aG docker $USER`

### GitHub (RO)
Read-only access to GitHub.

**Capabilities**:
- View repositories
- Read issues and pull requests
- Access GitHub Actions

**Setup**:
1. Create GitHub Personal Access Token with `repo:read` scope
2. Set environment variable: `export GITHUB_TOKEN=<your-token>`

### Confluence (RO)
Read-only access to Confluence documentation.

**Capabilities**:
- Search and read pages
- Access space documentation

**Setup**:
1. Get Confluence API token from your Atlassian account
2. Set environment variables:
   ```bash
   export CONFLUENCE_URL=https://your-org.atlassian.net/wiki
   export CONFLUENCE_USER=your-email@example.com
   export CONFLUENCE_TOKEN=<your-api-token>
   ```

## Available Skills

### Code Review
| Skill | Description |
|-------|-------------|
| Code Review | General code review and suggestions |
| Python Review | Python-specific code review and PEP compliance |
| Bash Review | Bash script review and best practices |
| Go Review | Go code review and idiomatic patterns |

### Testing
| Skill | Description |
|-------|-------------|
| Testing | Test development, coverage analysis, test strategies |

### DevOps
| Skill | Description |
|-------|-------------|
| K8s Debug | Kubernetes debugging and troubleshooting |

### Documentation
| Skill | Description |
|-------|-------------|
| README | README generation and improvement |
| API Docs | API documentation generation |

### Security
| Skill | Description |
|-------|-------------|
| Security Review | Security scanning and vulnerability analysis |

## Presets

Presets are pre-configured combinations of MCPs and skills for common workflows.
Selecting a preset clears other selections and starts a session immediately.

### Code Reviewer
For comprehensive code review tasks.
- **MCPs**: GitHub (RO), GitLab (RO)
- **Skills**: Code Review, Python Review, Go Review, Bash Review, Security Review

### Test Engineer
For test development and coverage improvement.
- **MCPs**: None
- **Skills**: Testing, Code Review

### DevOps Debugger
For troubleshooting infrastructure and CI/CD issues.
- **MCPs**: Kubernetes (RO), GitLab (RO), Docker (RW), Confluence (RO)
- **Skills**: K8s Debug

## Project-Local Storage

The wrapper stores project-specific configuration in `.claude-wrapper/` directory:
- `gitlab-url`: GitLab instance URL for this project
- This directory is automatically added to `.git/info/exclude`

## Manual MCP Configuration

You can also configure MCPs manually using the Claude CLI:

```bash
# Add an MCP
claude mcp add <mcp-name> -- <command> [args...]

# List configured MCPs
claude mcp list

# Remove an MCP
claude mcp remove <mcp-name>
```

## Manual Skill Installation

Skills can be installed manually:

```bash
# Install a skill
npx @anthropic/skills add <skill-name>

# List installed skills
claude skills list
```

## Environment Variables

For convenient setup, add these to your shell profile (`~/.bashrc` or `~/.zshrc`):

```bash
# GitHub access
export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"

# GitLab access
export GITLAB_TOKEN="glpat-xxxxxxxxxxxx"

# Confluence access (if used)
export CONFLUENCE_URL="https://your-org.atlassian.net/wiki"
export CONFLUENCE_USER="your-email@example.com"
export CONFLUENCE_TOKEN="xxxxxxxxxxxx"
```

## Troubleshooting

### MCP not connecting
1. Check if required environment variables are set: `env | grep TOKEN`
2. Verify the MCP server can start: `npx -y @anthropic/mcp-<name> --help`
3. Check Claude logs: `~/.claude/logs/`

### Skills not loading
1. Check if skill is installed: `ls ~/.claude/skills/`
2. Reinstall: `npx @anthropic/skills add <skill-name>`

### Permission errors
1. Verify file permissions for kubeconfig and token files
2. Check Docker socket access: `docker ps`

## Keyboard Shortcuts

In Claude CLI:
- `Ctrl+C`: Cancel current operation
- `Ctrl+D`: Exit session
- `/help`: Show Claude CLI help
- `/mcp`: Show MCP status
