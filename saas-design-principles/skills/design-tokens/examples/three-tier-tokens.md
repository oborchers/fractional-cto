# Three-Tier Token Architecture

Demonstrates the primitive → semantic → component token hierarchy with CSS custom properties.

## CSS Custom Properties

```css
/* ============================================
   TIER 1: Primitive Tokens (raw palette)
   Never reference these directly in components.
   ============================================ */
:root {
  --primitive-blue-50:  oklch(0.97 0.01 250);
  --primitive-blue-500: oklch(0.62 0.19 250);
  --primitive-blue-600: oklch(0.55 0.19 250);
  --primitive-gray-50:  oklch(0.98 0.00 0);
  --primitive-gray-100: oklch(0.95 0.00 0);
  --primitive-gray-200: oklch(0.90 0.00 0);
  --primitive-gray-700: oklch(0.40 0.00 0);
  --primitive-gray-900: oklch(0.20 0.00 0);
  --primitive-green-500: oklch(0.65 0.18 145);
  --primitive-red-500:   oklch(0.58 0.22 25);
  --primitive-yellow-500: oklch(0.80 0.15 85);
  --primitive-white: oklch(1.00 0.00 0);
  --primitive-black: oklch(0.00 0.00 0);
  --primitive-radius-sm: 4px;
  --primitive-radius-md: 8px;
  --primitive-spacing-xs: 4px;
  --primitive-spacing-sm: 8px;
  --primitive-spacing-md: 16px;
  --primitive-spacing-lg: 24px;
}

/* ============================================
   TIER 2: Semantic Tokens (purpose-driven)
   Named by PURPOSE, not appearance.
   These are what change between themes.
   ============================================ */
:root {
  /* Backgrounds */
  --color-bg-page:      var(--primitive-gray-50);
  --color-bg-surface:   var(--primitive-white);
  --color-bg-subtle:    var(--primitive-gray-100);
  --color-bg-muted:     var(--primitive-gray-200);

  /* Text */
  --color-text-primary:   var(--primitive-gray-900);
  --color-text-secondary: var(--primitive-gray-700);

  /* Actions */
  --color-action-primary:       var(--primitive-blue-500);
  --color-action-primary-hover: var(--primitive-blue-600);

  /* Status */
  --color-status-success: var(--primitive-green-500);
  --color-status-error:   var(--primitive-red-500);
  --color-status-warning: var(--primitive-yellow-500);
  --color-status-info:    var(--primitive-blue-500);

  /* Borders */
  --color-border-default: var(--primitive-gray-200);

  /* Spacing & Radius */
  --radius-default: var(--primitive-radius-md);
  --spacing-element: var(--primitive-spacing-sm);
  --spacing-section: var(--primitive-spacing-lg);
}

/* Dark mode — only semantic tokens change */
[data-theme="dark"] {
  --color-bg-page:      var(--primitive-gray-900);
  --color-bg-surface:   oklch(0.25 0.00 0);
  --color-bg-subtle:    oklch(0.22 0.00 0);
  --color-bg-muted:     oklch(0.30 0.00 0);

  --color-text-primary:   var(--primitive-gray-50);
  --color-text-secondary: var(--primitive-gray-200);

  --color-border-default: var(--primitive-gray-700);
}

/* ============================================
   TIER 3: Component Tokens (scoped)
   Reference semantic tokens.
   ============================================ */
:root {
  /* Button */
  --button-bg:           var(--color-action-primary);
  --button-bg-hover:     var(--color-action-primary-hover);
  --button-text:         var(--primitive-white);
  --button-radius:       var(--radius-default);
  --button-padding:      var(--spacing-element) var(--spacing-section);

  /* Card */
  --card-bg:             var(--color-bg-surface);
  --card-border:         var(--color-border-default);
  --card-radius:         var(--radius-default);

  /* Input */
  --input-bg:            var(--color-bg-surface);
  --input-border:        var(--color-border-default);
  --input-border-error:  var(--color-status-error);
  --input-border-valid:  var(--color-status-success);
  --input-text:          var(--color-text-primary);
}
```

## DTCG JSON Format

The W3C Design Tokens Community Group specification for cross-platform tooling:

```json
{
  "color": {
    "bg": {
      "page": {
        "$value": "{color.primitive.gray.50}",
        "$type": "color",
        "$description": "Main page background"
      },
      "surface": {
        "$value": "{color.primitive.white}",
        "$type": "color",
        "$description": "Elevated surface (cards, panels)"
      }
    },
    "action": {
      "primary": {
        "$value": "{color.primitive.blue.500}",
        "$type": "color",
        "$description": "Primary action buttons and links"
      }
    }
  }
}
```

## Key Points

- **Tier 1 (primitive)**: raw values — never reference directly in components
- **Tier 2 (semantic)**: purpose-named — these are what change between themes
- **Tier 3 (component)**: scoped — reference semantic tokens, keep component CSS simple
- Name by **purpose** (`--color-bg-surface`), not appearance (`--color-white`)
- Theme switching only touches Tier 2 — no component re-renders needed
- OKLCH color values provide perceptually uniform lightness across hues
