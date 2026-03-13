# markdown-compressor

Compress LLM agent instructions, CLAUDE.md files, ARCHITECTURE.md files, and code documentation to minimize token usage while preserving the information an LLM needs to operate correctly.

## The Problem

LLM-facing markdown accumulates bloat: verbose explanations, redundant examples, motivational filler, hedging language, implied-knowledge tutorials. Every extra token costs money and eats context window. There's no structured way to compress these files while ensuring critical information survives.

## Two Modes

| Mode | What Changes | Risk | Typical Reduction |
|------|-------------|------|-------------------|
| **Lossless** | Structure only — whitespace, formatting, redundant syntax | Zero | 20-40% |
| **Lossy** | Semantics — rewrite for density, remove filler, consolidate | Reviewed | 40-70% |

Lossless is always safe. Lossy uses a compressor-reviewer loop with user approval per section.

## Usage

### Command

```
/compress path/to/file.md              # Lossy mode (prompted)
/compress path/to/file.md --lossless   # Lossless mode
/compress path/to/file.md --auto       # Lossy, no per-section review
/compress path/to/file.md --lossless --auto  # Lossless, no review
```

### Flow

1. **Pre-analysis** — parses heading hierarchy, measures tokens per section, flags structural issues
2. **Section-by-section compression** — for each section:
   - `section-compressor` agent applies compression
   - `compression-reviewer` agent checks for information loss (lossy only)
   - User approves, skips, or edits via interactive selector — or auto-approves
   - Result is **written to file immediately** (incremental saves, crash-safe)
3. **Summary** — reports token reduction and sections modified

### Auto-Approve

Three ways to skip per-section review:

- **`--auto` flag** — skip review from the start
- **After section 1** — review one section to calibrate, then choose "Auto-approve remaining"
- In auto mode, the `compression-reviewer` agent still runs for lossy compression and automatically incorporates its fixes — it just doesn't gate on the user

### Automatic Skill Activation

The `markdown-compression` skill activates when Claude detects relevant work: "compress this file", "optimize tokens", "make this more concise", "shrink this markdown".

## What Gets Compressed

**Always safe to remove:** filler, restated information, hedging, verbose transitions, redundant illustrative examples, decorative markdown, HTML comments

**Never removed:** specific values/thresholds, behavioral rules (NEVER/ALWAYS), tool names and paths, decision logic, output formats, edge cases, YAML frontmatter, operational examples (copy-pasteable curl/CLI/config blocks)

## Plugin Components

| Component | File | Purpose |
|-----------|------|---------|
| Skill | `skills/markdown-compression/SKILL.md` | Core compression principles and techniques |
| References | `skills/markdown-compression/references/` | Detailed lossless and lossy technique catalogs |
| Examples | `skills/markdown-compression/examples/` | Before/after compression examples |
| Command | `commands/compress.md` | `/compress` slash command |
| Agents | `agents/section-compressor.md` | Compresses one section (aggressive) |
| | `agents/compression-reviewer.md` | Reviews compression for info loss (adversarial) |
| Hook | `hooks/hooks.json` | SessionStart awareness injection |

## Installation

```bash
# Test locally
claude --plugin-dir /path/to/markdown-compressor
```
