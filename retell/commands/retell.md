---
description: Transform a Claude Code conversation into a polished blog post through an interactive 5-stage pipeline
argument-hint: "[conversation-uuid or path]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "Agent", "AskUserQuestion", "WebFetch"]
---

Transform a Claude Code conversation transcript into a polished, first-person blog post. This command orchestrates a 5-stage interactive pipeline with editorial gates at every stage.

## Pipeline Overview

```
Stage 1: PARSE    (script, 0 tokens)   → events.json + manifest.json
Stage 2: TRIAGE   (Sonnet subagent)    → angles, recommendation, context questions
  ← Author reviews, picks angle, injects context
Stage 3: OUTLINE  (Sonnet subagent)    → sections, beats, quotes, word counts
  ← Author reviews, reorders, cuts, adjusts
Stage 4: DRAFT    (you, Opus)          → full blog post
  ← Author reviews, gives feedback
Stage 5: POLISH   (you, Opus)          → revised post (repeat until satisfied)
```

## Execution Process

### If no argument provided — Discovery Mode

1. Run the preview script to show recent conversations:
   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/preview-conversations.py 15
   ```
2. Present the results to the user
3. Ask which conversation to use (by UUID prefix) using `AskUserQuestion`
4. Continue to Stage 1 with the chosen UUID

### Stage 1: Parse

Run the deterministic parser — zero LLM tokens:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/parse-conversation.py <identifier> --output-dir /tmp/retell-<uuid-prefix>
```

Read the manifest to understand the conversation:
- How many events, sessions, subagents
- Token budget estimate
- Any PII warnings from the parser

Present a brief summary to the user:
- "Parsed 82 events across 2 sessions. 4 subagents available. ~87K signal tokens estimated."
- If PII warnings exist, show them and ask how to proceed

### Between Stage 1 and Stage 2: Reference Documents

After presenting the parse summary, ask the user:

"Do you have any reference documents that provide context beyond the conversation? These could be research notes, architecture docs, design specs, prior drafts, or any markdown file with background material. Provide file paths, or say 'none' to continue."

If the user provides paths:
1. Verify each file exists and is readable using `Read`
2. For each document, generate a brief summary:
   - File name and path
   - Approximate length (word count)
   - Key headings (first 2 levels)
   - A 2-3 sentence synopsis of the content
3. Present the summaries back to the user for confirmation
4. If total reference doc size exceeds ~50K tokens (~200K characters), warn the user and suggest prioritizing the most relevant documents
5. Store both the full paths and the summaries for downstream stages

**Carry forward:** Reference document paths (full list) and reference document summaries (condensed).

### Stage 2: Triage

Use the `triage-analyst` agent (Sonnet). Provide it with:
- The path to `events.json` and `manifest.json`
- Reference document summaries (if any were provided)
- Instructions to read the files and produce its structured assessment

**Present the triage results to the user interactively:**

1. Show the blog-worthiness assessment
2. Present the **recommendation prominently** — the recommended angle with its full reasoning
3. List the other angles as alternatives
4. Show the timeline of key beats
5. Show context questions the agent surfaced
6. Show red flags and PII warnings if any

**Ask the user to pick an angle using `AskUserQuestion`:**
- Accept the recommended angle (fast path)
- Pick a different angle
- Combine elements from multiple angles
- Say "skip" to stop the pipeline

**After the user picks an angle, ask these editorial questions.** Use `AskUserQuestion` for questions with fixed options (Language, Length, Thinking blocks). Open-ended questions (Backstory, Audience, Style reference, Public links) may use free-text prompts.

1. **Backstory**: "Is there anything about this story the conversation can't capture? What happened before this session, why it matters to you, motivation, context the transcript doesn't contain?" — Open-ended, free-form. This is the most important question. The best blog material often lives outside the JSONL.

2. **Language**: "Should the blog post be written in English or German?" — Default is English. This affects all text output from this point forward: section headings in the outline, all prose in the draft, and all revisions in polish. Quotes from the conversation will be translated into the output language so the entire post reads consistently. If a style reference is provided in a different language than the output language, the style patterns (rhythm, sentence structure, tone) will be extracted and applied to the target language.

