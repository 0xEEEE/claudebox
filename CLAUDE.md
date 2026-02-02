# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClaudeBox is a Docker-based development environment for Claude CLI with 1000+ users. It provides isolated, reproducible containerization with 20+ development profiles, multi-instance support via slots, and project-specific isolation.

**Repository**: https://github.com/RchGrav/claudebox
**Version**: 2.0.0
**License**: MIT

## Critical Requirements

- **Bash 3.2 compatibility ONLY** - macOS ships with Bash 3.2; this ensures cross-platform support
- **Preserve ALL existing functionality** - breaking changes have caused days of lost work
- **Read and understand code thoroughly** before suggesting any modifications

## Development Commands

```bash
# Run Bash 3.2 compatibility tests
cd tests && ./test_bash32_compat.sh

# Run tests in Docker with actual Bash 3.2
cd tests && ./test_in_bash32_docker.sh

# Static analysis with ShellCheck
shellcheck main.sh lib/*.sh

# Build self-extracting installer
bash .builder/build.sh

# Run installer (outputs to dist/)
./claudebox.run
```

## High-Level Architecture

### Entry Point

`main.sh` (~700 lines) - Orchestrates everything: path resolution, library loading, CLI parsing, Docker setup, and container execution.

### Library Modules (`lib/`)

| Module | Purpose |
|--------|---------|
| `cli.sh` | Four-bucket CLI parser (see below) |
| `common.sh` | Utilities, logging (`cecho`, `error`, `warn`, `success`), color constants |
| `env.sh` | Environment variables, Docker user constants, version numbers |
| `os.sh` | Platform detection (Linux/macOS) |
| `config.sh` | Profile definitions (20+ profiles with packages/descriptions) |
| `project.sh` | Multi-slot container system, CRC32 naming, slot generation |
| `docker.sh` | Image building, container lifecycle, Docker installation |
| `state.sh` | Symlink maintenance, project directory init |
| `commands.sh` | Central command dispatcher |
| `commands.core.sh` | `help`, `shell`, `update` |
| `commands.profile.sh` | `profiles`, `profile`, `add`, `remove`, `install` |
| `commands.slot.sh` | `create`, `slots`, `slot`, `revoke` |
| `commands.info.sh` | `info`, `projects`, `allowlist` |
| `commands.clean.sh` | `clean`, `undo`, `redo` |
| `commands.system.sh` | `save`, `unlink`, `rebuild`, `tmux`, `project` |
| `preflight.sh` | Pre-execution validation |
| `welcome.sh` | First-time user onboarding |

### Four-Bucket CLI Architecture

The CLI parser in `lib/cli.sh` categorizes all arguments into four buckets:

```
claudebox --verbose rebuild --enable-sudo -c "prompt"
    │         │         │           │           │
    │         │         │           │           └─► Bucket 4: Pass-through (to Claude)
    │         │         │           └─────────────► Bucket 2: Control flags (to container env)
    │         │         └─────────────────────────► Bucket 1: Host-only (consumed by script)
    │         └───────────────────────────────────► Bucket 1: Host-only
    └─────────────────────────────────────────────► Bucket 3: Script command
```

- **Bucket 1 (Host-only)**: `--verbose`, `rebuild`, `tmux` - consumed on host, not passed
- **Bucket 2 (Control)**: `--enable-sudo`, `--disable-firewall` - become container env vars
- **Bucket 3 (Script)**: ClaudeBox commands handled on host (`profile`, `clean`, `info`, etc.)
- **Bucket 4 (Pass-through)**: Everything else forwarded to `claude` CLI in container

### Build System (`.builder/`)

- `build.sh` - Creates self-extracting installer
- `script_template_root.sh` - Installer template
- Output: `dist/claudebox.run` (self-extracting), `dist/claudebox-<version>.tar.gz`

### Docker Build (`build/`)

- `Dockerfile` - Multi-stage build with ARGs for USER_ID, GROUP_ID, NODE_VERSION
- `docker-entrypoint` - Container initialization, venv setup, firewall rules

