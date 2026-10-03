# Working across PACE and a development machine

Use Git for source, documentation, and deliberately selected assets. Simulation
inputs, generated data, local logs, caches, and archives stay local unless
explicitly included in a release. See [data availability](../../DATA_AVAILABILITY.md).

Inspect the actual remote and branch instead of assuming an account or URL:

```bash
git remote -v
git branch --show-current
git status --short
git fetch origin
git log --oneline --left-right HEAD...origin/main
```

A clean checkout that is only behind can be updated with
`git merge --ff-only origin/main`. If histories diverge, preserve both sets of
commits, review and resolve conflicts, and use a normal merge. Do not force push
or rewrite shared history. Preserve local staged, unstaged, and untracked work
before integrating remote changes.

On either machine, stage explicit paths and review the staged content:

```bash
git diff
git add path/to/changed_file
git diff --cached
git status --short
git commit -m "Describe the concrete change and its purpose"
git push origin main
```

These are examples for an authorized commit/synchronization task. Coding agents
follow [AGENTS.md](../../AGENTS.md), including its authorization rules. Never use
force-add to include ignored research data inadvertently.

After pushing, compare `git rev-parse HEAD` with `git ls-remote origin refs/heads/main`
and inspect the local worktree. On the other machine, fetch and review before
integrating. A rejected push usually means the remote advanced; inspect those
commits instead of overwriting them.

PACE runs heavy experiments through Slurm; the development machine can edit
source and perform lightweight checks. Use [the current run guide](PACE_RUN_GUIDE.md)
for job entry points. Old machine-specific scripts and the retired threshold
workflow are not synchronization prerequisites.