3. **Audience**: "Who's reading this?" — e.g., "other Claude Code users", "non-technical founders", "developers building on LLMs". Shapes jargon level and what to explain vs. assume.

4. **Length**: "How long should the post be?" — Short (800-1,200 words), Medium (1,800-2,500 words, recommended), or Long (3,000+ words). Overrides the triage's estimate.

5. **Thinking blocks**: "Include behind-the-scenes AI reasoning, or keep it to the visible exchange?" — Including thinking blocks adds depth ("Behind the scenes, Claude was weighing...") but not every post benefits from it.

6. **Style reference** (optional): "Is there a blog post whose writing style you'd like to match? Provide a URL." — If provided, use WebFetch to read the reference post before drafting. Analyze its voice, paragraph rhythm, sentence length, use of headers, code blocks, quotes, and humor. The draft stage should match these stylistic patterns while keeping the content original. If the style reference is in a different language than the configured output language, extract the structural and tonal patterns and apply them to the target language; do not translate the reference post.

7. **Public links** (optional): "Any public URLs to reference in the post? (GitHub repo, project page, live demo, etc.)" — If the user is building in public, these links should be woven naturally into the post where relevant (e.g., "The full plugin is on GitHub" with a link, or "You can try it yourself" with a repo URL). Don't force every link in — only include where they fit the narrative.

Also present the triage's context questions and let the user answer any they want — these are optional but can unlock the best material.

**Carry forward:** The chosen angle, all author context and backstory, output language, audience, length target, thinking block policy, style reference analysis, public links, reference document paths and summaries, and any editorial notes.

### Stage 3: Outline

