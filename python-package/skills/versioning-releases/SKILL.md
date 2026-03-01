---
name: versioning-releases
description: "This skill should be used when the user is choosing a versioning scheme, writing a changelog, preparing a release, configuring Towncrier or python-semantic-release, planning deprecations, managing major version migrations, or setting up version single-source-of-truth. Covers SemVer, CalVer, PEP 440, Keep a Changelog, Towncrier, Conventional Commits, deprecation strategy, pre-release publishing, and release automation."
version: 1.0.0
---

# Follow SemVer Strictly and Automate Every Release

A version number is a contract with every user who pins against your package. Breaking that contract -- shipping a behavioral change in a PATCH bump, removing a function without a deprecation cycle, or publishing a non-PEP-440 tag -- erodes trust and causes silent failures across the dependency graph. The best Python packages (Pydantic, pytest, Django) treat versioning as seriously as they treat their API surface.

Pydantic's v1-to-v2 migration is the most instructive case study: systematic renaming with a `model_` prefix, a compatibility namespace (`pydantic.v1`), an automated codemod (`bump-pydantic`), and a 12-month support window for v1. That level of discipline is what users expect from a well-maintained package.

## SemVer Decision Guide

Use `MAJOR.MINOR.PATCH` for every Python library. Increment the correct segment based on what changed, not how much code was touched.

| Change Type | Bump | Example |
|-------------|------|---------|
| Remove public function/class | **MAJOR** | Delete `Client.send()` |
| Change function signature (required args) | **MAJOR** | `def get(url)` becomes `def get(url, timeout)` |
| Change return type or default behavior | **MAJOR** | Return `dict` instead of `list` |
| Rename public attribute/method | **MAJOR** | `.json()` becomes `.model_dump()` |
| Drop Python version support | **MAJOR** | Drop Python 3.9 |
| Add new public function/class | **MINOR** | New `Client.stream()` method |
| Add optional parameter with default | **MINOR** | `def get(url, *, timeout=30)` |
| Deprecate without removing | **MINOR** | Add deprecation warning |
| Fix incorrect behavior | **PATCH** | Fix off-by-one in pagination |
| Internal refactor (no API change) | **PATCH** | Restructure `_internal/` |

**The hardest calls are behavioral changes.** If `parse("2024-01-01")` returned a `date` and now returns a `datetime`, the signature is identical but downstream code breaks. This is a MAJOR change.

### The 0.x Convention

SemVer allows anything to change at `0.y.z`. In practice, treat MINOR as "breaking" and PATCH as "non-breaking" during 0.x development. Document this convention in your README. Graduate to 1.0 when the API is stable. FastAPI (0.115.x) and httpx (0.28.x) have stayed at 0.x for years -- if you have significant adoption, either go to 1.0 or explicitly document your 0.x contract.

### CalVer: When to Use It

Use CalVer only for tools where "backward compatibility" is meaningless or always maintained: formatters (Black `24.10.0`), packaging tools (pip `24.3.1`), platforms. For libraries with downstream dependents, always use SemVer.

## PEP 440 Compliance

PyPI and pip enforce PEP 440. Non-compliant version strings are rejected.

| Concept | SemVer Syntax | PEP 440 Syntax |
|---------|---------------|----------------|
| Pre-release alpha | `1.0.0-alpha.1` | `1.0.0a1` |
| Pre-release beta | `1.0.0-beta.2` | `1.0.0b2` |
| Release candidate | `1.0.0-rc.1` | `1.0.0rc1` |
| Post-release | Not defined | `1.0.0.post1` |
| Dev release | Not defined | `1.0.0.dev1` |

**Ordering:** `1.0.0.dev1 < 1.0.0a1 < 1.0.0b1 < 1.0.0rc1 < 1.0.0 < 1.0.0.post1`

Pre-releases are never installed by default. Users must pass `--pre` or pin an exact pre-release version. Always use PEP 440 format for tags: `v1.0.0a1`, not `v1.0.0-alpha.1`.

## Changelog: Keep a Changelog + Towncrier

Maintain a `CHANGELOG.md` following the Keep a Changelog format. Group entries by type, write from the user's perspective, and link each version to its diff.

| Section | When to Use | SemVer Signal |
|---------|------------|---------------|
| **Added** | New features | MINOR |
| **Changed** | Changes to existing functionality | MINOR or MAJOR |
| **Deprecated** | Features marked for future removal | MINOR |
| **Removed** | Features removed | MAJOR |
| **Fixed** | Bug fixes | PATCH |
| **Security** | Vulnerability fixes | PATCH |

| Bad Entry | Good Entry |
|-----------|------------|
| "Refactored internal connection pooling module" | "Fixed connection pool not releasing connections on timeout" |
| "Updated CI matrix" | *(Do not include -- not user-facing)* |

