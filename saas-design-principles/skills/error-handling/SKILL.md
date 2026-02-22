---
name: error-handling
description: This skill should be used when the user is building or reviewing error states, validation errors, permission errors (403), session expiry warnings, offline handling, concurrent edit conflicts, rate limiting, or server error (500) recovery flows. Covers the full taxonomy of SaaS failure modes and graceful degradation patterns.
version: 1.0.0
---

# The Full Taxonomy of What Goes Wrong

Error handling in SaaS extends far beyond "something went wrong" modals. A production-ready application must account for every failure mode with specific, actionable responses.

## Validation Errors

Surface inline, below the specific field, with red borders and actionable text.

**Never use toasts for validation errors.** Toasts stack, auto-dismiss before reading, and force users to hunt for the relevant field.

## Permission Errors (403)

Must explain what the user can't do, why, and what they can do about it.

| Bad | Good |
|-----|------|
| "Access denied" | "Only workspace admins can manage billing. Request access from @admin-name" |
| "Contact your administrator" | Show who has the required permission + a "Request Access" button |
| "Forbidden" | Suggest alternative actions the user CAN take |

**Three response options to offer:**
1. Show who has the required permission
2. Provide a "Request Access" button
3. Suggest alternative actions

## Session Expiry

Special care required. Jared Spool documented a case where a user completed a purchase, opened another tab, returned to find "Your session expired" — with no clarity on whether the purchase completed.

**The principle:** Always clearly communicate what was saved and what was lost.

**Requirements:**
- Show a warning modal with a countdown timer BEFORE expiration
- Include both "Continue Session" and "Log Out" buttons
- After auto-logout, display an inline notification on the login page explaining what happened
- Never leave ambiguity about what data was preserved

For additional session management guidance (adaptive MFA, auth flows), see the `authentication` skill.

## Concurrent Edit Conflicts

The deepest technical-UX intersection. Figma's approach: model documents as property-level maps.

**Resolution strategy:**
- Two users changing different properties on the same object = no conflict
- Two users changing the same property = last-write-wins
- This is simpler than Operational Transformation or full CRDTs, and sufficient for most SaaS products

**UI requirements:**
- Show clear indicators of who else is editing
- Use real-time subscriptions for basic conflict detection
- Pair with property-level resolution

## Network Errors

Graceful degradation is mandatory.

**Rules:**
- Show a clear offline banner when connectivity is lost
- Queue actions locally and sync when connectivity returns
- For rate limiting (429), display a countdown or estimated wait time before retry
- For server errors (500), show a friendly message with a retry button
- Never expose stack traces or technical error codes to end users

## Examples

Working implementations in `examples/`:
- **`examples/error-states.md`** — Permission denied (403), offline banner with action queue, server error (500) with retry, and rate limiting (429)

## Review Checklist

When reviewing or building error handling:

- [ ] Validation errors are inline, below the field, with red borders and actionable text
- [ ] No validation errors delivered via toasts
- [ ] Permission errors explain what, why, and what to do next
- [ ] No generic "Contact your administrator" messages
- [ ] Session expiry shows a countdown warning modal before logout
- [ ] After auto-logout, login page explains what happened and what was saved
- [ ] Concurrent editing shows who else is active
- [ ] Edit conflicts resolved at property level, not document level
- [ ] Offline state shows a clear banner
- [ ] Actions queue locally when offline and sync on reconnection
- [ ] Server errors show friendly messages with retry buttons
- [ ] No stack traces or error codes exposed to end users
