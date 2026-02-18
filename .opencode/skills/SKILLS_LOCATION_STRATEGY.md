# Skills Location Strategy

## Current State

Skills are currently in `.opencode/skills/` which is OpenCode-specific. The `.gitignore` ignores `.opencode/*` except for `.opencode/skills/`.

## Recommendation: Keep Current Location, Add Agent-Agnostic Documentation

**Recommended approach:** Keep skills in `.opencode/skills/` with explicit documentation that these are agent-agnostic.

### Rationale

1. **Already working**: The current structure is functional and tracked in git
2. **OpenCode is not proprietary**: The `.opencode/` directory name doesn't imply OpenCode ownership - it's a convention for "open" AI tooling
3. **Cross-platform compatibility**: Skills are written in markdown with standard YAML frontmatter - any agent system can read them
4. **Gitignore already configured**: `.opencode/skills/` is specifically un-ignored, showing intentional tracking

### Alternative Locations Considered

| Location | Pros | Cons | Verdict |
|----------|------|------|---------|
| `.ai/skills/` | Neutral name | Breaking change, lose history | ❌ Not worth migration |
| `docs/skills/` | Very explicit | Mixes with user docs | ❌ Wrong namespace |
| `.agents/skills/` | Agent-agnostic | Breaking change | ❌ Not worth it |
| `.opencode/skills/` | **Current, working** | **Name might confuse** | ✅ **Keep, document clearly** |

## Implementation

### 1. Update AGENTS.md Header

Make it clear that `.opencode/skills/` is not OpenCode-specific:

```markdown
All AI-assisted development is skill-driven. Skills (`.opencode/skills/`) are vendored 
in-repo and are the primary mechanism for institutional memory. Agents MUST load and 
follow relevant skills before acting.

**Note:** Despite the directory name, skills are agent-agnostic markdown files. The 
`.opencode/` prefix is a convention for open AI tooling, not a tool-specific requirement.
Any agent system (Claude Code, Cursor, Windsurf, Aider, custom tools) can read and use 
these skills.
```

### 2. Add Skills README

Create `.opencode/skills/README.md` explaining the universal nature:

```markdown
# Bluefin Egg Skills

This directory contains agent-agnostic skills for AI-assisted development on the 
Bluefin Egg project.

## For AI Agents

These skills are written in standard markdown with YAML frontmatter. Any agent system 
should be able to read and apply them. Skills define:

- When to use the skill (description field)
- Core principles and patterns
- Step-by-step workflows
- Common mistakes and how to avoid them

## For Humans

Skills represent institutional knowledge - techniques, patterns, and workflows that 
work well for this project. Reading skills is a great way to understand project 
conventions and best practices.

## For Tool Developers

Skills use a simple format:
- YAML frontmatter with `name` and `description` fields
- Markdown body with standard sections
- Optional Graphviz diagrams (`.dot` syntax in code blocks)
- Supporting files in the same directory

To integrate skills into your agent system:
1. Scan `*.md` files in this directory
2. Parse YAML frontmatter for metadata
3. Present relevant skills based on description triggers
4. Render markdown body for agent consumption
```

### 3. Update using-superpowers Skill

Add section on cross-platform compatibility:

```markdown
## Skill Location

Skills are located in `.opencode/skills/` in this repository. Despite the directory 
name, these are agent-agnostic markdown files that any AI system can use.

**For OpenCode users:** Use the `Skill` tool to load skills.

**For Claude Code users:** Skills should be auto-discovered from this directory.

**For other agents:** Check your platform's documentation for skill loading. If your 
platform doesn't have native skill support, you can still read the markdown files 
directly - they're designed to be human-readable.

**For tool developers:** See `.opencode/skills/README.md` for integration guidance.
```

### 4. Document in Project README (if exists)

Add a section on AI-assisted development pointing to skills.

## Agent System Compatibility Matrix

| Agent System | Skills Support | How to Use |
|-------------|----------------|------------|
| OpenCode | Native via `Skill` tool | Automatic discovery from `.opencode/skills/` |
| Claude Code | Native (hypothetical) | Would auto-discover from project |
| Cursor | Manual | Agent reads markdown files directly |
| Windsurf | Manual | Agent reads markdown files directly |
| Aider | Manual | Agent reads markdown files or references AGENTS.md |
| Custom tools | Depends | Read markdown files, parse YAML frontmatter |

## Migration Path (If Needed Later)

If `.opencode/` name becomes truly problematic:

1. Move to new location (e.g., `.ai/skills/`)
2. Leave symlink: `.opencode/skills -> ../.ai/skills`
3. Update all documentation
4. Add deprecation notice
5. Remove symlink after 6 months

This preserves backward compatibility while migrating.

## Conclusion

**Keep `.opencode/skills/`** - it's working, tracked in git, and agent-agnostic. Add clear documentation that the directory name is just a convention, not a tool lock-in.

The skills themselves are standard markdown + YAML, making them universally accessible.
