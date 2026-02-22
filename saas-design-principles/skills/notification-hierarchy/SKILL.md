---
name: notification-hierarchy
description: This skill should be used when the user is building or reviewing toast notifications, banners, modal dialogs, inline messages, snackbars, or alert systems. Covers the four-tier notification hierarchy, feedback patterns, success and error messaging, and alert fatigue prevention.
version: 1.0.0
---

# Match Message Urgency to Interruption Level

The notification hierarchy is one of the most commonly misapplied patterns in SaaS. IBM Carbon's framework provides the clearest decision guide. Each notification type has a specific purpose — misusing them causes alert fatigue and lowers productivity.

## The Hierarchy

From lowest to highest disruption:

### 1. Inline Messages (Lowest Disruption)

Contextual feedback within a specific UI section. Persists until resolved.

**Use for:** Validation errors, field-level guidance, status indicators.

### 2. Toasts

Brief, non-blocking confirmations of completed actions.

**Use for:** "Item saved," "Email sent," "Record updated."

**Rules:**
- Auto-dismiss after **3 seconds** if they contain no actions
- Persist if they include an undo button or other action
- Never stack more than **4 toasts** simultaneously

### 3. Banners

System-level or product-level notifications not tied to a specific task.

**Use for:** Maintenance windows, plan limits, degraded service, required actions.

**Rules:**
- Persist until dismissed
- Sit at the top of the screen
- Not tied to a specific user action

### 4. Modals (Highest Disruption)

Block all other interaction. The nuclear option.

**Use exclusively for:**
- Confirming destructive actions (delete, cancel subscription)
- Acknowledging session expiry
- Completing multi-step flows requiring focused attention

**Never use modals for:** Informational messages, success confirmations, or anything that could be a toast or banner.

## Decision Guide

| Scenario | Notification Type |
|----------|------------------|
| Field has a validation error | Inline message |
| User saved a record successfully | Toast (auto-dismiss 3s) |
| User deleted something (with undo) | Toast (persist until dismissed) |
| System maintenance in 30 minutes | Banner |
| User's plan is approaching its limit | Banner |
| User is about to delete their account | Modal |
| Session is about to expire | Modal (with countdown) |

## Color Coding

Standardized across every major design system:

| Color | Meaning | Icon Required |
|-------|---------|---------------|
| **Blue** | Informational | Yes |
| **Green** | Success | Yes |
| **Yellow** | Warning | Yes |
| **Red** | Error/Danger | Yes |

**Never rely on color alone for meaning.** Each status must also have a unique icon — this is both an accessibility requirement and a usability one.

## Alert Fatigue

IBM Carbon explicitly warns: "Frequent distractions lower productivity and can lead to alert fatigue."

**The principle:** If uncertain whether a notification is necessary, it probably isn't. Confine each notification to the portion of the interface it's relevant to.

## Examples

Working implementations in `examples/`:
- **`examples/toast-system.md`** — Toast manager with 4-toast limit, auto-dismiss, undo actions, and color/icon system in React

## Review Checklist

When reviewing or building notification systems:

- [ ] Validation errors use inline messages, never toasts
- [ ] Success confirmations use toasts with 3-second auto-dismiss
- [ ] Toasts with actions (undo, retry) persist until dismissed
- [ ] No more than 4 toasts stacked simultaneously
- [ ] System-level messages use banners at the top of the screen
- [ ] Modals reserved exclusively for destructive or critical actions
- [ ] Each notification has both a color AND a unique icon
- [ ] No unnecessary notifications — when in doubt, leave it out
- [ ] Notification type matches the interruption level of the message