## CRITICAL DESIGN DECISIONS - DO NOT CHANGE

### Container Management
- **Named containers WITH --rm flag** - Intentional and works perfectly
- **Containers are ephemeral** - Created, run, auto-delete on exit
- **DO NOT remove --rm flag** - Containers must clean themselves up
- **DO NOT try to delete containers on start** - They don't exist (--rm removed them)

### Docker Images
- **Images shared across all slots** - Named after parent (slot 0)
- **Layer caching is critical** - DO NOT force `--no-cache` unless explicitly requested
- **DO NOT delete images during rebuild** - Docker handles layer updates automatically

### Slot System
- **Slots start at 1, not 0** - Slot 0 conceptually represents the parent
- **Counter value 0 means no slots exist**
- **Lock files NOT used** - Container names provide the locking mechanism
- **Check `docker ps` for running containers** - This is the source of truth

### Common Mistakes to Avoid
1. DO NOT assume named containers can't use `--rm` - They can and must
2. DO NOT delete non-existent containers - They're already gone from `--rm`
3. DO NOT force `--no-cache` on rebuilds - Layer caching is intentional
4. DO NOT change the slot numbering system - Designed for hash uniqueness
5. DO NOT add lock files - Docker container names are the locks
6. DO NOT redirect stderr to `/dev/null` - Errors needed for troubleshooting
7. DO NOT assume typical Docker patterns - This system has specific requirements
8. **NEVER USE `git restore HEAD`** without explicit user instruction - Always `git stash` first

## CRITICAL: Error Handling with set -e

Scripts use `set -euo pipefail` - ANY non-zero return exits immediately.

**WRONG** (exits script unexpectedly):
```bash
[[ "$VERBOSE" == "true" ]] && echo "Debug message"
grep "pattern" file && echo "Found it"
```

**CORRECT** (use if statements):
```bash
if [[ "$VERBOSE" == "true" ]]; then
    echo "Debug message"
fi

if grep "pattern" file; then
    echo "Found it"
fi
```

- **NEVER use `&&` for conditional execution** - Use `if` statements
- **NEVER use `||` as a fallback** - Handle errors explicitly
- If you must use `&&`/`||`, ensure line always exits 0: `command || true`

## Bash 3.2 Compatibility Rules

macOS ships with Bash 3.2. These features are **NOT available**:

| Forbidden | Alternative |
|-----------|-------------|
| `declare -A` (associative arrays) | Use function-based lookups |
| `${var^^}` (uppercase) | Use `tr '[:lower:]' '[:upper:]'` |
| `${var,,}` (lowercase) | Use `tr '[:upper:]' '[:lower:]'` |
| `[[ -v var ]]` (variable check) | Use `[ "${var:-}" = "" ]` |
| `readlink -f` | Use portable loop |

## Portability Rules (macOS / Linux)

- **Interpreter**: Use `#!/usr/bin/env bash`
- **sed -i**: Requires empty suffix on BSD: `sed -i ''` or use temp file
- **stat**: Avoid entirely - output formats diverge
- **Command discovery**: Use `command -v`, never `which`
- **Option parsing**: Use `getopts`, never `getopt`

## Output Philosophy

- **NO UNNECESSARY OUTPUT** - Clean, purposeful output only
- **ALWAYS USE PRINTF** - Never `echo` for output (behavior varies across platforms)
- Use `printf '%s\n' "$var"` instead of `echo "$var"`
- Verbose mode (`--verbose`) exists for those who want detailed output

## Project Data Structure

```
~/.claudebox/
├── source/                      # ClaudeBox installation
├── projects/
│   └── <project>_<crc>/
│       ├── .project_container_counter
│       ├── .project_path
│       ├── profiles.ini
│       ├── .claude/             # Auth state
│       ├── .zsh_history
│       └── firewall/allowlist
├── default-flags
└── docker-build-context/

~/.local/bin/claudebox → ~/.claudebox/source/main.sh
```

## Safety Flags

Every executable script must have (after shebang):

