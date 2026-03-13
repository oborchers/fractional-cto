# Lossless Compression Example

## Before (CLAUDE.md excerpt — 287 tokens)

```markdown
# Project Guidelines


<!-- Last reviewed: 2024-06-15 -->

## Table of Contents

- [Development](#development)
- [Testing](#testing)
- [Deployment](#deployment)

---

## Development

### Local Setup

#### Prerequisites

Make sure you have the following installed:

* Node.js >= 18
  * npm >= 9
    * Or yarn >= 3
+ Docker Desktop

---

## Testing

### Unit Tests

Run unit tests with:

```bash
npm test
```

### Integration Tests

## Deployment

### Staging

Deploy to staging with:

```bash
npm run deploy:staging
```

### Production

**IMPORTANT:** ***ALWAYS*** run the full test suite before deploying to production!!!

```bash
npm run deploy:prod
```
```

## After (lossless — 171 tokens, 40% reduction)

```markdown
# Project Guidelines

## Development

### Local Setup

Prerequisites:

- Node.js >= 18
  - npm >= 9 or yarn >= 3
- Docker Desktop

## Testing

### Unit Tests

Run unit tests:

```
npm test
```

## Deployment

### Staging

```
npm run deploy:staging
```

### Production

**ALWAYS** run full test suite before deploying to production.

```
npm run deploy:prod
```
```

## What Changed

| Transformation | Count |
|---------------|-------|
| HTML comments removed | 1 |
| Blank lines collapsed | 4 |
| TOC removed | 1 |
| Horizontal rules removed | 2 |
| Empty section removed (Integration Tests) | 1 |
| List markers standardized | 4 |
| Redundant emphasis reduced | 1 |
| Code block language tags simplified | 3 |
| Empty parent header removed (Prerequisites) | 1 |

No semantic content was altered.
