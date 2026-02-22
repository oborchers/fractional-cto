# Toast Notification System

Demonstrates a toast manager that enforces the 4-toast maximum, auto-dismisses at 3 seconds for no-action toasts, and persists toasts with actions.

## Pseudocode

```
class ToastManager:
    MAX_VISIBLE = 4
    AUTO_DISMISS_MS = 3000

    state toasts = []
    state idCounter = 0

    function show(message, type = "info", action = null):
        id = ++idCounter
        toast = { id, message, type, action, createdAt: now() }

        // Enforce maximum
        if toasts.length >= MAX_VISIBLE:
            dismiss(toasts[0].id)   // Remove oldest

        toasts.push(toast)

        // Auto-dismiss if no action
        if not action:
            setTimeout(() => dismiss(id), AUTO_DISMISS_MS)

        return id

    function dismiss(id):
        toasts = toasts.filter(t => t.id != id)

    // Convenience methods
    function success(message):     show(message, "success")
    function error(message):       show(message, "error")
    function warning(message):     show(message, "warning")
    function info(message):        show(message, "info")
    function withUndo(message, undoFn):
        show(message, "success", { label: "Undo", onClick: undoFn })
```

## React

```jsx
const ToastContext = createContext(null);

function ToastProvider({ children }) {
  const [toasts, setToasts] = useState([]);
  const idRef = useRef(0);

  const toast = useMemo(() => ({
    show(message, type = "info", action = null) {
      const id = ++idRef.current;
      setToasts(prev => {
        const next = prev.length >= 4 ? prev.slice(1) : prev;
        return [...next, { id, message, type, action }];
      });

      if (!action) {
        setTimeout(() => this.dismiss(id), 3000);
      }
      return id;
    },
    dismiss(id) {
      setToasts(prev => prev.filter(t => t.id !== id));
    },
    success: (msg) => toast.show(msg, "success"),
    error:   (msg) => toast.show(msg, "error"),
    warning: (msg) => toast.show(msg, "warning"),
    withUndo: (msg, undoFn) => toast.show(msg, "success", {
      label: "Undo", onClick: undoFn
    }),
  }), []);

  return (
    <ToastContext.Provider value={toast}>
      {children}
      <ToastContainer toasts={toasts} onDismiss={toast.dismiss} />
    </ToastContext.Provider>
  );
}

function ToastContainer({ toasts, onDismiss }) {
  return (
    <div className="toast-container" role="status" aria-live="polite">
      {toasts.map(t => (
        <div key={t.id} className={`toast toast-${t.type}`}>
          <Icon name={iconForType(t.type)} />
          <span>{t.message}</span>
          {t.action && (
            <button className="toast-action" onClick={() => {
              t.action.onClick();
              onDismiss(t.id);
            }}>
              {t.action.label}
            </button>
          )}
          <button
            className="toast-close"
            onClick={() => onDismiss(t.id)}
            aria-label="Dismiss"
          >
            ×
          </button>
        </div>
      ))}
    </div>
  );
}

function iconForType(type) {
  const icons = {
    info: "info-circle",
    success: "check-circle",
    warning: "alert-triangle",
    error: "x-circle",
  };
  return icons[type];
}

// Usage
function DeleteButton({ item }) {
  const toast = useContext(ToastContext);

  async function handleDelete() {
    const backup = { ...item };
    await api.deleteItem(item.id);

    toast.withUndo(`"${item.name}" deleted`, async () => {
      await api.restoreItem(backup);
    });
  }

  return <button onClick={handleDelete}>Delete</button>;
}
```

## CSS

```css
.toast-container {
  position: fixed;
  bottom: 16px;
  right: 16px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  z-index: 1000;
  max-width: 400px;
}

.toast {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 16px;
  border-radius: var(--radius-default);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  animation: slide-in 200ms ease-out;
}

.toast-info    { background: var(--color-status-info-bg);    border-left: 3px solid var(--color-status-info); }
.toast-success { background: var(--color-status-success-bg); border-left: 3px solid var(--color-status-success); }
.toast-warning { background: var(--color-status-warning-bg); border-left: 3px solid var(--color-status-warning); }
.toast-error   { background: var(--color-status-error-bg);   border-left: 3px solid var(--color-status-error); }

@keyframes slide-in {
  from { transform: translateX(100%); opacity: 0; }
  to   { transform: translateX(0);    opacity: 1; }
}
```

## Key Points

- **4-toast maximum** — remove oldest when limit reached
- **3-second auto-dismiss** for toasts without actions
- **Persist toasts with actions** (undo, retry) until user dismisses
- Each type has both a **color AND unique icon** — never rely on color alone
- `role="status"` and `aria-live="polite"` for screen reader announcements
- Toast container uses fixed positioning at bottom-right
- Include a dismiss button on every toast for keyboard accessibility