If the chosen angle needs subagent content, first parse those subagents:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/parse-conversation.py <identifier> --output-dir /tmp/retell-<uuid-prefix> --include-subagents
```

Use the `outline-architect` agent (Sonnet). Provide it with:
- The chosen angle (title, pitch, tone)
- All author context and backstory collected so far
- Reference document paths (for full reading by the agent)
- Output language (English or German)
- Target word count from the user's length preference
- Thinking block policy (include or exclude)
- Target audience
- Path to events.json (now with subagent content if needed)

**Present the outline to the user interactively:**

1. Show the proposed sections with headings and beat summaries
2. Show key quotes that will be used (marked as cleaned where applicable)
3. Show word count estimates per section and total
4. Show open questions the agent surfaced

**Ask the user to decide using `AskUserQuestion`:**
- Approve the outline as-is
- Reorder sections
- Change treatment types (quote → summarize, etc.)
- Cut sections or beats
- Answer open questions
- Add more author context
- Adjust word count targets

**Carry forward:** The approved outline with all editorial decisions.

### Stage 4: Draft

**Write the blog post yourself (Opus).** Do NOT delegate this to a subagent — voice quality matters here.

Using the approved outline:
1. Follow the section order exactly
2. Use the `treatment` field: "quote" = use exact words, "summarize" = paraphrase, "montage" = compress into flowing prose
3. Match the specified tone, calibrated for the target audience
4. Write in **first-person voice** — "I asked Claude to...", "I rejected the monochrome direction..."
5. Target the user's chosen word count (short/medium/long)
6. Write the entire post in the configured output language. If the output language is German, use natural German prose with first-person voice ("Ich fragte Claude...", "Ich verwarf die erste Richtung, weil..."). Translate all conversation quotes into the output language, preserving the speaker's tone and emotional register. Do not translate English idioms literally; use idiomatic equivalents. Technical terms that are conventionally used in English in the target language's tech community (e.g., "Pull Request", "Deployment") may stay in English. If a style reference was provided in a different language, apply its structural patterns (paragraph length, header frequency, humor level) to the output language without translating phrases from the reference.
7. If thinking blocks are included, weave them as "behind the scenes" narrative — never quote thinking blocks directly, use them to inform the voice ("Behind the scenes, Claude was weighing...")
8. If a style reference was provided, match its voice patterns: paragraph rhythm, sentence length, use of headers/subheaders, code block frequency, conversational vs. formal register, humor level. The content is original — the style is borrowed.
9. If public links were provided, weave them naturally where they fit the narrative. Don't dump all links at the end — place them at the moment they become relevant. A GitHub repo link fits when the artifact is first named; a demo link fits at the closing.
10. If reference documents were provided, draw on their content where it enriches the narrative. Use them to add depth, accuracy, or context that the conversation alone doesn't provide. Cite specific insights or data points naturally; never dump reference material wholesale. The conversation remains the spine of the story; reference docs are supplementary texture.
11. Do not invent facts; everything must come from the outline's content, author context, and reference documents
12. **Never use em dashes, en dashes, or hyphens as punctuation.** They are a dead giveaway of AI-generated text. Use commas, semicolons, colons, parentheses, or split into separate sentences instead. Hyphens in compound words (e.g., "real-time") are fine.

**Ask the user where to save the blog post** before writing:
- Default location: `~/Desktop/blogpost-<uuid-prefix>-<date>.md`
- Offer alternatives: current working directory, custom path
- Use AskUserQuestion to confirm the output path

**Write the draft to the chosen location.**

**After writing, suggest hero image ideas** — 3-5 short, concrete search terms the author can drop into a stock image search bar (Unsplash, Pexels, Shutterstock, etc.). Each term should be thematically tied to the post's central metaphor or subject, not generic. For example, a post about recursive tool-building might suggest: `"mirror reflecting mirror"`, `"blueprint of a blueprint"`, `"ouroboros snake"`, `"nesting dolls craftsmanship"`, `"feedback loop diagram"`. Avoid clichés like "person typing on laptop" or "abstract technology background."

**Present the draft and image suggestions, then ask for feedback using `AskUserQuestion`** (e.g., Approve / Request changes / Done).

### Stage 5: Polish

This is a revision loop. The user reads the draft and provides feedback:
- "Opening is too slow"
- "Cut paragraph 3"
- "The rejection scene needs more punch"
- "Add a transition between sections 2 and 3"

Revise the post based on feedback. Update the file in place. Repeat until the user is satisfied or says "done."

**On every revision pass**, scan for and eliminate any em dashes, en dashes, or hyphens used as punctuation. Rephrase those sentences using commas, semicolons, colons, parentheses, or by splitting into separate sentences. Maintain the configured output language consistently throughout. If the post is in German, ensure no English fragments have crept in (except for technical terms that are conventionally used in English, like "Pull Request" or "Deployment Pipeline").

## Mandatory Use of AskUserQuestion

**Every user decision point MUST use the `AskUserQuestion` tool.** Never ask for decisions via inline text like "Approve?" or listing options in prose. The interactive selector UI provides a consistent, navigable experience.

This applies to ALL decision points with fixed options, including but not limited to:
- Discovery mode: which conversation to use
- PII warnings: how to proceed
- Reference documents: whether the user has any (Yes/No)
- Angle selection: accept recommendation, pick different, combine, or skip
- Editorial questions with fixed options: Language (English/German), Length (Short/Medium/Long), Thinking blocks (Include/Exclude)
- Outline approval: approve, reorder, cut, answer questions, etc.
- Output path confirmation
- Draft review: approve, request changes, or done
- Polish loop: approve, request changes, or done

Open-ended questions (backstory, audience description, revision feedback details) may use free-text prompts, but the initial decision gate for each stage must always use `AskUserQuestion`.

## Important Rules

- **Every stage is a stopping point.** If triage says "not blog-worthy," stop. If the user says "skip," stop. Don't push forward without explicit go-ahead.
- **Never fabricate quotes.** Clean typos and merge fragments, but never invent words the user or Claude didn't say.
- **First-person voice is non-negotiable.** Every blog post is written from the author's perspective.
- **Author context travels forward.** Anything the user provides at any gate must be carried to all subsequent stages.
- **One conversation at a time.** Never parse or reference other conversation files. If the author wants backstory from other sessions, they inject it as free-form text.
- **Show your work at gates.** Don't silently move between stages. Always present results and get explicit approval before proceeding.
