---
name: progressive-disclosure
description: This skill should be used when the user is building or reviewing onboarding flows, empty states, progress checklists, signup forms, product tours, or first-run experiences. Covers progressive disclosure of features, time-to-value optimization, the Zeigarnik effect, and feature revelation strategy.
version: 1.0.0
---

# Reveal Complexity Progressively

Nielsen defined progressive disclosure in 2006: defer advanced or rarely used features to a secondary screen, making applications easier to learn and less error-prone. This improves learnability, efficiency of use, and error rate.

## The Two-Level Limit

**Never go beyond two levels of disclosure.** Usability drops rapidly at three or more levels because users get lost navigating between them. If a settings panel requires three levels of nesting, the design needs simplification, not more progressive disclosure.

Linear's philosophy: "Simple first, then powerful."
Intercom's principle: "Simple and opinionated by default, progressively reveal power and flexibility."

## Onboarding

Onboarding is progressive disclosure applied to time. The data is stark: **40–60% of signup users never return** after their first experience. Every extra minute in time-to-value lowers conversion by approximately 3%.

### Signup

- Limit to **3 fields maximum** — every extra field costs roughly 7% conversion
- Frame additional questions as personalization, not interrogation
- Example: Notion asks "What will you use this for?" to customize the experience

### Product Tours

- **3–5 steps maximum**
- Always include a skip button
- Focus on one critical action rather than explaining every feature
- Users are 4.5x more likely to complete a second tour if they complete the first one — make the first tour excellent and brief

### Checklists

Checklists work because of the **Zeigarnik effect** — the psychological need to complete unfinished tasks.

**Rules:**
- Start the progress bar at **20%, not 0%**
- Keep checklists to **3–5 items**
- Nest them directly in the product, not floating on top
- Tie items to real user actions that demonstrate value, not arbitrary feature exploration

## Empty States

Empty states are the most underrated onboarding surface. Notion fills its empty first-use state with educational content that doubles as a checklist.

**Every empty state needs three things:**
1. Context explaining why it is empty
2. A single clear call-to-action
3. Reassurance that nothing is broken

**Never show a blank screen with "No data yet."** An empty state should never feel empty or negative, even when things aren't working as expected (SAP Fiori).

## Review Checklist

When reviewing or building progressive disclosure:

- [ ] Advanced features deferred to secondary screens
- [ ] No more than two levels of disclosure anywhere
- [ ] Signup limited to 3 fields maximum
- [ ] Product tour is 3–5 steps with a skip button
- [ ] Checklists have 3–5 items and start at 20% progress
- [ ] Checklist items tied to value-demonstrating actions
- [ ] Every empty state has context, a CTA, and reassurance
- [ ] No blank "No data yet" screens anywhere
- [ ] First-run experience focuses on one critical action
