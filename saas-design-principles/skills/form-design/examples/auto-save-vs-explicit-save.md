# Auto-Save vs Explicit Save

Demonstrates the correct pattern: toggle switches save immediately, text inputs use explicit save (or debounced auto-save). Never mix both in one form.

## Pseudocode

```
component SettingsForm:
    state formData = loadFromServer()
    state isDirty = false
    state isSaving = false
    let debounceTimer = null

    // Toggle switches — save immediately, no button needed
    function onToggleChange(key, newValue):
        formData[key] = newValue
        await api.saveSetting(key, newValue)   // Immediate
        showToast("Setting updated")

    // Text inputs — track dirty state, save on button click
    function onTextChange(key, newValue):
        formData[key] = newValue
        isDirty = true

        // Optional: auto-save with debounce
        clearTimeout(debounceTimer)
        debounceTimer = setTimeout(() => autoSave(), 3000)

    function onTextBlur(key):
        // Also save on blur (in addition to 3s debounce)
        autoSave()

    function autoSave():
        if not isDirty: return
        clearTimeout(debounceTimer)
        saveToServer()

    function saveToServer():
        isSaving = true
        await api.saveSettings(formData)
        isDirty = false
        isSaving = false

    render:
        <form>
            <!-- Toggles save immediately -->
            <Toggle
                label="Email notifications"
                checked={formData.emailNotifications}
                onChange={v => onToggleChange("emailNotifications", v)}
            />

            <!-- Text inputs require explicit save -->
            <TextInput
                label="Display name"
                value={formData.displayName}
                onChange={v => onTextChange("displayName", v)}
                onBlur={() => onTextBlur("displayName")}
            />

            <!-- Save button always visible (even with auto-save) -->
            <SaveButton
                disabled={!isDirty || isSaving}
                label={isSaving ? "Saving..." : isDirty ? "Save changes" : "Saved"}
            />
        </form>
```

## React

```jsx
function SettingsForm() {
  const [form, setForm] = useState(initialData);
  const [isDirty, setDirty] = useState(false);
  const [isSaving, setSaving] = useState(false);
  const timerRef = useRef(null);

  // Toggle — saves immediately
  async function handleToggle(key, value) {
    setForm(prev => ({ ...prev, [key]: value }));
    await api.saveSetting(key, value);
    toast.success("Setting updated");
  }

  // Text — marks dirty, starts debounce
  function handleText(key, value) {
    setForm(prev => ({ ...prev, [key]: value }));
    setDirty(true);

    clearTimeout(timerRef.current);
    timerRef.current = setTimeout(save, 3000);
  }

  function handleBlur() {
    if (isDirty) save();
  }

  async function save() {
    clearTimeout(timerRef.current);
    setSaving(true);
    await api.saveSettings(form);
    setDirty(false);
    setSaving(false);
  }

  return (
    <form onSubmit={e => { e.preventDefault(); save(); }}>
      <Toggle
        label="Email notifications"
        checked={form.emailNotifications}
        onChange={v => handleToggle("emailNotifications", v)}
      />

      <TextInput
        label="Display name"
        value={form.displayName}
        onChange={v => handleText("displayName", v)}
        onBlur={handleBlur}
      />

      {/* Always show Save — even with auto-save, for psychological reassurance */}
      <button type="submit" disabled={!isDirty || isSaving}>
        {isSaving ? "Saving..." : isDirty ? "Save changes" : "Saved"}
      </button>
    </form>
  );
}
```

## Vue 3

```vue
<script setup>
import { ref } from "vue";

const form = ref({ ...initialData });
const isDirty = ref(false);
const isSaving = ref(false);
let timer = null;

async function handleToggle(key, value) {
  form.value[key] = value;
  await api.saveSetting(key, value);
  toast.success("Setting updated");
}

function handleText(key, value) {
  form.value[key] = value;
  isDirty.value = true;
  clearTimeout(timer);
  timer = setTimeout(save, 3000);
}

function handleBlur() {
  if (isDirty.value) save();
}

async function save() {
  clearTimeout(timer);
  isSaving.value = true;
  await api.saveSettings(form.value);
  isDirty.value = false;
  isSaving.value = false;
}
</script>

<template>
  <form @submit.prevent="save">
    <Toggle
      label="Email notifications"
      :checked="form.emailNotifications"
      @change="v => handleToggle('emailNotifications', v)"
    />
    <TextInput
      label="Display name"
      :value="form.displayName"
      @input="v => handleText('displayName', v)"
      @blur="handleBlur"
    />
    <button type="submit" :disabled="!isDirty || isSaving">
      {{ isSaving ? "Saving..." : isDirty ? "Save changes" : "Saved" }}
    </button>
  </form>
</template>
```

## Key Points

- **Toggle switches** save immediately — they are imperative controls (like flipping a light switch)
- **Text inputs** use explicit save via button, optionally with 3-second debounced auto-save
- **Never mix** auto-save and explicit save on the same field type in one form
- **Always show the Save button** — even with auto-save, it provides psychological reassurance
- Button label reflects state: "Save changes" (dirty), "Saving..." (in flight), "Saved" (clean)
- Auto-save fires on **both** blur AND 3 seconds after last keystroke
- **Never auto-save** data with financial, security, or privacy implications
