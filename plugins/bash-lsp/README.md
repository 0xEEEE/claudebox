# bash-lsp

Claude Code LSP plugin for [bash-language-server](https://github.com/bash-lsp/bash-language-server), providing intelligent code assistance for Bash and shell scripts.

## Features

bash-language-server provides:
- Code navigation (go to definition, find references)
- Completions and auto-suggestions
- Hover documentation
- Symbol outline
- Diagnostics via shellcheck integration
- Code formatting via shfmt

## Requirements

In ClaudeBox containers with the `bash` profile, bash-language-server is pre-installed via bun for better performance.

For manual installation outside containers:

```bash
# Using bun (recommended for performance)
bun install -g bash-language-server

# Or using npm
npm install -g bash-language-server
```

## Installation

### Option 1: Load directly (development/testing)

```bash
claude --plugin-dir /path/to/claudebox/plugins/bash-lsp
```

### Option 2: Install to user scope

Copy this plugin to your Claude Code plugins directory:

```bash
mkdir -p ~/.claude/plugins/bash-lsp
cp -r /path/to/claudebox/plugins/bash-lsp/* ~/.claude/plugins/bash-lsp/
```

Then enable it in Claude Code:
```
/plugin enable bash-lsp
```

## Usage

Once installed and bash-language-server is in your PATH, Claude Code will automatically:
- Show syntax errors and shellcheck diagnostics
- Provide code navigation for shell scripts
- Offer completions and documentation

## Supported File Extensions

- `.sh` - Bash/shell scripts
- `.bash` - Bash scripts
- `.bashrc`, `.bash_profile`, `.bash_aliases` - Bash configuration files
- `.zsh`, `.zshrc` - Zsh scripts (basic support)

## Dependencies

For full functionality, these tools should also be installed:
- `shellcheck` - Shell script static analysis
- `shfmt` - Shell script formatter

Both are included in the ClaudeBox `bash` profile.

## Links

- [bash-language-server GitHub](https://github.com/bash-lsp/bash-language-server)
- [ShellCheck](https://www.shellcheck.net/)
- [shfmt](https://github.com/mvdan/sh)
