# Optimistic Update with Rollback

Demonstrates immediate UI feedback with server reconciliation and graceful rollback on failure.

## Pseudocode

```
function toggleFavorite(itemId):
    previousState = getState(itemId)

    // Update UI immediately
    setState(itemId, { isFavorite: !previousState.isFavorite })

    try:
        await api.toggleFavorite(itemId)
    catch error:
        // Revert on failure
        setState(itemId, previousState)
        showToast("Failed to update. Please try again.", "error")
```

## React

```jsx
function FavoriteButton({ itemId, isFavorite }) {
  const [optimistic, setOptimistic] = useState(isFavorite);
  const [pending, setPending] = useState(false);

  async function toggle() {
    const previous = optimistic;
    setOptimistic(!previous);        // Instant feedback
    setPending(true);

    try {
      await api.toggleFavorite(itemId);
    } catch {
      setOptimistic(previous);       // Revert
      toast.error("Failed to update. Please try again.");
    } finally {
      setPending(false);
    }
  }

  return (
    <button onClick={toggle} disabled={pending} aria-pressed={optimistic}>
      {optimistic ? "★" : "☆"}
    </button>
  );
}
```

## Vue 3

```vue
<script setup>
import { ref } from "vue";

const props = defineProps({ itemId: String, isFavorite: Boolean });
const optimistic = ref(props.isFavorite);
const pending = ref(false);

async function toggle() {
  const previous = optimistic.value;
  optimistic.value = !previous;       // Instant feedback
  pending.value = true;

  try {
    await api.toggleFavorite(props.itemId);
  } catch {
    optimistic.value = previous;      // Revert
    toast.error("Failed to update. Please try again.");
  } finally {
    pending.value = false;
  }
}
</script>

<template>
  <button @click="toggle" :disabled="pending" :aria-pressed="optimistic">
    {{ optimistic ? "★" : "☆" }}
  </button>
</template>
```

## Svelte

```svelte
<script>
  export let itemId;
  export let isFavorite;

  let optimistic = isFavorite;
  let pending = false;

  async function toggle() {
    const previous = optimistic;
    optimistic = !previous;           // Instant feedback
    pending = true;

    try {
      await api.toggleFavorite(itemId);
    } catch {
      optimistic = previous;          // Revert
      toast.error("Failed to update. Please try again.");
    } finally {
      pending = false;
    }
  }
</script>

<button on:click={toggle} disabled={pending} aria-pressed={optimistic}>
  {optimistic ? "★" : "☆"}
</button>
```

## Key Points

- Update state BEFORE the API call — the UI responds within 100ms
- Store previous state so rollback is a single assignment
- Show an actionable error toast on failure, not a generic message
- Use `aria-pressed` for toggle state accessibility
- Only apply optimistic updates to actions with >97% success rate
