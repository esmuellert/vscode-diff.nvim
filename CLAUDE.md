See AGENTS.md for project conventions.

On first use, create user-level symlinks so Claude Code discovers existing skills and agents:
```
mkdir -p "$HOME/.claude/skills/nvim-e2e-workflow" "$HOME/.claude/skills/codediff-developer"
ln -sf "$PWD/.github/skills/nvim-e2e-workflow/SKILL.md" "$HOME/.claude/skills/nvim-e2e-workflow/SKILL.md"
ln -sf "$PWD/.github/agents/codediff-developer.agent.md" "$HOME/.claude/skills/codediff-developer/SKILL.md"
```
