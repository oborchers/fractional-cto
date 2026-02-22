# Reward Early, Punish Late Validation

Demonstrates blur-based validation: show success immediately, delay errors until the user has finished and moved on.

## Pseudocode

```
component ValidatedInput(label, validate, value):
    state status = "idle"        // idle | valid | invalid
    state errorMessage = ""

    function onBlur():
        result = validate(value)
        if result.valid:
            status = "valid"     // Green checkmark immediately
            errorMessage = ""
        else:
            status = "invalid"   // Red border + message
            errorMessage = result.message

    function onFocus():
        if status == "invalid":
            status = "idle"      // Clear error when re-editing
            errorMessage = ""

    render:
        <label>{label}</label>
        <input
            value={value}
            onBlur={onBlur}
            onFocus={onFocus}
            class={status}
            aria-invalid={status == "invalid"}
            aria-describedby={errorMessage ? errorId : undefined}
        />
        if status == "valid":
            <span class="success-icon">✓</span>
        if status == "invalid":
            <span class="error-text" id={errorId}>{errorMessage}</span>
```

## React

```jsx
function ValidatedInput({ label, validate, value, onChange }) {
  const [status, setStatus] = useState("idle");
  const [error, setError] = useState("");
  const errorId = `${label}-error`;

  function handleBlur() {
    const result = validate(value);
    if (result.valid) {
      setStatus("valid");
      setError("");
    } else {
      setStatus("invalid");
      setError(result.message);
    }
  }

  function handleFocus() {
    if (status === "invalid") {
      setStatus("idle");
      setError("");
    }
  }

  return (
    <div className="field">
      <label>{label}</label>
      <div className="input-wrapper">
        <input
          value={value}
          onChange={e => onChange(e.target.value)}
          onBlur={handleBlur}
          onFocus={handleFocus}
          className={status}
          aria-invalid={status === "invalid"}
          aria-describedby={error ? errorId : undefined}
        />
        {status === "valid" && <span className="success-icon">✓</span>}
      </div>
      {status === "invalid" && (
        <span className="error-text" id={errorId} role="alert">
          {error}
        </span>
      )}
    </div>
  );
}

// Usage
const validateEmail = (v) =>
  v.includes("@")
    ? { valid: true }
    : { valid: false, message: "Email must include an @ symbol" };
```

## Vue 3

```vue
<script setup>
import { ref } from "vue";

const props = defineProps({ label: String, validate: Function, modelValue: String });
const emit = defineEmits(["update:modelValue"]);

const status = ref("idle");
const error = ref("");

function handleBlur() {
  const result = props.validate(props.modelValue);
  if (result.valid) {
    status.value = "valid";
    error.value = "";
  } else {
    status.value = "invalid";
    error.value = result.message;
  }
}

function handleFocus() {
  if (status.value === "invalid") {
    status.value = "idle";
    error.value = "";
  }
}
</script>

<template>
  <div class="field">
    <label>{{ label }}</label>
    <div class="input-wrapper">
      <input
        :value="modelValue"
        @input="emit('update:modelValue', $event.target.value)"
        @blur="handleBlur"
        @focus="handleFocus"
        :class="status"
        :aria-invalid="status === 'invalid'"
      />
      <span v-if="status === 'valid'" class="success-icon">✓</span>
    </div>
    <span v-if="status === 'invalid'" class="error-text" role="alert">
      {{ error }}
    </span>
  </div>
</template>
```

## Svelte

```svelte
<script>
  export let label;
  export let validate;
  export let value;

  let status = "idle";
  let error = "";

  function handleBlur() {
    const result = validate(value);
    if (result.valid) {
      status = "valid";
      error = "";
    } else {
      status = "invalid";
      error = result.message;
    }
  }

  function handleFocus() {
    if (status === "invalid") {
      status = "idle";
      error = "";
    }
  }
</script>

<div class="field">
  <label>{label}</label>
  <div class="input-wrapper">
    <input
      bind:value
      on:blur={handleBlur}
      on:focus={handleFocus}
      class={status}
      aria-invalid={status === "invalid"}
    />
    {#if status === "valid"}
      <span class="success-icon">✓</span>
    {/if}
  </div>
  {#if status === "invalid"}
    <span class="error-text" role="alert">{error}</span>
  {/if}
</div>
```

## Key Points

- Validate **on blur** (when user leaves the field), never on every keystroke
- Show **green checkmark immediately** on valid input (reward early)
- Show **red border + message** only after the user has moved on (punish late)
- **Clear errors on re-focus** so the user starts fresh when re-editing
- Error text uses `role="alert"` for screen reader announcement
- Error messages tell the user **what went wrong AND how to fix it**
