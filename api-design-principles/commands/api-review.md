---
description: Review the current code or API against API design principles — identifies violations and suggests improvements
disable-model-invocation: true
---

Review the code or API currently being worked on against the api-design-principles skills.

Follow this process:

1. Identify which API design areas are relevant to the current context (routes, errors, auth, pagination, etc.)
2. For each relevant area, invoke the corresponding api-design-principles skill
3. Evaluate the current code against each skill's review checklist
4. Report findings organized by principle, using this format for each:

**[Principle Name]**
- Violations found (with specific file/line references)
- What to fix and how
- Items that already comply

5. Provide a summary with:
   - Total violations count by severity (critical / important / suggestion)
   - Top 3 highest-impact improvements to make first

Focus on actionable, specific feedback. Reference the exact principle being violated.
