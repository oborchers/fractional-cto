# Lossless Compression Techniques

Lossless transformations change document structure without altering semantics. Every transformation below preserves 100% of the information content.

## Transformation Catalog

### 1. Whitespace Normalization

**Rule:** Collapse multiple consecutive blank lines to a single blank line. Remove trailing whitespace from all lines. Standardize indentation to 2 spaces for nested lists.

**Before:**
```markdown
## Section A



Content here.



## Section B
```

**After:**
```markdown
## Section A

Content here.

## Section B
```

### 2. HTML Comment Removal

**Rule:** Remove all HTML comments. These are invisible to LLMs and waste tokens.

**Before:**
```markdown
<!-- TODO: Review this section -->
## API Configuration

<!-- Last updated: 2024-01-15 -->
Set the `API_KEY` environment variable.
<!-- Note: This uses v2 of the API -->
```

**After:**
```markdown
## API Configuration

Set the `API_KEY` environment variable.
```

### 3. Horizontal Rule Cleanup

**Rule:** Remove horizontal rules (`---`, `***`, `___`) that serve only as visual separators. Keep only those that denote semantic boundaries (e.g., frontmatter delimiters).

**Before:**
```markdown
## Authentication

Configure OAuth2 credentials.

---

## Authorization

Set role-based access.

---

## Rate Limiting
```

**After:**
```markdown
## Authentication

Configure OAuth2 credentials.

## Authorization

Set role-based access.

## Rate Limiting
```

### 4. Redundant Emphasis Reduction

**Rule:** When multiple emphasis mechanisms convey the same weight, keep the strongest single mechanism.

**Before:**
```markdown
**IMPORTANT:** ***NEVER*** expose API keys in client-side code!!!
```

**After:**
```markdown
**NEVER** expose API keys in client-side code.
```

### 5. Empty Section Removal

**Rule:** Remove sections that contain only a heading and no content, unless the heading is a placeholder for future content that other sections reference.

**Before:**
```markdown
## Deployment

## Configuration

Set `NODE_ENV=production` for production deployments.

## Monitoring
```

**After:**
```markdown
## Configuration

Set `NODE_ENV=production` for production deployments.
```

### 6. Table of Contents Removal

**Rule:** Remove auto-generated or manual table of contents sections. LLMs navigate by heading structure, not by TOC links.

**Before:**
```markdown
## Table of Contents

- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [API Reference](#api-reference)

## Installation
```

**After:**
```markdown
## Installation
```

### 7. Redundant Header Consolidation

**Rule:** When adjacent headers have no content between them and the child header could stand alone, remove the empty parent.

**Before:**
```markdown
## Database

### PostgreSQL Configuration

Set `DATABASE_URL` to your connection string.
```

If "Database" has no other children and no content of its own, collapse:

**After:**
```markdown
## PostgreSQL Configuration

Set `DATABASE_URL` to your connection string.
```

**Exception:** Keep parent headers when they have multiple children or when the hierarchy is semantically meaningful.

### 8. List Marker Standardization

**Rule:** Standardize all unordered list markers to `-`. Standardize nested indentation to 2 spaces. Remove excessive nesting where a flat list suffices.

**Before:**
```markdown
* Item one
  * Sub-item
    * Sub-sub-item that's really just a detail
+ Item two
  + Another sub-item
```

**After (when nesting is meaningful):**
```markdown
- Item one
  - Sub-item
    - Sub-sub-item that's really just a detail
- Item two
  - Another sub-item
```

**After (when nesting is cosmetic):**
```markdown
- Item one — sub-item, sub-sub-item detail
- Item two — another sub-item
```

### 9. Link Simplification

**Rule:** For LLM-facing documents, bare URLs and reference-style links are equivalent. Collapse reference-style links to inline when the reference is only used once.

**Before:**
```markdown
See the [documentation][docs] for details.

[docs]: https://example.com/docs
```

**After:**
```markdown
See the [documentation](https://example.com/docs) for details.
```

### 10. Code Block Language Tag Normalization

**Rule:** Remove language tags from code blocks when the language is obvious from context or when the block contains configuration/output rather than code.

**Before:**
````markdown
```text
ERROR: Connection refused
```

```plaintext
$ export API_KEY=xxx
```
````

**After:**
````markdown
```
ERROR: Connection refused
```

```
$ export API_KEY=xxx
```
````

## Application Order

Apply transformations in this order to avoid conflicts:

1. HTML comment removal
2. Whitespace normalization
3. Empty section removal
4. Table of contents removal
5. Horizontal rule cleanup
6. Redundant header consolidation
7. Redundant emphasis reduction
8. List marker standardization
9. Link simplification
10. Code block normalization

## What Lossless Mode Does NOT Change

- Heading text or hierarchy (only removes empty parents)
- Prose content or wording
- Code block contents
- Table data
- List item text (only markers and indentation)
- YAML frontmatter
- Any semantic content
