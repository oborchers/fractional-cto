# Session Expiry Countdown Modal

Demonstrates a warning modal before session expiry with countdown timer, session extension, and post-logout notification explaining what was saved.

## Pseudocode

```
component SessionExpiryGuard(warningSeconds = 120):
    state showWarning = false
    state secondsLeft = warningSeconds
    state sessionExpired = false

    // Server provides session expiry time
    onMount:
        scheduleWarning(getSessionExpiryTime() - warningSeconds)

    function scheduleWarning(triggerAt):
        setTimeout(() => {
            showWarning = true
            secondsLeft = warningSeconds
            startCountdown()
        }, triggerAt - now())

    function startCountdown():
        interval = setInterval(() => {
            secondsLeft -= 1
            if secondsLeft <= 0:
                clearInterval(interval)
                handleExpired()
        }, 1000)

    function handleContinue():
        showWarning = false
        response = await api.extendSession()
        scheduleWarning(response.newExpiryTime - warningSeconds)

    function handleLogout():
        showWarning = false
        await api.logout()
        redirect("/login?reason=manual")

    function handleExpired():
        showWarning = false
        sessionExpired = true
        await api.logout()
        redirect("/login?reason=expired&saved=true")

    render:
        if showWarning:
            <Modal
                title="Session Expiring"
                blocking={true}
                aria-live="assertive"
            >
                <p>Your session will expire in {formatTime(secondsLeft)}.</p>
                <p>Any unsaved changes will be preserved.</p>

                <footer>
                    <Button variant="secondary" onClick={handleLogout}>
                        Log Out
                    </Button>
                    <Button variant="primary" onClick={handleContinue}>
                        Continue Session
                    </Button>
                </footer>
            </Modal>
```

## Post-Logout Login Page

```
component LoginPage:
    params = getUrlParams()

    render:
        if params.reason == "expired":
            <InlineNotification type="info">
                Your session expired due to inactivity.
                {params.saved == "true"
                    ? "Your work was automatically saved."
                    : "Some unsaved changes may have been lost."}
            </InlineNotification>

        if params.reason == "manual":
            <InlineNotification type="success">
                You have been logged out successfully.
            </InlineNotification>

        <LoginForm />
```

## React

```jsx
function SessionExpiryGuard({ warningSeconds = 120, children }) {
  const [showWarning, setShowWarning] = useState(false);
  const [secondsLeft, setSecondsLeft] = useState(warningSeconds);
  const intervalRef = useRef(null);

  useEffect(() => {
    const expiresAt = getSessionExpiryTime();
    const warnAt = expiresAt - warningSeconds * 1000;
    const timeout = setTimeout(() => {
      setShowWarning(true);
      setSecondsLeft(warningSeconds);

      intervalRef.current = setInterval(() => {
        setSecondsLeft(prev => {
          if (prev <= 1) {
            clearInterval(intervalRef.current);
            handleExpired();
            return 0;
          }
          return prev - 1;
        });
      }, 1000);
    }, warnAt - Date.now());

    return () => {
      clearTimeout(timeout);
      clearInterval(intervalRef.current);
    };
  }, []);

  async function handleContinue() {
    clearInterval(intervalRef.current);
    setShowWarning(false);
    await api.extendSession();
  }

  async function handleExpired() {
    setShowWarning(false);
    await api.logout();
    window.location.href = "/login?reason=expired&saved=true";
  }

  const minutes = Math.floor(secondsLeft / 60);
  const seconds = secondsLeft % 60;

  return (
    <>
      {children}
      {showWarning && (
        <Modal title="Session Expiring" blocking aria-live="assertive">
          <p>
            Your session will expire in {minutes}:{String(seconds).padStart(2, "0")}.
          </p>
          <p>Your work has been automatically saved.</p>
          <div className="modal-actions">
            <button onClick={() => api.logout().then(() =>
              window.location.href = "/login?reason=manual"
            )}>
              Log Out
            </button>
            <button className="primary" onClick={handleContinue}>
              Continue Session
            </button>
          </div>
        </Modal>
      )}
    </>
  );
}
```

## Key Points

- **Warn before expiration** — show a countdown modal, not a surprise logout
- **Both options available**: "Continue Session" (extends) and "Log Out" (graceful exit)
- **After auto-logout**, the login page explains what happened with an inline notification
- **Clearly communicate what was saved** — "Your work was automatically saved" or "Some unsaved changes may have been lost"
- Use `aria-live="assertive"` on the modal so screen readers announce it immediately
- Countdown timer gives users a sense of urgency and control
- Pass logout reason via URL params so the login page can display the right message
