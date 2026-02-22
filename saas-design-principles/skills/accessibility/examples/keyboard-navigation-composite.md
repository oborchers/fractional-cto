# Keyboard Navigation for Composite Widgets

Demonstrates the roving tabindex pattern for keyboard navigation within a composite widget (tab panel). Shows why accessible component libraries are preferred over hand-rolling.

## The Pattern: Roving Tabindex

Composite widgets (tab lists, listboxes, menus) use a single Tab stop. Arrow keys move between items within the widget.

```
Tab → enters the widget (focuses active item)
Arrow → moves between items
Enter/Space → activates item
Escape → closes (for overlays)
Tab → exits the widget (moves to next focusable element)
```

## Pseudocode

```
component TabPanel(tabs, activeTab):
    function onKeyDown(event, index):
        switch event.key:
            case "ArrowRight":
            case "ArrowDown":
                focusTab((index + 1) % tabs.length)
            case "ArrowLeft":
            case "ArrowUp":
                focusTab((index - 1 + tabs.length) % tabs.length)
            case "Home":
                focusTab(0)
            case "End":
                focusTab(tabs.length - 1)

    function focusTab(index):
        setActiveTab(tabs[index].id)
        tabRefs[index].focus()

    render:
        <div role="tablist">
            for each tab, index in tabs:
                <button
                    role="tab"
                    id={tab.id}
                    aria-selected={tab.id == activeTab}
                    aria-controls={tab.panelId}
                    tabindex={tab.id == activeTab ? 0 : -1}
                    onKeyDown={e => onKeyDown(e, index)}
                    onClick={() => setActiveTab(tab.id)}
                >
                    {tab.label}
                </button>

        for each tab in tabs:
            <div
                role="tabpanel"
                id={tab.panelId}
                aria-labelledby={tab.id}
                hidden={tab.id != activeTab}
            >
                {tab.content}
            </div>
```

## React

```jsx
function TabPanel({ tabs }) {
  const [activeId, setActiveId] = useState(tabs[0].id);
  const tabRefs = useRef([]);

  function focusTab(index) {
    setActiveId(tabs[index].id);
    tabRefs.current[index]?.focus();
  }

  function handleKeyDown(e, index) {
    const actions = {
      ArrowRight: () => focusTab((index + 1) % tabs.length),
      ArrowLeft:  () => focusTab((index - 1 + tabs.length) % tabs.length),
      Home:       () => focusTab(0),
      End:        () => focusTab(tabs.length - 1),
    };

    if (actions[e.key]) {
      e.preventDefault();
      actions[e.key]();
    }
  }

  return (
    <>
      <div role="tablist">
        {tabs.map((tab, i) => (
          <button
            key={tab.id}
            ref={el => (tabRefs.current[i] = el)}
            role="tab"
            id={tab.id}
            aria-selected={tab.id === activeId}
            aria-controls={tab.panelId}
            tabIndex={tab.id === activeId ? 0 : -1}
            onKeyDown={e => handleKeyDown(e, i)}
            onClick={() => setActiveId(tab.id)}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {tabs.map(tab => (
        <div
          key={tab.panelId}
          role="tabpanel"
          id={tab.panelId}
          aria-labelledby={tab.id}
          hidden={tab.id !== activeId}
        >
          {tab.content}
        </div>
      ))}
    </>
  );
}
```

## Why Use a Library Instead

The above is a simplified implementation. A production-ready version must also handle:
- Focus restoration when tabs are added/removed dynamically
- RTL (right-to-left) language support (swap Arrow directions)
- Disabled tabs (skip in arrow navigation)
- Automatic vs manual activation modes
- Touch device interactions
- Screen reader announcements for dynamic content changes

**Libraries like Radix UI, React Aria, or Headless UI handle all of these.** The edge cases are vast and the failure modes are invisible to sighted developers.

```jsx
// Radix UI — all accessibility built in
import * as Tabs from "@radix-ui/react-tabs";

<Tabs.Root defaultValue="tab1">
  <Tabs.List>
    <Tabs.Trigger value="tab1">General</Tabs.Trigger>
    <Tabs.Trigger value="tab2">Security</Tabs.Trigger>
  </Tabs.List>
  <Tabs.Content value="tab1">General settings...</Tabs.Content>
  <Tabs.Content value="tab2">Security settings...</Tabs.Content>
</Tabs.Root>
```

## Key Points

- **Tab** enters/exits the composite widget; **Arrow keys** move within it
- **Roving tabindex**: active item has `tabindex="0"`, all others have `tabindex="-1"`
- `aria-selected`, `aria-controls`, and `aria-labelledby` connect tabs to panels
- **Home/End** keys jump to first/last item
- **Prefer accessible libraries** (Radix UI, React Aria, Headless UI) over hand-rolling
- Hand-rolling misses RTL support, disabled state handling, and dynamic content — use libraries