**Use Towncrier for multi-contributor projects.** Each PR adds a news fragment (`changes/423.bugfix.md`), CI enforces fragment presence, and `towncrier build` compiles them at release time. No merge conflicts on the changelog. Used by pip, pytest, attrs, Twisted.

## Version Single Source of Truth

Define the version in exactly one place. Prefer git-tag-derived versioning for open source.

| Scenario | Approach |
|----------|----------|
| Open source library | **hatch-vcs** or **setuptools-scm** (git tag as source, generates `_version.py`) |
| Internal/private package | Static version in `pyproject.toml` |
| Simple script/tool | `__version__` in source |

For runtime access, import from the generated `_version.py` file (see `project-structure` skill for the full rationale on why `_version.py` is preferred over `importlib.metadata.version()`).

## Deprecation Strategy

Never remove a public API without at least one release cycle of deprecation warnings. Include the removal version, the alternative, and a migration link in every warning message.

```python
warnings.warn(
    "old_function() is deprecated since v2.0 and will be removed in v3.0. "
    "Use new_function() instead. "
    "See https://mylib.dev/migration for details.",
    DeprecationWarning,
    stacklevel=2,  # CRITICAL: points warning to the caller's code
)
```

**Always use `stacklevel=2`.** Without it, the warning points to the line inside your library, not the user's code that called the deprecated function. For wrapped or decorated functions, use `stacklevel=3` or higher.

| User Base | Minimum Deprecation Period |
|-----------|--------------------------|
| Small (< 1K downloads/month) | 1 minor version (3+ months) |
| Medium (1K-100K downloads/month) | 2 minor versions (6+ months) |
| Large (100K+ downloads/month) | 1 full major version (12+ months) |

Test that deprecation warnings fire correctly with `pytest.warns(DeprecationWarning, match=...)` and that deprecated functions still work until removal.

## Release Process

Follow this end-to-end workflow for every release:

1. Compile changelog fragments: `towncrier build --version 2.1.0`
2. Tag the release: `git tag v2.1.0 && git push origin main --tags`
3. Create a GitHub Release from the tag
4. CI builds sdist + wheel on the `release` event
5. Publish to PyPI via trusted publishing (OIDC, no API tokens)

For major versions, publish pre-releases first: `v2.0.0a1` (alpha) then `v2.0.0b1` (beta) then `v2.0.0rc1` (release candidate) then `v2.0.0` (stable). Allow 2-4 weeks between stages for ecosystem testing. Pydantic v2 used a 2-month pre-release window.

## Reference Configuration

```toml
# pyproject.toml -- Towncrier configuration
[tool.towncrier]
package = "my_package"
directory = "changes"
filename = "CHANGELOG.md"
title_format = "## [{version}] - {project_date}"
issue_format = "[#{issue}](https://github.com/org/repo/issues/{issue})"
underlines = ["", "", ""]

[[tool.towncrier.type]]
directory = "feature"
name = "Added"
showcontent = true

[[tool.towncrier.type]]
directory = "bugfix"
name = "Fixed"
showcontent = true

[[tool.towncrier.type]]
directory = "deprecation"
name = "Deprecated"
showcontent = true

[[tool.towncrier.type]]
directory = "removal"
name = "Removed"
showcontent = true

[[tool.towncrier.type]]
directory = "change"
name = "Changed"
showcontent = true

[[tool.towncrier.type]]
directory = "security"
name = "Security"
showcontent = true
```

## Review Checklist

When reviewing code for versioning, releases, and changelogs:

- [ ] Version follows SemVer (`MAJOR.MINOR.PATCH`) with correct segment bumped for the change type
- [ ] All version strings comply with PEP 440 (use `1.0.0a1`, not `1.0.0-alpha.1`)
- [ ] Version is derived from a single source of truth (git tag via hatch-vcs/setuptools-scm generating `_version.py`, or static in pyproject.toml)
- [ ] `CHANGELOG.md` follows Keep a Changelog format with entries grouped by Added/Changed/Deprecated/Removed/Fixed/Security
- [ ] Changelog entries are written from the user's perspective, not the developer's
- [ ] Every PR includes a Towncrier news fragment (or equivalent) for user-facing changes
- [ ] Deprecation warnings use `warnings.warn()` with `DeprecationWarning`, `stacklevel=2`, the removal version, and the alternative
- [ ] Deprecated functions are tested to verify both the warning and continued functionality
- [ ] No public API is removed without at least one release cycle of deprecation warnings
- [ ] Git tags use the `v` prefix (`v2.1.0`) and PEP 440 format for pre-releases (`v2.0.0a1`)
- [ ] Major version releases are preceded by alpha/beta/RC pre-releases on PyPI
- [ ] CI publishes via trusted publishing (OIDC) on the GitHub Release event
- [ ] Migration guides exist for every breaking change, mapping old API to new equivalents
