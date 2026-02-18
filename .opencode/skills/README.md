# Bluefin Egg Skills

This directory contains **agent-agnostic skills** for AI-assisted development on the Bluefin Egg project.

## What are Skills?

Skills are reusable, proven techniques and workflows encoded as documentation. They serve as institutional memory - capturing what works and preventing repeated mistakes.

**Key characteristic:** Skills are universal markdown documents, not tool-specific code. Any AI agent (or human) can read and apply them.

## For AI Agents

These skills are written in standard markdown with YAML frontmatter. Skills define:

- **When to use:** Triggering conditions in the `description` field
- **Core principles:** What this skill teaches
- **Workflows:** Step-by-step processes with flowcharts
- **Common mistakes:** What goes wrong and how to fix it
- **Integration:** How this skill relates to others

### How to Use Skills

**OpenCode:** Use the `Skill` tool to load skills by name (e.g., `brainstorming`, `writing-plans`)

**Other agents:** Read markdown files directly. The YAML frontmatter provides metadata, the markdown body provides the content.

### Skill Discovery

To find relevant skills:
1. Read the `description` field in YAML frontmatter - it starts with "Use when..."
2. Match your current task against those triggers
3. Load and follow the full skill content

**Critical rule:** Even a 1% chance a skill applies means you should load it. See `using-superpowers/SKILL.md` for the complete skill usage workflow.

## For Humans

Skills represent project knowledge - conventions, patterns, and workflows that work. Reading skills is valuable for:

- Understanding project standards
- Learning proven techniques
- Contributing improvements
- Onboarding to the project

Start with:
- `using-superpowers/SKILL.md` - How the skill system works
- `brainstorming/SKILL.md` - Starting creative work
- `writing-plans/SKILL.md` - Planning multi-step work
- `local-e2e-testing/SKILL.md` - Building and testing locally

## For Tool Developers

Skills use a simple, parseable format:

### File Structure

```
skills/
  skill-name/
    SKILL.md              # Main content (required)
    supporting-file.*     # Optional supporting files
```

### SKILL.md Format

```yaml
---
name: skill-name-with-hyphens
description: Use when [specific triggering conditions and symptoms]
---

# Skill Name

## Overview
What is this? Core principle in 1-2 sentences.

## [Additional sections...]
```

### Frontmatter

- Only two fields: `name` and `description`
- Max 1024 characters total
- `name`: Letters, numbers, hyphens only (no spaces, parentheses)
- `description`: Third-person, starts with "Use when...", focuses on triggering conditions

### Content

- Standard markdown (CommonMark)
- Optional Graphviz diagrams in code blocks with `dot` language tag
- Cross-references to other skills by name only (e.g., "use superpowers:brainstorming")

### Integration Guide

To add skill support to your agent system:

1. **Discovery:** Scan `*.md` files in this directory recursively
2. **Parsing:** Extract YAML frontmatter (name, description)
3. **Matching:** Match task context against description triggers
4. **Loading:** Present full markdown content to agent
5. **Rendering:** Render markdown (including optional Graphviz diagrams)

Skills are designed to be:
- **Searchable:** Rich keywords in descriptions
- **Self-contained:** Everything needed is in the skill or linked files
- **Composable:** Skills reference other skills by name
- **Testable:** Skills can be validated with agent tests (see `writing-skills/SKILL.md`)

## Directory Name

Despite the `.opencode/` directory name, **these skills are not OpenCode-specific**. The prefix is a convention for open AI tooling, not a tool requirement.

Skills are standard markdown + YAML, making them universally accessible to any agent system or human reader.

## Contributing

To add or update skills, follow the `writing-skills/SKILL.md` workflow:

1. Write test scenarios showing what behavior needs improving
2. Run baseline (agent fails without skill)
3. Write skill addressing those failures
4. Verify agent now complies
5. Close loopholes through iteration

See `writing-skills/SKILL.md` for the complete TDD-based skill creation process.

## Skill Categories

| Category | Examples | Use When |
|----------|----------|----------|
| **Process** | brainstorming, writing-plans, systematic-debugging | Starting work, need structured approach |
| **Quality** | test-driven-development, verification-before-completion | Ensuring work is correct and complete |
| **Workflow** | subagent-driven-development, using-git-worktrees | Managing complex multi-step work |
| **BuildStream** | adding-a-package, debugging-bst-build-failures | Working with the build system |
| **Packaging** | packaging-go-projects, packaging-zig-projects | Adding new software to the image |

## Questions?

For questions about:
- **Using skills:** See `using-superpowers/SKILL.md`
- **Creating skills:** See `writing-skills/SKILL.md`
- **Project context:** See `AGENTS.md` in repository root
- **Build system:** See `local-e2e-testing/SKILL.md`
