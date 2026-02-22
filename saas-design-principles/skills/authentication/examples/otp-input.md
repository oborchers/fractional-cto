# OTP Input Field

Demonstrates the correct OTP input with proper HTML attributes, auto-advance between digits, paste support, and auto-submit on completion.

## Critical HTML Attributes

```html
<!-- CORRECT: text input with numeric keyboard -->
<input type="text" inputmode="numeric" autocomplete="one-time-code" />

<!-- WRONG: number input allows scroll-wheel changes and scientific notation -->
<input type="number" />
```

## Pseudocode

```
component OtpInput(length = 6, onComplete):
    state digits = array of "" × length
    refs inputRefs = array of refs × length

    function handleInput(index, value):
        // Accept only single digits
        digit = value.replace(/\D/g, "").slice(-1)
        digits[index] = digit

        if digit and index < length - 1:
            inputRefs[index + 1].focus()   // Auto-advance

        if allDigitsFilled():
            onComplete(digits.join(""))    // Auto-submit

    function handleKeyDown(index, key):
        if key == "Backspace" and digits[index] == "" and index > 0:
            inputRefs[index - 1].focus()   // Back on empty backspace

    function handlePaste(event):
        pastedText = event.clipboardData.getData("text")
        pastedDigits = pastedText.replace(/\D/g, "").slice(0, length)
        for i, digit in pastedDigits:
            digits[i] = digit
        inputRefs[min(pastedDigits.length, length - 1)].focus()

        if allDigitsFilled():
            onComplete(digits.join(""))

    render:
        <div role="group" aria-label="One-time code">
            for i in 0..length:
                <input
                    ref={inputRefs[i]}
                    type="text"
                    inputmode="numeric"
                    autocomplete={i == 0 ? "one-time-code" : "off"}
                    maxlength="1"
                    value={digits[i]}
                    onInput={v => handleInput(i, v)}
                    onKeyDown={e => handleKeyDown(i, e.key)}
                    onPaste={handlePaste}
                    aria-label={`Digit ${i + 1} of ${length}`}
                />
        </div>
```

## React

```jsx
function OtpInput({ length = 6, onComplete }) {
  const [digits, setDigits] = useState(Array(length).fill(""));
  const refs = useRef([]);

  function handleInput(index, value) {
    const digit = value.replace(/\D/g, "").slice(-1);
    const next = [...digits];
    next[index] = digit;
    setDigits(next);

    if (digit && index < length - 1) {
      refs.current[index + 1].focus();
    }

    if (next.every(d => d !== "")) {
      onComplete(next.join(""));
    }
  }

  function handleKeyDown(index, e) {
    if (e.key === "Backspace" && !digits[index] && index > 0) {
      refs.current[index - 1].focus();
    }
  }

  function handlePaste(e) {
    e.preventDefault();
    const pasted = e.clipboardData.getData("text").replace(/\D/g, "").slice(0, length);
    const next = [...digits];
    [...pasted].forEach((d, i) => { next[i] = d; });
    setDigits(next);
    refs.current[Math.min(pasted.length, length - 1)].focus();

    if (next.every(d => d !== "")) {
      onComplete(next.join(""));
    }
  }

  return (
    <div role="group" aria-label="One-time code">
      {digits.map((digit, i) => (
        <input
          key={i}
          ref={el => (refs.current[i] = el)}
          type="text"
          inputMode="numeric"
          autoComplete={i === 0 ? "one-time-code" : "off"}
          maxLength={1}
          value={digit}
          onChange={e => handleInput(i, e.target.value)}
          onKeyDown={e => handleKeyDown(i, e)}
          onPaste={handlePaste}
          aria-label={`Digit ${i + 1} of ${length}`}
        />
      ))}
    </div>
  );
}
```

## Vue 3

```vue
<script setup>
import { ref, nextTick } from "vue";

const props = defineProps({ length: { type: Number, default: 6 } });
const emit = defineEmits(["complete"]);

const digits = ref(Array(props.length).fill(""));
const inputs = ref([]);

function handleInput(index, event) {
  const digit = event.target.value.replace(/\D/g, "").slice(-1);
  digits.value[index] = digit;
  event.target.value = digit;

  if (digit && index < props.length - 1) {
    inputs.value[index + 1].focus();
  }

  if (digits.value.every(d => d !== "")) {
    emit("complete", digits.value.join(""));
  }
}

function handleKeyDown(index, event) {
  if (event.key === "Backspace" && !digits.value[index] && index > 0) {
    inputs.value[index - 1].focus();
  }
}

function handlePaste(event) {
  event.preventDefault();
  const pasted = event.clipboardData.getData("text").replace(/\D/g, "").slice(0, props.length);
  [...pasted].forEach((d, i) => { digits.value[i] = d; });
  inputs.value[Math.min(pasted.length, props.length - 1)].focus();

  if (digits.value.every(d => d !== "")) {
    emit("complete", digits.value.join(""));
  }
}
</script>

<template>
  <div role="group" aria-label="One-time code">
    <input
      v-for="(_, i) in length"
      :key="i"
      :ref="el => (inputs[i] = el)"
      type="text"
      inputmode="numeric"
      :autocomplete="i === 0 ? 'one-time-code' : 'off'"
      maxlength="1"
      :value="digits[i]"
      @input="e => handleInput(i, e)"
      @keydown="e => handleKeyDown(i, e)"
      @paste="handlePaste"
      :aria-label="`Digit ${i + 1} of ${length}`"
    />
  </div>
</template>
```

## Key Points

- Use `type="text"` with `inputmode="numeric"` — NEVER `type="number"`
- Set `autocomplete="one-time-code"` on the first input for iOS/macOS autofill
- **Auto-advance** to next input on digit entry
- **Auto-submit** when all digits are filled — no submit button needed
- **Paste support** — extract digits from pasted text and distribute across inputs
- **Backspace** on empty field moves focus to previous field
- Each input has `aria-label` for screen reader context
- `role="group"` wraps the inputs with a descriptive label
