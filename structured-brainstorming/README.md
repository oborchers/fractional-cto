# structured-brainstorming

Structured thinking methods that counteract LLM reasoning biases during problem exploration. Gives Claude 8 specific methods — selected because they fight known failure modes like premature convergence, sycophancy, and mode collapse. For deep dives, spawns parallel subagents that explore the problem from different angles simultaneously.

## The Problem

Without deliberate structure, LLM responses gravitate toward the most probable answer, skip genuine alternative exploration, and converge prematurely on conventional solutions. This plugin provides methods that force deeper, more diverse thinking.

## The 8 Methods

| Method | Fights | Core Question |
|--------|--------|--------------|
| First Principles Decomposition | Shallow exploration | "What is actually true vs. assumed?" |
| Inversion / Pre-Mortem | Sycophancy | "What would make this fail?" |
| Constraint Manipulation | Mode collapse | "What if I change a constraint?" |
| Perspective Forcing | Single perspective | "How does each stakeholder see this?" |
| Analogy Search | Local search | "Where was this solved in another domain?" |
| MECE Decomposition | Vague decomposition | "What are the non-overlapping parts?" |
| Assumption Surfacing | Authority bias | "What am I taking for granted?" |
| Diverge-then-Converge | Premature convergence | "How many options exist before I evaluate?" |

## Usage

### Automatic Skill Activation

The skill activates when Claude detects relevant work: "how should I approach this?", "I'm stuck on X", "what are my options?", "help me think through this."

### Command

```
/brainstorm "How should we design the auth system for our SaaS product?"
```

### Parallel Subagent Exploration

For high-stakes or ambiguous problems, Claude spawns `brainstorm-explorer` subagents in parallel — each applying different methods to the same problem. Agents can search the codebase and the web for cross-domain analogies.

## Plugin Components

| Component | File | Purpose |
|-----------|------|---------|
| Skill | `skills/structured-brainstorming/SKILL.md` | Core methods, method selection, subagent dispatch |
| References | `skills/structured-brainstorming/references/` | Detailed per-method guides (8 files) |
| Examples | `skills/structured-brainstorming/examples/` | Worked sessions: inline and parallel agent (2 files) |
| Command | `commands/brainstorm.md` | `/brainstorm` slash command |
| Agent | `agents/brainstorm-explorer.md` | Subagent for parallel exploration |
| Hook | `hooks/hooks.json` | SessionStart awareness injection |

## Installation

```bash
# Test locally
claude --plugin-dir /path/to/structured-brainstorming
```
