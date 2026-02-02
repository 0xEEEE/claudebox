# ty-lsp

Claude Code LSP plugin for [ty](https://github.com/astral-sh/ty), the extremely fast Python type checker and language server from Astral.

## Features

ty provides:
- **10-100x faster** than mypy and Pyright
- Code navigation (go to definition, find references)
- Completions and auto-import
- Code actions and quick fixes
- Inlay hints and hover information
- Real-time diagnostics

## Requirements

ty must be installed and available in your PATH:

```bash
# Using uv (recommended)
uv tool install ty

# Or using pip
pip install ty

# Or using pipx
pipx install ty
```

## Installation

### Option 1: Load directly (development/testing)

```bash
claude --plugin-dir /path/to/claudebox/plugins/ty-lsp
```

### Option 2: Install to user scope

Copy this plugin to your Claude Code plugins directory:

```bash
mkdir -p ~/.claude/plugins/ty-lsp
cp -r /path/to/claudebox/plugins/ty-lsp/* ~/.claude/plugins/ty-lsp/
```

Then enable it in Claude Code:
```
/plugin enable ty-lsp
```

## Usage

Once installed and ty is in your PATH, Claude Code will automatically:
- Show type errors and warnings after edits
- Provide code navigation for Python files
- Offer completions and auto-imports

## Configuration

ty can be configured via `ty.toml` or `pyproject.toml` in your project root:

```toml
# ty.toml
[tool.ty]
python-version = "3.11"
```

## Troubleshooting

If you see "Executable not found in $PATH":
1. Verify ty is installed: `ty --version`
2. Ensure ty is in your PATH
3. Restart Claude Code

## Links

- [ty Documentation](https://docs.astral.sh/ty/)
- [ty GitHub](https://github.com/astral-sh/ty)
- [ty Playground](https://play.ty.dev)