```bash
set -Eeuo pipefail
IFS=$'\n\t'
```

## Code Analysis Approach

1. **READ** the entire relevant code section first - never grep and guess
2. **TRACE** through execution paths to understand dependencies
3. **ASK** clarifying questions if functionality is unclear
4. **TEST** mentally against Bash 3.2 constraints before suggesting any changes
5. **PROPOSE** minimal necessary changes with clear explanations

<!-- BACKLOG.MD GUIDELINES START -->
# Instructions for the usage of Backlog.md CLI Tool

## 1. Source of Truth

- Tasks live under **`backlog/tasks/`** (drafts under **`backlog/drafts/`**).
- Every implementation decision starts with reading the corresponding Markdown task file.
- Project documentation is in **`backlog/docs/`**.
- Project decisions are in **`backlog/decisions/`**.

## 2. Defining Tasks

### **Title**

Use a clear brief title that summarizes the task.

### **Description**: (The **"why"**)

Provide a concise summary of the task purpose and its goal. Do not add implementation details here. It
should explain the purpose and context of the task. Code snippets should be avoided.

### **Acceptance Criteria**: (The **"what"**)

List specific, measurable outcomes that define what means to reach the goal from the description. Use checkboxes (`- [ ]`) for tracking.
When defining `## Acceptance Criteria` for a task, focus on **outcomes, behaviors, and verifiable requirements** rather
than step-by-step implementation details.
Acceptance Criteria (AC) define *what* conditions must be met for the task to be considered complete.
They should be testable and confirm that the core purpose of the task is achieved.
**Key Principles for Good ACs:**

- **Outcome-Oriented:** Focus on the result, not the method.
- **Testable/Verifiable:** Each criterion should be something that can be objectively tested or verified.
- **Clear and Concise:** Unambiguous language.
- **Complete:** Collectively, ACs should cover the scope of the task.
- **User-Focused (where applicable):** Frame ACs from the perspective of the end-user or the system's external behavior.

    - *Good Example:* "- [ ] User can successfully log in with valid credentials."
    - *Good Example:* "- [ ] System processes 1000 requests per second without errors."
    - *Bad Example (Implementation Step):* "- [ ] Add a new function `handleLogin()` in `auth.ts`."

### Task file

Once a task is created it will be stored in `backlog/tasks/` directory as a Markdown file with the format
`task-<id> - <title>.md` (e.g. `task-42 - Add GraphQL resolver.md`).

### Additional task requirements

- Tasks must be **atomic** and **testable**. If a task is too large, break it down into smaller subtasks.
  Each task should represent a single unit of work that can be completed in a single PR.

- **Never** reference tasks that are to be done in the future or that are not yet created. You can only reference
  previous
  tasks (id < current task id).

- When creating multiple tasks, ensure they are **independent** and they do not depend on future tasks.
  Example of wrong tasks splitting: task 1: "Add API endpoint for user data", task 2: "Define the user model and DB
  schema".
  Example of correct tasks splitting: task 1: "Add system for handling API requests", task 2: "Add user model and DB
  schema", task 3: "Add API endpoint for user data".

## 3. Recommended Task Anatomy

```markdown
# task-42 - Add GraphQL resolver

## Description (the why)

Short, imperative explanation of the goal of the task and why it is needed.

## Acceptance Criteria (the what)

- [ ] Resolver returns correct data for happy path
- [ ] Error response matches REST
- [ ] P95 latency <= 50 ms under 100 RPS

## Implementation Plan (the how)

1. Research existing GraphQL resolver patterns
2. Implement basic resolver with error handling
3. Add performance monitoring
4. Write unit and integration tests
5. Benchmark performance under load

## Implementation Notes (only added after working on the task)

- Approach taken
- Features implemented or modified
- Technical decisions and trade-offs
- Modified or added files
```

## 4. Implementing Tasks

Mandatory sections for every task:

- **Implementation Plan**: (The **"how"**) Outline the steps to achieve the task. Because the implementation details may
  change after the task is created, **the implementation notes must be added only after putting the task in progress**
  and before starting working on the task.
