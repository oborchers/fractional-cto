---
name: structured-brainstorming
description: "This skill should be used when the user needs to brainstorm, explore a problem space, think through design decisions, compare approaches, evaluate trade-offs, is stuck on an approach, or wants to explore multiple solutions. Trigger phrases include 'how should I approach this', 'what are my options', 'help me think through this', 'help me decide between X and Y', 'what are the pros and cons', 'weigh the trade-offs', 'compare these approaches', and 'I'm stuck'. Covers 8 bias-counteracting methods with user-gated parallel subagent exploration for deep dives."
version: 1.1.0
---

# Structured Brainstorming

Structured brainstorming applies specific thinking methods that counteract LLM reasoning biases during problem exploration. Without deliberate structure, LLM responses gravitate toward the most probable answer, skip genuine alternative exploration, and converge prematurely on conventional solutions.

This skill provides 8 methods selected because they fight known LLM failure modes. The `/brainstorm` command drives an interactive flow where the user decides when to dispatch parallel `brainstorm-explorer` subagents for deep multi-angle exploration.

## Why Structure Matters for LLMs

LLMs have specific reasoning biases that structured methods counteract:

| Bias | What Happens | Counteracting Method |
|------|-------------|----------------------|
| Premature convergence | Jumps to "the answer" without exploring alternatives | **Diverge-then-Converge** |
| Sycophancy | Leans toward what the user seems to want | **Inversion / Pre-Mortem** |
| Mode collapse | "Different" ideas are variations of the same idea | **Constraint Manipulation** |
| Shallow exploration | Stays in the obvious solution neighborhood | **First Principles Decomposition** |
| Authority bias | Defaults to best practices / conventional wisdom | **Assumption Surfacing** |
| Single perspective | Thinks only as "helpful assistant" | **Perspective Forcing** |
| Local search | Explores only adjacent solutions | **Analogy Search** |
| Vague decomposition | Breaks problems into overlapping, incomplete parts | **MECE Decomposition** |

## The 8 Methods

| # | Method | Core Question | Best For |
|---|--------|--------------|----------|
| 1 | First Principles Decomposition | "What is actually true here vs. assumed?" | Challenging conventional approaches |
| 2 | Inversion / Pre-Mortem | "What would make this fail spectacularly?" | Risk assessment, robustness |
| 3 | Constraint Manipulation | "What if I add/remove/reverse a constraint?" | Breaking out of local optima |
| 4 | Perspective Forcing | "How does the [user/operator/critic/...] see this?" | Blind spot detection |
| 5 | Analogy Search | "Where has a similar problem been solved?" | Novel approaches from other domains |
| 6 | MECE Decomposition | "What are the non-overlapping parts of this?" | Systematic coverage |
| 7 | Assumption Surfacing | "What am I taking for granted?" | Hidden constraint discovery |
| 8 | Diverge-then-Converge | "How many distinct options exist before I evaluate?" | Overcoming premature convergence |

For detailed method descriptions, step-by-step processes, and application prompts, consult the corresponding file in `references/`.

## Method Selection

Match problem type to recommended methods:

| Problem Type | Start With | Add If Needed |
|-------------|-----------|---------------|
| "How should I design X?" | First Principles, MECE | Perspective Forcing, Analogy |
| "I'm stuck on X" | Assumption Surfacing, Constraint Manipulation | Inversion, Analogy |
| "What could go wrong with X?" | Inversion / Pre-Mortem, Perspective Forcing | Assumption Surfacing |
| "What are my options for X?" | Diverge-then-Converge, MECE | Constraint Manipulation, Analogy |
| "Should I do X or Y?" | First Principles, Inversion | Perspective Forcing, Assumption Surfacing |
| "How do others solve X?" | Analogy Search, Perspective Forcing | First Principles |
| "How do I prioritize X?" | MECE Decomposition, Diverge-then-Converge | Perspective Forcing |

## Applying Methods

For focused problems where 2-3 methods suffice, apply methods directly without dispatching agents. Use the method selection table to pick methods, then apply each following its reference file. Spend enough depth per method to produce a concrete finding, not a platitude.

For complex, high-stakes, or multi-faceted problems, use the `/brainstorm` command to dispatch parallel `brainstorm-explorer` agents. Each agent applies its assigned methods with the same depth, using the reference files for the detailed step-by-step process.

## Parallel Exploration with Subagents

The `/brainstorm` command asks the user whether to dispatch parallel `brainstorm-explorer` subagents or rephrase the problem statement first. When the user chooses to dispatch, spawn agents in parallel using the Agent tool — each exploring the problem from a different angle simultaneously.

**Agent dispatch pattern:**
- Agent 1: First Principles + Assumption Surfacing (strip to fundamentals)
- Agent 2: Inversion / Pre-Mortem + Perspective Forcing (failure modes + stakeholders)
- Agent 3: Analogy Search + Constraint Manipulation (cross-domain + creative alternatives)
- Agent 4: MECE Decomposition + Diverge-then-Converge (systematic coverage)

Each agent receives: the problem statement, the assigned methods with their reference material, and instructions to explore deeply. Give agents access to the codebase (Read, Grep, Glob). If WebSearch is available, also grant it for cross-domain research in Analogy Search and Constraint Manipulation.

After all agents complete, synthesize: identify convergent themes, genuine disagreements, and surprising findings. Present a structured recommendation with the full exploration visible.

## Output Structure

Every brainstorming session produces:

1. **Problem restatement** -- confirm understanding before exploring
2. **Method application** -- labeled sections showing each method's findings
3. **Convergence** -- where methods agree, disagree, and surprise
4. **Recommendation** -- concrete next step(s) with explicit trade-offs
5. **Open questions** -- what remains uncertain and how to resolve it

## Reference Files

Detailed method descriptions, step-by-step processes, and application prompts:

- **`references/first-principles-decomposition.md`** -- Stripping assumptions, decomposing to fundamentals, rebuilding from ground truth
- **`references/inversion-and-pre-mortem.md`** -- Working backwards from failure, forcing pessimistic analysis
- **`references/constraint-manipulation.md`** -- Adding, removing, and reversing constraints to escape local optima
- **`references/perspective-forcing.md`** -- Stakeholder simulation and structured role-based thinking
- **`references/analogy-search.md`** -- Cross-domain pattern matching and analogical transfer
- **`references/mece-decomposition.md`** -- Non-overlapping, collectively exhaustive problem breakdowns
- **`references/assumption-surfacing.md`** -- Identifying and challenging hidden assumptions
- **`references/diverge-then-converge.md`** -- Separating idea generation from idea evaluation

## Example Files

Worked brainstorming sessions:

- **`examples/inline-brainstorm.md`** -- Event system design (5 methods applied, showing expected depth per method)
- **`examples/parallel-agent-exploration.md`** -- Auth system greenfield (4 subagents, full parallel exploration with user-gated dispatch)
