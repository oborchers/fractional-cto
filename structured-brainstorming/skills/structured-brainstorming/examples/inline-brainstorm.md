# Inline Brainstorm: Event System Design

## User Prompt

"We need to add an event system to our monolith. When a user signs up, we need to send a welcome email, create a Stripe customer, provision default settings, and track analytics. Right now these are all inline function calls in the signup handler and it's becoming a mess. How should I design this?"

## Method Application

### First Principles Decomposition

**What is actually required?**
- A user signs up (primary action — MUST succeed)
- Four secondary effects need to happen (email, Stripe, settings, analytics)
- Secondary effects should not block signup (user shouldn't wait for Stripe API)
- Secondary effects should eventually happen (email must arrive, Stripe customer must exist)
- Failed secondary effects should not lose data (retry capability)

**Fundamental truth:** This is a "primary action + reliable side effects" problem. The core pattern: separate the commit of the primary action from the dispatch of side effects, and make side effects retryable.

### MECE Decomposition

Breaking the solution space into non-overlapping categories along the "coupling" dimension:

| Approach | Primary-Secondary Coupling | Failure Isolation | Complexity |
|----------|--------------------------|-------------------|------------|
| **Inline calls** (current) | Tight — all in one transaction | None — one failure fails signup | Lowest |
| **Sync event dispatch** | Medium — same process, after commit | Partial — failures logged but not retried | Low |
| **Async queue** (SQS/Redis) | Loose — different process, after commit | Full — retry, DLQ, independent scaling | Medium |
| **Transactional outbox** | Loose + guaranteed — event written in same DB transaction | Full + guaranteed delivery | Higher |

**CE check:** Is anything missing? Could also do CDC (change data capture) from the database — structurally different from outbox because it watches DB changes rather than writing explicit events. Added for completeness but likely overkill for a monolith.

### Perspective Forcing

**End User:** "I just want to sign up and start using the product. I don't care about your architecture. Don't make me wait for your email provider."

**Operator:** "If Stripe is down at 3 AM, I want signup to still work. I need to see which events failed, retry them, and know when the backlog clears. Don't make me SSH into a box to check."

**Critic:** "An event bus in a monolith sounds like premature abstraction. You have ONE event type. Are you sure you need a queue, consumer, retry logic, and dead-letter handling for 'user signed up'?"

**Business:** "Signup is the highest-value moment. Anything that adds failure modes to signup needs to be justified. But losing a Stripe customer creation means lost revenue."

### Inversion / Pre-Mortem

"It's 3 months from now and the event system is a problem. What went wrong?"

- **Scenario 1:** We built an async queue but events get lost silently because we didn't implement dead-letter monitoring. Users sign up but never get Stripe customers. Revenue impact not detected for weeks.
- **Scenario 2:** We went with the transactional outbox but the polling consumer adds 15% load to the database. At peak signup, DB latency degrades for everyone.
- **Scenario 3:** We kept it simple with sync dispatch but added a fifth handler (notification service), and now signup takes 2.5 seconds because it waits for 5 API calls sequentially.

### Assumption Surfacing

**Challenged assumption:** "We need an event system." Actually, we need signup to be fast and side effects to be reliable. For ONE event type with four handlers, a simpler pattern might work: commit the signup, then dispatch side effects with a simple retry mechanism. This is not an "event system" — it's "background tasks triggered by signup."

## Convergence

**Methods agree on:** Decouple secondary effects from signup. Do not block the user. Ensure retryability.

**Methods disagree on:** How much infrastructure this needs. The Critic and Assumption Surfacing both challenge whether this needs a full event system.

**Tension:** The Operator wants full observability and retry, but the Critic warns against over-engineering for one event type.

**Recommendation:** Start with an async queue (SQS or Redis-based job queue) with a dead-letter queue for failures. This is the simplest approach that satisfies the Operator (retry + DLQ + monitoring) without the database coupling of the outbox pattern.

Do NOT build a generic event bus. Build "background jobs triggered by signup." If you add more event types later, generalize then.

**Concrete steps:**
1. Move the four handlers into background jobs (one job per handler)
2. After signup commits, enqueue four jobs
3. Each job retries 3 times with exponential backoff
4. Failed jobs go to a dead-letter queue with alerting
5. Add a simple dashboard showing job queue depth and failure rate

**Open questions:**
- What job queue does the monolith already use? (If none exists, adding one is the biggest decision.)
- What's the acceptable delay for side effects? Seconds? Minutes? This determines queue choice.
