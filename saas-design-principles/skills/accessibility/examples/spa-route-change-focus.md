# SPA Route Change Focus Management

Demonstrates the three mandatory SPA fixes: update document title, move focus, and announce route changes via ARIA live region.

## The Problem

When a traditional page loads, browsers automatically:
1. Reset focus to the top of the page
2. Announce the new page title to screen readers
3. Reset scroll position

**Single-page applications break all three.** This must be fixed manually.

## Shared: ARIA Live Region Announcer

Place this once in the app shell (invisible, announced by screen readers):

```html
<!-- Placed in root layout, always present -->
<div
  id="route-announcer"
  role="status"
  aria-live="polite"
  aria-atomic="true"
  style="
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
  "
></div>
```

## React (React Router)

```jsx
import { useEffect } from "react";
import { useLocation } from "react-router-dom";

function RouteAnnouncer() {
  const location = useLocation();

  useEffect(() => {
    // 1. Update document title
    const pageTitle = getPageTitle(location.pathname);
    document.title = pageTitle;

    // 2. Move focus to main content
    const main = document.querySelector("main");
    if (main) {
      main.setAttribute("tabindex", "-1");
      main.focus();
      // Remove tabindex after focus so it doesn't appear in tab order
      main.addEventListener("blur", () => main.removeAttribute("tabindex"), {
        once: true,
      });
    }

    // 3. Announce route change to screen readers
    const announcer = document.getElementById("route-announcer");
    if (announcer) {
      announcer.textContent = `Navigated to ${pageTitle}`;
    }
  }, [location]);

  return null;
}

// Place inside <Router>:
// <RouteAnnouncer />
```

## Vue 3 (Vue Router)

```js
// router/index.js
import { createRouter, createWebHistory } from "vue-router";

const router = createRouter({ history: createWebHistory(), routes });

router.afterEach((to) => {
  // Runs after every route change

  // 1. Update document title
  const pageTitle = to.meta.title || "App";
  document.title = pageTitle;

  // 2. Move focus to main content (use nextTick to wait for DOM update)
  nextTick(() => {
    const main = document.querySelector("main");
    if (main) {
      main.setAttribute("tabindex", "-1");
      main.focus();
      main.addEventListener("blur", () => main.removeAttribute("tabindex"), {
        once: true,
      });
    }
  });

  // 3. Announce route change
  const announcer = document.getElementById("route-announcer");
  if (announcer) {
    announcer.textContent = `Navigated to ${pageTitle}`;
  }
});
```

## SvelteKit

```svelte
<!-- src/routes/+layout.svelte -->
<script>
  import { afterNavigate } from "$app/navigation";
  import { page } from "$app/stores";

  afterNavigate(() => {
    // 1. Title is set per-page via <svelte:head>, but ensure it's updated
    // 2. Move focus to main content
    const main = document.querySelector("main");
    if (main) {
      main.setAttribute("tabindex", "-1");
      main.focus();
      main.addEventListener("blur", () => main.removeAttribute("tabindex"), {
        once: true,
      });
    }

    // 3. Announce route change
    const announcer = document.getElementById("route-announcer");
    if (announcer) {
      announcer.textContent = `Navigated to ${document.title}`;
    }
  });
</script>

<!-- ARIA live region — always present in layout -->
<div
  id="route-announcer"
  role="status"
  aria-live="polite"
  aria-atomic="true"
  class="sr-only"
></div>

<main>
  <slot />
</main>

<style>
  .sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
  }
</style>
```

## Key Points

- **Update `<title>`** on every route change — screen readers announce it
- **Move focus** to `<main>` with `tabindex="-1"` for programmatic focus
- **Remove `tabindex`** after blur so the element doesn't appear in normal tab order
- **ARIA live region** (`role="status"`, `aria-live="polite"`) announces the navigation
- **When uncertain** where to place focus, move it to the top of the page — always correct
- This pattern is the **most commonly failed** SPA accessibility requirement
