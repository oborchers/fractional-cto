# Error State Components

Demonstrates three key error state patterns: permission denied (403), offline banner with action queue, and server error (500) with retry.

## Permission Denied (403)

```
component PermissionDenied(requiredRole, adminUser, featureName):
    render:
        <div class="error-page" role="alert">
            <icon name="lock" />
            <h2>You don't have access to {featureName}</h2>
            <p>
                This feature requires the <strong>{requiredRole}</strong> role.
                {adminUser.name} ({adminUser.email}) can grant you access.
            </p>
            <div class="actions">
                <Button
                    variant="primary"
                    onClick={() => api.requestAccess(featureName)}
                >
                    Request Access
                </Button>
                <Button variant="secondary" onClick={() => navigate(-1)}>
                    Go Back
                </Button>
            </div>
        </div>
```

**Rules:**
- Show **who** has the required permission (name + email)
- Provide a **"Request Access"** button — not just "Contact your administrator"
- Offer an **alternative action** (go back, view read-only)

## Offline Banner with Action Queue

```
component OfflineBanner(queuedActions):
    render:
        if not navigator.onLine:
            <div class="banner banner-warning" role="status">
                <icon name="wifi-off" />
                <span>
                    You're offline.
                    {queuedActions.length > 0
                        ? `${queuedActions.length} action(s) will sync when you reconnect.`
                        : "Changes will be saved when you reconnect."}
                </span>
            </div>

// Queue actions while offline
function createOfflineQueue():
    queue = []

    function enqueue(action):
        queue.push({ action, timestamp: now() })
        saveToLocalStorage(queue)

    function onReconnect():
        for each item in queue:
            try:
                await item.action()
            catch:
                showToast("Failed to sync: " + item.description, "error")
        queue = []
        clearLocalStorage()

    // Listen for reconnection
    window.addEventListener("online", onReconnect)

    return { enqueue, queue }
```

**Rules:**
- **Clear offline banner** visible at top of screen
- Show **count of queued actions** so users know work isn't lost
- **Sync automatically** on reconnection — no manual action needed
- Handle sync failures gracefully with per-action error toasts

## Server Error (500)

```
component ServerError(error, onRetry):
    render:
        <div class="error-page" role="alert">
            <icon name="server-error" />
            <h2>Something went wrong</h2>
            <p>
                We couldn't complete your request. This is usually temporary.
            </p>
            <div class="actions">
                <Button variant="primary" onClick={onRetry}>
                    Try Again
                </Button>
                <Button
                    variant="secondary"
                    onClick={() => navigate("/")}
                >
                    Go to Dashboard
                </Button>
            </div>

            {/* Never show to users: error.stack, error.code, error.trace */}
        </div>
```

**Rules:**
- **Friendly language** — "Something went wrong" not "500 Internal Server Error"
- **Retry button** — most 500s are transient
- **Escape hatch** — link to a known-good page (dashboard, home)
- **Never expose** stack traces, error codes, or technical details to end users
- Log the technical details to your error tracking service (Sentry, etc.)

## Rate Limiting (429)

```
component RateLimitNotice(retryAfterSeconds):
    state countdown = retryAfterSeconds

    render:
        <div class="banner banner-warning" role="status">
            <icon name="clock" />
            <span>
                Too many requests. You can try again in {countdown} seconds.
            </span>
            {countdown <= 0 &&
                <Button variant="link" onClick={onRetry}>Retry now</Button>
            }
        </div>
```

**Rules:**
- Show a **countdown** (from the `Retry-After` header)
- Enable the retry action **only after the countdown completes**
- Use a banner, not a modal — rate limiting is not a blocking error
