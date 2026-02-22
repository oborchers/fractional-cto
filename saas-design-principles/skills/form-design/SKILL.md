---
name: form-design
description: This skill should be used when the user is building or reviewing form validation, inline validation, auto-save vs explicit save patterns, form error messages, multi-step wizards, toggle switches, or input fields. Covers the "reward early, punish late" validation strategy and form UX best practices.
version: 1.0.0
---

# Forms Should Feel Like Conversations, Not Paperwork

Luke Wroblewski's landmark study established the baseline: inline validation produces a 22% increase in success rates, 42% faster completion, and 47% fewer eye fixations compared to submit-time validation.

## Validation Strategy: Reward Early, Punish Late

The optimal strategy is to validate after the user leaves a field (on blur), never while typing.

**Rules:**
- Show green checkmarks for correct inputs immediately on blur
- Delay error messages until the user has finished input and moved on
- Never show errors before the user has typed anything — premature validation causes longer completion times and higher error rates
- Premature validation forces constant switching between "completion mode" and "revision mode"

## Auto-Save vs. Explicit Save

Start with **explicit save as the default.** Never mix auto-save and explicit save in a single form.

| Control Type | Save Behavior |
|-------------|---------------|
| Toggle switches | Save immediately (imperative controls, like flipping a light switch) |
| Text inputs, radio buttons, checkboxes | Explicit save via button |

**If auto-save is used for text inputs:**
- Save on blur AND 3 seconds after the last keystroke
- Never auto-save data with financial, security, or privacy implications

**Counterintuitive finding:** Even with auto-save, keep the Save button. Users who have spent years learning that explicit saves are required experience genuine anxiety when the button disappears. The Save button provides psychological reassurance even when it does nothing the system wouldn't do automatically.

## Error Messages: The "Fix It" Test

Every error message must tell the user what went wrong AND how to fix it.

| Bad | Good |
|-----|------|
| "Invalid password" | "Insert a password of at least 8 characters" |
| "Error in field" | "Email must include an @ symbol" |
| "Validation failed" | "Phone number must be 10 digits, e.g. 555-123-4567" |

**Placement rules:**
- Place errors near the offending field, not just at the top of the form
- Use red borders and explanatory text
- The red-for-errors convention is universal — do not reinvent it

## Multi-Step Wizards

**When wizards work:**
- Steps are independent and sequential
- Each step has a clear, logical grouping

**When wizards fail:**
- Steps are interdependent — users need to alternate between steps
- In this case, a single scrollable page outperforms a wizard

**Wizard requirements:**
- Show progress indicators
- Allow backward navigation without data loss
- Break forms into logical groups

## Examples

Working implementations in `examples/`:
- **`examples/validation-reward-early-punish-late.md`** — Blur-based validation with success/error states in React, Vue, and Svelte
- **`examples/auto-save-vs-explicit-save.md`** — Settings form with immediate toggle saves and debounced text auto-save

## Review Checklist

When reviewing or building forms:

- [ ] Validation occurs on blur, not while typing
- [ ] Success states (green checkmarks) shown immediately for correct inputs
- [ ] Error messages tell users what went wrong AND how to fix it
- [ ] Errors placed near the offending field with red borders
- [ ] No premature validation before user has typed
- [ ] Auto-save and explicit save never mixed in the same form
- [ ] Toggle switches save immediately without a button
- [ ] Text inputs use explicit save (or auto-save with blur + 3s debounce)
- [ ] Save button present even with auto-save for psychological reassurance
- [ ] Multi-step wizards have progress indicators and backward navigation
- [ ] Interdependent steps use a single scrollable page instead of a wizard
