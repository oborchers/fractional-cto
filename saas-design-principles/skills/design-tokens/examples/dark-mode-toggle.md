# Dark Mode Toggle

Demonstrates the hybrid approach: detect system preference, allow manual override, store in localStorage, apply via data attribute. No component re-renders needed.

## Core Logic (Framework-Agnostic)

```js
// theme.js — shared logic for all frameworks

const STORAGE_KEY = "theme-preference";
const THEMES = ["light", "dim", "dark"]; // Twitter-style three-option model

function getSystemPreference() {
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

function getStoredPreference() {
  return localStorage.getItem(STORAGE_KEY);
}

function getEffectiveTheme() {
  return getStoredPreference() || getSystemPreference();
}

function applyTheme(theme) {
  document.documentElement.setAttribute("data-theme", theme);
}

function setTheme(theme) {
  localStorage.setItem(STORAGE_KEY, theme);
  applyTheme(theme);
}

// Apply on page load (before first paint — put in <head>)
applyTheme(getEffectiveTheme());

// Listen for system preference changes
window
  .matchMedia("(prefers-color-scheme: dark)")
  .addEventListener("change", (e) => {
    if (!getStoredPreference()) {
      applyTheme(e.matches ? "dark" : "light");
    }
  });
```

## Inline Script (Prevent Flash of Wrong Theme)

Place this in `<head>` before any stylesheets to prevent flash:

```html
<script>
  (function() {
    var stored = localStorage.getItem("theme-preference");
    var theme = stored || (
      window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
    );
    document.documentElement.setAttribute("data-theme", theme);
  })();
</script>
```

## React

```jsx
import { useState, useEffect } from "react";
import { getEffectiveTheme, setTheme } from "./theme";

function ThemeToggle() {
  const [current, setCurrent] = useState(getEffectiveTheme);

  function cycle() {
    const themes = ["light", "dim", "dark"];
    const next = themes[(themes.indexOf(current) + 1) % themes.length];
    setTheme(next);
    setCurrent(next);
  }

  // No re-render of children needed — CSS variables cascade automatically
  return (
    <button onClick={cycle} aria-label={`Theme: ${current}`}>
      {current === "light" ? "☀️" : current === "dim" ? "🌤" : "🌙"}
    </button>
  );
}
```

## Vue 3

```vue
<script setup>
import { ref } from "vue";
import { getEffectiveTheme, setTheme } from "./theme";

const current = ref(getEffectiveTheme());
const themes = ["light", "dim", "dark"];
const icons = { light: "☀️", dim: "🌤", dark: "🌙" };

function cycle() {
  const next = themes[(themes.indexOf(current.value) + 1) % themes.length];
  setTheme(next);
  current.value = next;
}
</script>

<template>
  <button @click="cycle" :aria-label="`Theme: ${current}`">
    {{ icons[current] }}
  </button>
</template>
```

## Svelte

```svelte
<script>
  import { getEffectiveTheme, setTheme } from "./theme";

  let current = getEffectiveTheme();
  const themes = ["light", "dim", "dark"];
  const icons = { light: "☀️", dim: "🌤", dark: "🌙" };

  function cycle() {
    const next = themes[(themes.indexOf(current) + 1) % themes.length];
    setTheme(next);
    current = next;
  }
</script>

<button on:click={cycle} aria-label="Theme: {current}">
  {icons[current]}
</button>
```

## Key Points

- Apply theme **in `<head>` before stylesheets** to prevent flash of wrong theme
- Detect system preference with `prefers-color-scheme`
- Allow **manual override** that persists in `localStorage`
- Apply via `data-theme` attribute on `<html>` — CSS variables cascade, no re-renders
- Listen for **system changes** but respect stored manual preference
- Consider three options (light/dim/dark) for long-session apps
- The toggle component only updates itself — all other components update via CSS cascade
