# Skeleton Screen with Shimmer

Demonstrates a skeleton loading state that matches actual content layout with a left-to-right shimmer animation.

## CSS (Shared across frameworks)

```css
.skeleton {
  background: linear-gradient(
    90deg,
    var(--color-bg-subtle) 25%,
    var(--color-bg-muted) 50%,
    var(--color-bg-subtle) 75%
  );
  background-size: 200% 100%;
  animation: shimmer 1.5s ease-in-out infinite;
  border-radius: 4px;
}

@keyframes shimmer {
  0%   { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}

/* Skeleton elements must match actual content dimensions */
.skeleton-avatar  { width: 40px; height: 40px; border-radius: 50%; }
.skeleton-title   { width: 60%; height: 20px; }
.skeleton-text    { width: 100%; height: 14px; margin-top: 8px; }
.skeleton-text-sm { width: 80%; height: 14px; margin-top: 8px; }
```

## Pseudocode

```
component ContentCard(isLoading, data):
    if isLoading:
        render:
            <div class="card">
                <div class="skeleton skeleton-avatar" />
                <div class="skeleton skeleton-title" />
                <div class="skeleton skeleton-text" />
                <div class="skeleton skeleton-text-sm" />
            </div>
    else:
        render:
            <div class="card">
                <img src={data.avatar} />
                <h3>{data.title}</h3>
                <p>{data.description}</p>
            </div>
```

## React

```jsx
function ContentCard({ isLoading, data }) {
  if (isLoading) {
    return (
      <div className="card">
        <div className="skeleton skeleton-avatar" />
        <div className="skeleton skeleton-title" />
        <div className="skeleton skeleton-text" />
        <div className="skeleton skeleton-text-sm" />
      </div>
    );
  }

  return (
    <div className="card">
      <img src={data.avatar} alt={data.name} />
      <h3>{data.title}</h3>
      <p>{data.description}</p>
    </div>
  );
}
```

## Vue 3

```vue
<template>
  <div class="card">
    <template v-if="isLoading">
      <div class="skeleton skeleton-avatar" />
      <div class="skeleton skeleton-title" />
      <div class="skeleton skeleton-text" />
      <div class="skeleton skeleton-text-sm" />
    </template>
    <template v-else>
      <img :src="data.avatar" :alt="data.name" />
      <h3>{{ data.title }}</h3>
      <p>{{ data.description }}</p>
    </template>
  </div>
</template>
```

## Svelte

```svelte
<div class="card">
  {#if isLoading}
    <div class="skeleton skeleton-avatar" />
    <div class="skeleton skeleton-title" />
    <div class="skeleton skeleton-text" />
    <div class="skeleton skeleton-text-sm" />
  {:else}
    <img src={data.avatar} alt={data.name} />
    <h3>{data.title}</h3>
    <p>{data.description}</p>
  {/if}
</div>
```

## Key Points

- Shimmer uses a **left-to-right** gradient animation (perceived as faster than pulsing)
- Animation speed is **1.5s** — slow and steady beats fast motion
- Skeleton elements **match actual content dimensions** (avatar, title, text lines)
- Only use for loads of **1.5–10 seconds** — below 1.5s show nothing or a subtle spinner
- Use semantic tokens for skeleton colors so it works in both light and dark modes