- **Implementation Notes**: Document your approach, decisions, challenges, and any deviations from the plan. This
  section is added after you are done working on the task. It should summarize what you did and why you did it. Keep it
  concise but informative.

**IMPORTANT**: Do not implement anything else that deviates from the **Acceptance Criteria**. If you need to
implement something that is not in the AC, update the AC first and then implement it or create a new task for it.

## 5. Typical Workflow

```bash
# 1 Identify work
backlog task list -s "To Do" --plain

# 2 Read details & documentation
backlog task 42 --plain
# Read also all documentation files in `backlog/docs/` directory.
# Read also all decision files in `backlog/decisions/` directory.

# 3 Start work: assign yourself & move column
backlog task edit 42 -a @{yourself} -s "In Progress"

# 4 Add implementation plan before starting
backlog task edit 42 --plan "1. Analyze current implementation\n2. Identify bottlenecks\n3. Refactor in phases"

# 5 Break work down if needed by creating subtasks or additional tasks
backlog task create "Refactor DB layer" -p 42 -a @{yourself} -d "Description" --ac "Tests pass,Performance improved"

# 6 Complete and mark Done
backlog task edit 42 -s Done --notes "Implemented GraphQL resolver with error handling and performance monitoring"
```

## 6. Final Steps Before Marking a Task as Done

Always ensure you have:

1. Marked all acceptance criteria as completed (change `- [ ]` to `- [x]`)
2. Added an `## Implementation Notes` section documenting your approach
3. Run all tests and linting checks
4. Updated relevant documentation

## 7. Definition of Done (DoD)

A task is **Done** only when **ALL** of the following are complete:

1. **Acceptance criteria** checklist in the task file is fully checked (all `- [ ]` changed to `- [x]`).
2. **Implementation plan** was followed or deviations were documented in Implementation Notes.
3. **Automated tests** (unit + integration) cover new logic.
4. **Static analysis**: linter & formatter succeed.
5. **Documentation**:
    - All relevant docs updated (any relevant README file, backlog/docs, backlog/decisions, etc.).
    - Task file **MUST** have an `## Implementation Notes` section added summarising:
        - Approach taken
        - Features implemented or modified
        - Technical decisions and trade-offs
        - Modified or added files
6. **Review**: self review code.
7. **Task hygiene**: status set to **Done** via CLI (`backlog task edit <id> -s Done`).
8. **No regressions**: performance, security and licence checks green.

## 8. Handy CLI Commands

| Purpose | Command |
|---------|---------|
| Create task | `backlog task create "Add OAuth"` |
| Create with desc | `backlog task create "Feature" -d "Enables users to use this feature"` |
| Create with AC | `backlog task create "Feature" --ac "Must work,Must be tested"` |
| Create with deps | `backlog task create "Feature" --dep task-1,task-2` |
| Create sub task | `backlog task create -p 14 "Add Google auth"` |
| List tasks | `backlog task list --plain` |
| View detail | `backlog task 7 --plain` |
| Edit | `backlog task edit 7 -a @{yourself} -l auth,backend` |
| Add plan | `backlog task edit 7 --plan "Implementation approach"` |
| Add AC | `backlog task edit 7 --ac "New criterion,Another one"` |
| Add deps | `backlog task edit 7 --dep task-1,task-2` |
| Add notes | `backlog task edit 7 --notes "We added this and that feature because"` |
| Mark as done | `backlog task edit 7 -s "Done"` |
| Archive | `backlog task archive 7` |
| Draft flow | `backlog draft create "Spike GraphQL"` then `backlog draft promote 3.1` |
| Demote to draft | `backlog task demote <task-id>` |

## 9. Tips for AI Agents

- **Always use `--plain` flag** when listing or viewing tasks for AI-friendly text output instead of using Backlog.md
  interactive UI.
- When users mention to create a task, they mean to create a task using Backlog.md CLI tool.

<!-- BACKLOG.MD GUIDELINES END -->
