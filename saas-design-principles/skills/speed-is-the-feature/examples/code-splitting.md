# Route-Level Code Splitting

Demonstrates splitting bundles by route and lazy-loading non-critical UI to stay under the 200KB gzipped budget.

## React

```jsx
import { lazy, Suspense } from "react";
import { Routes, Route } from "react-router-dom";

// Route-level splits — each page loads only when navigated to
const Dashboard = lazy(() => import("./pages/Dashboard"));
const Settings  = lazy(() => import("./pages/Settings"));
const Analytics = lazy(() => import("./pages/Analytics"));

// Non-critical UI — lazy-load heavy components
const ExportModal = lazy(() => import("./components/ExportModal"));
const ChartWidget = lazy(() => import("./components/ChartWidget"));

function App() {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <Routes>
        <Route path="/"         element={<Dashboard />} />
        <Route path="/settings" element={<Settings />} />
        <Route path="/analytics" element={<Analytics />} />
      </Routes>
    </Suspense>
  );
}
```

## Vue 3

```js
// router/index.js
import { createRouter, createWebHistory } from "vue-router";

const routes = [
  {
    path: "/",
    // Route-level split — returns a dynamic import
    component: () => import("../pages/Dashboard.vue"),
  },
  {
    path: "/settings",
    component: () => import("../pages/Settings.vue"),
  },
  {
    path: "/analytics",
    component: () => import("../pages/Analytics.vue"),
  },
];

export default createRouter({ history: createWebHistory(), routes });
```

```vue
<!-- Lazy-loading a heavy component within a page -->
<script setup>
import { defineAsyncComponent } from "vue";

const ChartWidget = defineAsyncComponent(
  () => import("../components/ChartWidget.vue")
);
</script>

<template>
  <Suspense>
    <ChartWidget :data="chartData" />
    <template #fallback>
      <div class="skeleton skeleton-chart" />
    </template>
  </Suspense>
</template>
```

## SvelteKit

```js
// Routes are automatically code-split in SvelteKit.
// Each +page.svelte is its own chunk.
//
// src/routes/
// ├── +page.svelte          → /
// ├── settings/+page.svelte → /settings
// └── analytics/+page.svelte → /analytics

// For lazy-loading a heavy component within a page:
```

```svelte
<!-- src/routes/analytics/+page.svelte -->
<script>
  import { onMount } from "svelte";

  let ChartWidget;
  onMount(async () => {
    const module = await import("$lib/components/ChartWidget.svelte");
    ChartWidget = module.default;
  });
</script>

{#if ChartWidget}
  <svelte:component this={ChartWidget} data={chartData} />
{:else}
  <div class="skeleton skeleton-chart" />
{/if}
```

## What to Split

| Split at route level | Lazy-load within pages |
|---------------------|----------------------|
| Every top-level page | Modals and dialogs |
| Settings sections | Charts and data visualizations |
| Admin panels | Rich text editors |
| Onboarding flows | Export/import features |

## Key Points

- Split by **route** first — the biggest wins come from not loading pages the user hasn't visited
- Lazy-load **modals, charts, and non-critical UI** within pages
- Use skeleton screens as fallbacks during lazy loads
- SvelteKit and Next.js split by route automatically — configure it manually for plain React/Vue
- Monitor bundle size: total JS should stay **under 200KB gzipped**
