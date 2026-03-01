---
name: documentation
description: "This skill should be used when the user is setting up MkDocs Material, configuring mkdocstrings, writing docstrings, generating API reference pages, structuring documentation with the Diataxis framework, deploying docs to GitHub Pages or ReadTheDocs, or writing a README. Covers mkdocs.yml configuration, Griffe, Google-style docstrings, versioned docs with mike, code example testing, nav structure."
version: 1.0.0
---

# Structure Documentation with MkDocs Material and the Diataxis Framework

Documentation fails not from bad writing but from mixing content types. A tutorial that stops to list every parameter loses the learner. A reference page with step-by-step instructions becomes unusable for lookups. The Diataxis framework separates tutorials, how-to guides, reference, and explanation into distinct pages -- and MkDocs Material is the tool to build them. FastAPI, Pydantic, httpx, Rich, and Polars all use MkDocs Material. Sphinx remains appropriate for existing rST codebases and scientific Python, but MkDocs Material is the default for new packages.

## MkDocs Material vs Sphinx

| Aspect | MkDocs Material | Sphinx |
|--------|----------------|--------|
| Markup | Markdown (+ PyMdown extensions) | reStructuredText (+ MyST for Markdown) |
| Learning curve | Low -- Markdown is universal | Medium-High -- rST is niche |
| API autodoc | mkdocstrings + Griffe (static, no imports) | autodoc (import-based, mature) |
| Build speed | Fast (seconds) | Slower, especially with autodoc |
| Theme | Excellent out of box, dark mode | Requires furo or pydata-sphinx-theme |
| New project adoption | Dominant since 2023 | Declining for new projects |

**Use Sphinx when:** existing large rST docs, scientific Python ecosystem (intersphinx), PDF requirements. **Use MkDocs Material for everything else.**

## The Diataxis Framework

Organize all documentation into exactly four types:

| Type | Orientation | Rule | Example |
|------|------------|------|---------|
| **Tutorial** | Learning | Guide through steps to a working result. No choices, no alternatives. | "Build your first API with MyLibrary" |
| **How-To Guide** | Task | Solve a specific problem. Assume basics known. | "How to configure authentication" |
| **Reference** | Information | Accurate, complete API docs. Organized by code structure. | "Client class", "Configuration options" |
| **Explanation** | Understanding | Discuss trade-offs, design decisions, concepts. | "Why we chose async over sync" |

**Never mix types on a single page.** A tutorial with a 20-row parameter table serves nobody. A reference page with step-by-step prose is unusable for lookups.

## Documentation Structure

```
docs/
  index.md                        # Landing page: what, why, install
  getting-started/
    installation.md               # pip/uv install, extras, requirements
    quickstart.md                 # TUTORIAL: minimal working example
  tutorials/
    first-steps.md                # TUTORIAL: beginner walkthrough
  guide/                          # HOW-TO GUIDES
    authentication.md
    error-handling.md
    async-usage.md
    testing.md
  concepts/                       # EXPLANATION
    architecture.md
    design-decisions.md
  reference/                      # REFERENCE (auto-generated)
    SUMMARY.md
  changelog.md
  contributing.md
```

**Navigation principles:** Progressive disclosure -- homepage answers "what is this?", quickstart shows basic usage in 30 seconds. No more than 2 levels of nesting. Separate "getting started" (tutorial for first-time users) from "guide" (how-to for returning users). Put API reference last in nav.

### Versioned Documentation

Use `mike` for versioned docs deployed to GitHub Pages. Each release gets its own version; `latest` always points to the current stable release. Add `mike` to your docs dependency group and deploy via CI:

```bash
mike deploy --push --update-aliases 1.0 latest
```

### Deployment

| Platform | When | Setup |
|----------|------|-------|
| **GitHub Pages** | Open-source packages, free hosting | `mkdocs gh-deploy` or `mike` for versioning |
| **ReadTheDocs** | Existing FOSS projects, PR previews, search analytics | `.readthedocs.yaml` + webhook |

Default to GitHub Pages with `mike` for new packages. Use ReadTheDocs when you need PR preview builds or existing infrastructure.

## Docstring Conventions

Use Google style -- the community standard used by FastAPI, Pydantic, httpx, and Rich. Configure mkdocstrings with `docstring_style: google`.

| Bad Pattern | Good Pattern |
|-------------|-------------|
| `url (str): The URL to request.` | `url: The URL to request. May be absolute or relative to base_url.` |
| Duplicating type annotations in docstring | Types in signature, meaning and constraints in docstring |
| No docstring on public functions | Every public function, class, and module has a docstring |
| Docstring says what the code does line-by-line | Docstring says what it means, valid values, and edge cases |

```python
def fetch_users(
    client: HttpClient,
    *,
    limit: int = 100,
    offset: int = 0,
) -> list[User]:
    """Fetch a paginated list of users from the API.

    Retrieves users from the `/users` endpoint with pagination.
    Results are ordered by creation date, newest first.

    Args:
        client: An authenticated HTTP client instance.
        limit: Maximum number of users to return. Must be
            between 1 and 1000.
        offset: Number of users to skip for pagination.

    Returns:
        A list of User objects. Empty list if no users match.

    Raises:
        AuthenticationError: If the client credentials are invalid.
    """
```

## API Reference Generation

