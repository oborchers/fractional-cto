---
description: "Stress-test a plan document using adversarial red-team/blue-team agents"
argument-hint: "<path to plan file>"
---

Stress-test a planning document using the red-team/blue-team adversarial review pattern from the `stress-test` plugin.

Follow this process:

## Step 1: Plan File

If no plan file was provided as an argument, use `AskUserQuestion` to ask the user which file to stress-test:
- Ask them to provide the path to their plan document

Read the plan file to confirm it exists and understand its contents. Identify the plan's type (implementation plan, business plan, design plan, etc.) and the surrounding context (codebase, supporting documents, config files).

## Step 2: Context Assessment

Briefly assess the surrounding context available for grounding:
- Is there a codebase the plan references?
- Are there supporting documents, configs, or data files?
- What systems or APIs does the plan depend on?

Present this assessment to the user so they understand what the agents will work with.

## Step 3: Tool Scope

Use `AskUserQuestion` to ask the user what tool scope the blue team should have:

- **Local artifacts only** -- Read, Grep, Glob. The blue team can only reference the plan and local files. Fastest and safest. Best when surrounding context is rich (e.g., a full codebase).
- **+ Web research** -- Adds WebSearch and WebFetch. The blue team can look up external documentation, API specs, standards, and benchmarks. Good when the plan references external systems or standards.
- **+ System verification** -- Adds Bash and MCP tools. The blue team can query live APIs, check configurations, run diagnostic commands. Most powerful but requires the systems to be accessible.

Note: The red team always uses local artifacts only, regardless of this choice.

## Step 4: Permissions Check

Determine the output file path: same directory as the plan file, with `-stress-test.md` suffix (e.g., `plan.md` -> `plan-stress-test.md`). Resolve to an absolute path.

Check if the required permissions are granted in `.claude/settings.local.json`:

Required permissions:
- `"Edit(//[absolute-output-dir]/**)"` -- for the blue team to write the QA report
- `"Write(//[absolute-output-dir]/**)"` -- for the blue team to create the QA report
- If **+ Web research** scope: also check `"WebSearch"` and `"WebFetch"`

If ANY are missing:

  Inform the user which permissions are needed and why.

  Use `AskUserQuestion` to ask:
  - **Add permissions and restart** -- add missing permissions, then instruct user to restart
  - **Skip, I'll approve manually** -- proceed without modification

  If the user approves, read the existing `.claude/settings.local.json` (if any), merge missing permissions into `permissions.allow`, write the file, and instruct the user to restart.

  **Stop here** if permissions were added -- they take effect after restart.

## Step 5: Red Team

Spawn a `red-team` subagent. Provide it with:
- The path to the plan file
- A description of the surrounding context (what directories to explore, what the codebase contains, what supporting documents exist)

The red team reads the plan and artifacts, then returns a set of what-if questions organized by category.

When the red team completes, briefly present the question count and categories to the user. Do NOT present all questions in full -- the blue team report will contain them.

## Step 6: Blue Team

Spawn a `blue-team` subagent. Provide it with:
- The path to the plan file
- The full text of the red team's what-if questions (from the agent result)
- The output file path for the QA report
- The tool scope selected by the user in Step 3
- Today's date for the report header

The blue team reads the plan, artifacts, and what-if questions, then writes a QA report with verdicts for each question.

## Step 7: Results

When the blue team completes, read the QA report and present a summary to the user:
- Total questions evaluated
- Verdict breakdown (ANSWERED, PARTIALLY ADDRESSED, NOT COVERED, UNCERTAIN)
- List of NOT COVERED and UNCERTAIN items (these are the action items)

Use `AskUserQuestion` to ask the user:
- **Done** -- review is complete
- **Re-run after plan update** -- user will update the plan and wants to stress-test again
- **Discuss a specific gap** -- dive deeper into a particular finding

## Mandatory Use of AskUserQuestion

**Every user decision point MUST use the `AskUserQuestion` tool.** Never ask for decisions via inline text.

### Main Conversation Owns All User Interaction

`AskUserQuestion` must be called from this command (the main conversation), never from subagents. The red-team and blue-team agents handle analysis and write output -- this command handles all user interaction.
