---
description: "Brainstorm solutions for a problem using structured thinking methods that counteract LLM reasoning biases"
argument-hint: "<problem statement>"
---

Apply structured brainstorming to the given problem using the `structured-brainstorming` skill.

Follow this process:

1. **Restate the problem** to confirm understanding. If no problem statement was provided as an argument, ask the user to describe the problem.

2. **Select methods** from the method selection table in the skill based on the problem type. Apply each method with enough depth to produce a concrete finding.

3. **If the problem warrants deep exploration** (ambiguous, high-stakes, greenfield, touches multiple systems), spawn `brainstorm-explorer` subagents in parallel — each assigned different methods — then synthesize their findings.

4. **Deliver results** in the standard output structure:
   - Problem restatement
   - Method application (labeled sections)
   - Convergence (agreement, disagreement, surprises)
   - Recommendation with trade-offs
   - Open questions

Consult the reference files in the structured-brainstorming skill for detailed method descriptions when applying each method.