For packages with 10+ public modules, auto-generate reference pages using `mkdocs-gen-files`. Create `scripts/gen_ref_pages.py` that iterates `src/**/*.py`, skips private modules (`_`-prefixed), writes a `::: module.path` directive per module into `reference/`, and generates a `SUMMARY.md` for literate-nav. Enable the `gen-files`, `literate-nav`, and `section-index` plugins in `mkdocs.yml`.

For small packages (fewer than 10 public objects), write manual reference pages:

```markdown
# Client

::: my_library.Client
    options:
      show_root_heading: false
      members: [get, post, put, delete, close]
```

## Testing Code Examples

Documentation examples that are not tested will drift. Use one of these approaches:

| Approach | When to Use |
|----------|-------------|
| `--doctest-modules` in pytest | Simple pure functions, data transformations |
| `pytest-examples` (Pydantic team) | Testing Markdown code blocks in docs/ |
| Standalone test files (FastAPI approach) | Complex examples with I/O, configuration, setup |

Add `addopts = ["--doctest-modules"]` and `doctest_optionflags = ["NORMALIZE_WHITESPACE", "ELLIPSIS"]` to `[tool.pytest.ini_options]` to test docstring examples automatically.

## README Best Practices

The README is a landing page, not a manual. Answer three questions in under 60 seconds: (1) What is this? (2) How do I install it? (3) How do I use it?

**Badges to include:** PyPI version, Python versions, CI status, docs status. **Badges to avoid:** download counts, "code style: black", coverage percentage.

The README doubles as the PyPI long description via `readme = "README.md"` in pyproject.toml. Validate rendering with `twine check dist/*`.

## Reference Configuration

### `mkdocs.yml`

```yaml
site_name: My Library
site_url: https://my-library.readthedocs.io
repo_url: https://github.com/org/my-library
repo_name: org/my-library
edit_uri: edit/main/docs/
strict: true

theme:
  name: material
  palette:
    - media: "(prefers-color-scheme: light)"
      scheme: default
      primary: indigo
      toggle: { icon: material/brightness-7, name: Switch to dark mode }
    - media: "(prefers-color-scheme: dark)"
      scheme: slate
      primary: indigo
      toggle: { icon: material/brightness-4, name: Switch to light mode }
  features:
    - content.code.copy
    - content.code.annotate
    - content.tabs.link
    - navigation.instant
    - navigation.tabs
    - navigation.tabs.sticky
    - navigation.sections
    - navigation.top
    - navigation.indexes
    - search.suggest
    - search.highlight

markdown_extensions:
  - toc: { permalink: true }
  - admonition
  - attr_list
  - pymdownx.highlight: { anchor_linenums: true }
  - pymdownx.superfences
  - pymdownx.tabbed: { alternate_style: true }
  - pymdownx.details
  - pymdownx.snippets: { check_paths: true }

plugins:
  - search
  - mkdocstrings:
      default_handler: python
      handlers:
        python:
          paths: [src]
          import:
            - https://docs.python.org/3/objects.inv
          options:
            show_source: true
            show_root_heading: true
            show_root_full_path: false
            docstring_style: google
            merge_init_into_class: true
            separate_signature: true
            signature_crossrefs: true
            unwrap_annotated: true
            members_order: source
            filters: ["!^_", "^__init__$"]

nav:
  - Home: index.md
  - Getting Started:
    - Installation: getting-started/installation.md
    - Quick Start: getting-started/quickstart.md
  - User Guide:
    - guide/index.md
    - Basic Usage: guide/basic-usage.md
    - Advanced: guide/advanced.md
  - API Reference: reference/
  - Contributing: contributing.md
  - Changelog: changelog.md
```

### Documentation dependencies in `pyproject.toml`

```toml
[dependency-groups]
docs = [
    "mkdocs-material>=9.5",
    "mkdocstrings[python]>=0.27",
    "mkdocs-gen-files>=0.5",
    "mkdocs-literate-nav>=0.6",
    "mkdocs-section-index>=0.3",
    "mike>=2.1",
]
```

## Review Checklist

When reviewing documentation setup and content:

- [ ] MkDocs Material configured with `strict: true` to fail on warnings
- [ ] mkdocstrings configured with `docstring_style: google` and `merge_init_into_class: true`
- [ ] Every public function, class, and module has a Google-style docstring
- [ ] Docstrings describe meaning and constraints, not type annotations already in signatures
- [ ] Documentation follows Diataxis: tutorials, how-to guides, reference, and explanation are on separate pages
- [ ] Navigation uses progressive disclosure with no more than 2 levels of nesting
- [ ] API reference auto-generated via `mkdocs-gen-files` for large packages, or manual pages for small ones
- [ ] Code examples in docs are tested in CI (doctest, pytest-examples, or standalone test files)
- [ ] README answers what/install/quickstart in under 60 seconds
- [ ] README includes badges for PyPI version, Python versions, CI status, and docs status
- [ ] Every docs page is listed in `mkdocs.yml` nav -- no orphaned pages
- [ ] Versioned docs configured with `mike` for multi-version hosting
- [ ] Deployment target configured (GitHub Pages with `mike`, or ReadTheDocs with `.readthedocs.yaml`)
- [ ] `docs` dependency group declared in `pyproject.toml` with pinned minimum versions (includes `mike`)
