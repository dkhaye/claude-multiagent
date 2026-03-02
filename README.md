# claude-multiagent

A template for running autonomous multi-agent Claude Code workspaces. Spin up a Lead + Author + Reviewer pipeline in a tmux session, coordinated via Beads for atomic task distribution.

## Architecture

```
command-center (human-facing Claude Code session)
    │
    ├── plans work, writes to Lead inbox
    │
    └── tmux session: [[PROJECT_NAME]]
            │
            ├── pane 0: Lead agent (orchestrator)
            │       reads task-board.md, stocks Beads queue, monitors CI
            │
            ├── pane 1–3: Author agents (workers)
            │       pull tasks from Beads, write code, open PRs
            │
            └── pane 4: Reviewer agent (quality gate)
                    reviews PRs, posts gh pr review, captures learnings
```

**Coordination:** Agents communicate via files in `metadata/messages/<agent>/`. Each agent has an inbox directory; messages are individual timestamped `.md` files. No agent polls a shared file — each reads and deletes files from its own directory.

**Task distribution:** The Lead publishes tasks to a central [Beads](https://github.com/nicholasgasior/beads) database. Authors claim tasks atomically with `bd update <id> --claim`, preventing double-claiming without a lock server.

## Prerequisites

- [Claude Code](https://github.com/anthropics/claude-code) (`claude` CLI)
- [tmux](https://github.com/tmux/tmux)
- [Beads (`bd`)](https://github.com/nicholasgasior/beads) — task distribution
- [GitHub CLI (`gh`)](https://cli.github.com/)
- `jq` — for registry updates

## Creating a new project

```bash
git clone https://github.com/dkhaye/claude-multiagent
cd claude-multiagent
./new-project.sh [[PROJECT_NAME]]
```

This copies the template to `~/projects/[[PROJECT_NAME]]`, substitutes all `[[PROJECT_NAME]]` placeholders, initialises git and beads-central, and prints next steps.

## Project configuration

Each role has a `## Project Configuration` block at the top of its CLAUDE.md that you fill in for your project:

| File | What to configure |
|------|-------------------|
| `.claude-workspace/lead-agent/CLAUDE.md` | repos, read-only repos, languages, ticket project |
| `.claude-workspace/author-template/CLAUDE.md` | languages, static analysis tools, PR format |
| `.claude-workspace/reviewer/CLAUDE.md` | static analysis tools, review criteria, learnings categories |
| `.claude-workspace/command-center/CLAUDE.md` | repo table, org, ticket system |

## Launching

```bash
# Start agents in tmux
cd ~/projects/[[PROJECT_NAME]]
./launch-agents.sh

# Open command center in a separate terminal
cd ~/projects/[[PROJECT_NAME]]/.claude-workspace/command-center
claude
```

## Directory structure

```
[[PROJECT_NAME]]/
├── .claude-workspace/          # Agent working directories and CLAUDE.md files
│   ├── lead-agent/
│   ├── author-template/
│   ├── reviewer/
│   └── command-center/
├── beads-central/              # Shared Beads task database
├── metadata/
│   ├── messages/               # Agent inboxes (directories, not files)
│   │   ├── lead/
│   │   ├── author-1/
│   │   ├── author-2/
│   │   ├── author-3/
│   │   ├── reviewer/
│   │   └── human/              # Action items for the operator
│   ├── tmp/
│   │   ├── beads/              # Beads task description staging files
│   │   └── session/            # Per-agent temp files (commit msgs, PR bodies)
│   ├── learnings/              # Knowledge captured by the Reviewer
│   ├── logs/                   # agent-loop.sh logs
│   ├── task-board.md           # Human-readable task backlog
│   ├── agent-assignments.md    # Worktrees and open PRs (for CI monitoring)
│   ├── open-prs.json           # Machine-readable PR list
│   ├── worktree-registry.json  # Active/completed worktrees
│   └── dependency-graph.json   # Task dependency tracking
├── repos/                      # Reference clones (read-only for most agents)
├── worktrees/                  # Feature worktrees created by Lead
├── scripts/
│   ├── env.sh                  # Environment setup (WORKSPACE_ROOT, BEADS_DIR, PATH)
│   ├── agent-loop.sh           # Polling loop that starts/restarts Claude sessions
│   ├── beads-publish.sh        # bd create + bd update + rm in one command
│   ├── create-feature-worktrees.sh
│   ├── cleanup-worktrees.sh
│   ├── validate-path.sh
│   └── prompts/
│       ├── lead.txt
│       ├── author.txt
│       └── reviewer.txt
└── launch-agents.sh
```

## Key design decisions

- **Directory-based inboxes:** Each agent's inbox is a directory of individual message files. No concurrent writes to a shared file — messages accumulate and agents delete them after processing.
- **Atomic task claiming:** `bd update <id> --claim` is atomic. Authors never double-claim.
- **Staggered polling:** Authors poll at 30s, 47s, 64s offsets to prevent thundering herd on the Beads database.
- **No PR approval by agents:** The Reviewer only posts `--comment` or `--request-changes`. Merge approval is always the human operator's decision.
- **Temp file isolation:** Commit messages and PR bodies are written to `metadata/tmp/session/<agent>/` with timestamps, not to worktree root. This prevents write conflicts when multiple sessions touch the same worktree at different times.

## License

MIT
