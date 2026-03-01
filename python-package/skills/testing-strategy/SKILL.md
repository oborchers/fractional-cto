---
name: testing-strategy
description: "This skill should be used when the user is configuring pytest, writing tests, setting up test fixtures, using parametrize, measuring code coverage, writing async tests with pytest-asyncio, using Hypothesis for property-based testing, choosing between nox and tox, building CI test matrices, setting up snapshot testing with syrupy, mocking with pytest-mock, or reviewing test organization. Covers pytest configuration, fixtures, coverage thresholds, async testing, Hypothesis profiles, CI matrices, and mocking best practices."
version: 1.0.0
---

# Configure pytest Strictly, Test Behavior Not Implementation

Every serious Python package -- attrs, httpx, Pydantic, FastAPI, Rich -- shares the same pytest configuration philosophy: strict by default, warnings as errors, no silent regressions. Without strict settings, typos in markers go unnoticed, deprecated upstream APIs break you without warning, and xfail tests silently pass for months hiding fixed bugs that never get their markers removed.

Testing strategy failures are quiet. Coverage regresses 1% at a time. A missing `--strict-markers` lets `@pytest.mark.solw` pass silently. `filterwarnings` without `"error"` lets upstream deprecation warnings accumulate until a dependency update breaks everything at once. The configuration below prevents all of this.

## Pytest Configuration

These settings are non-negotiable. They appear in every major package's `pyproject.toml`:

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
xfail_strict = true
filterwarnings = ["error"]
addopts = ["--strict-markers", "--strict-config", "-ra"]
markers = [
    "slow: marks tests as slow (deselect with '-m \"not slow\"')",
    "network: marks tests that require network access",
    "integration: marks integration tests requiring external services",
]
```

| Setting | What It Prevents |
|---------|-----------------|
| `testpaths = ["tests"]` | Scanning `src/`, `docs/`, `node_modules/` -- faster collection |
| `xfail_strict = true` | Unexpectedly passing xfail silently succeeding instead of failing |
| `filterwarnings = ["error"]` | Missing upstream `DeprecationWarning` until it breaks you |
| `--strict-markers` | Typos like `@pytest.mark.solw` passing without error |
| `--strict-config` | Typos like `filterwarning` (missing 's') being silently ignored |
| `-ra` | Forgetting to check which tests were skipped or xfailed |

Add targeted warning ignores only for known upstream issues you cannot control:

```toml
filterwarnings = [
    "error",
    "ignore::DeprecationWarning:some_dependency.*",
]
```

## Test Organization

**Mirror the source directory** -- the `tests/` directory must mirror `src/my_package/` exactly, with the same subdirectories and a `test_`-prefixed file for every source module. This makes it obvious where tests live and immediately reveals untested modules. See the `project-structure` skill for the full directory mapping.

Start flat within that mirror. Refactor to additional directories (e.g., `tests/unit/`, `tests/integration/`) only when test count exceeds 500 or different test layers need different infrastructure.

| Structure | When | Run Subsets |
|-----------|------|-------------|
| **Flat mirror** (`tests/test_*.py` matching `src/`) | < 500 tests, same fixtures | `pytest -m "not slow"` |
| **Directories** (`tests/unit/`, `tests/integration/`) | > 500 tests, different infrastructure per layer | `pytest tests/unit/` |

### conftest.py rules

1. Fixtures only -- never put test functions in conftest.py
2. Fixtures flow downward to all tests in the directory and below
3. Past ~150 lines, extract into modules: `pytest_plugins = ["tests.fixtures.database"]`

## Fixtures

### Prefer factory fixtures

```python
# DO: Factory with sensible defaults
@pytest.fixture
def make_user():
    def _make_user(name="test_user", email="test@example.com", role="user"):
        return User(name=name, email=email, role=role)
    return _make_user

def test_admin_permissions(make_user):
    admin = make_user(role="admin")
    assert admin.can_delete(make_user())
```

| Good | Bad |
|------|-----|
| One factory fixture with parameters | Separate fixture per variant (`admin_user`, `inactive_user`) |
| Compose fixtures: `client(app(config))` | Monolithic fixture that sets up everything |
| Use built-ins: `tmp_path`, `capsys`, `monkeypatch` | Reinvent temporary directories or stdout capture |
| `autouse=True` only for leak prevention | `autouse=True` for convenience |

### Scope rules

A fixture can only depend on fixtures with equal or broader scope. Expensive resources (DB engines, HTTP servers) use `scope="session"`, cheap per-test resources (DB transactions, test clients) use default scope with rollback in teardown.

## Parametrize

Always use `ids` for readable test output. Include expected values in parameters -- never use conditionals inside parametrized tests.

```python
# DO: Expected value in parameters
@pytest.mark.parametrize(("fmt", "expected"), [
    pytest.param("json", '"name"', id="json_format"),
    pytest.param("xml", "<name>", id="xml_format"),
])
def test_export(fmt, expected):
    assert expected in export(data, fmt)
```

```python
# DON'T: Conditionals inside parametrized test
@pytest.mark.parametrize("fmt", ["json", "xml"])
def test_export(fmt):
    result = export(data, fmt)
    if fmt == "json": assert '"name"' in result    # Three tests pretending to be one
    elif fmt == "xml": assert "<name>" in result
```

Stack decorators for cartesian products:

```python
@pytest.mark.parametrize("method", ["GET", "POST", "PUT"])
@pytest.mark.parametrize("auth", ["token", "api_key"])
def test_endpoint(method, auth):  # 3 x 2 = 6 tests
    ...
```

## Coverage

```toml
[tool.coverage.run]
source_pkgs = ["my_library"]
branch = true
parallel = true

[tool.coverage.report]
show_missing = true
fail_under = 85
exclude_also = [
    "if TYPE_CHECKING:",
    "@overload",
    "raise NotImplementedError",
    "assert_never",
    "\\.\\.\\.",
]
```

| Decision | Recommendation |
|----------|---------------|
| **Branch coverage** | Always enable (`branch = true`). Line coverage misses untested else paths. |
| **`fail_under`** | Start at 80, raise as coverage improves. Never lower it. Prevents silent regression. |
| **Target** | 80-85% for libraries, 85-90% for production APIs, never chase 100% |
| **Exclusions** | `TYPE_CHECKING` blocks, `@overload`, abstract methods, sentinel `...` |

Run locally: `pytest --cov=my_library --cov-report=term-missing`

## Async Testing

Enable pytest-asyncio auto mode to avoid decorating every async test:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```

Any `async def test_*` is automatically detected. For trio or anyio backends, use `asyncio_mode = "auto"` with the `anyio` pytest plugin instead.

For FastAPI, use `httpx.AsyncClient` with `ASGITransport`:

```python
@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac

async def test_create_item(client):
    response = await client.post("/items/", json={"name": "Foo"})
    assert response.status_code == 201
```

## Property-Based Testing with Hypothesis

Use Hypothesis for serialization round-trips, parsers, data transformations, and mathematical properties. Used by Pydantic, attrs, CPython, NumPy. Not worth it for simple CRUD or UI tests.

Register separate profiles for CI and local development in `conftest.py`:

```python
from hypothesis import settings, HealthCheck

settings.register_profile("ci", max_examples=1000, deadline=None,
                           suppress_health_check=[HealthCheck.too_slow])
settings.register_profile("dev", max_examples=50, deadline=400)
settings.load_profile(os.getenv("HYPOTHESIS_PROFILE", "default"))
```

Pin regression cases with `@example()` so they run on every invocation, not just when Hypothesis rediscovers them.

Add `.hypothesis/` to `.gitignore`.

## Mocking Best Practices

| Mock | Do Not Mock |
|------|-------------|
| External HTTP APIs, databases in unit tests | Your own pure functions |
| Time/dates (`time-machine`), third-party services | Data structures, simple transformations |
| Environment variables (`monkeypatch`) | The thing you are testing |

Patch where the name is used, not where it is defined: `mocker.patch("myapp.email.SMTP")` (correct) vs `mocker.patch("smtplib.SMTP")` (wrong). Prefer dependency injection over mocking -- pass `InMemoryDatabase()` instead of patching `PostgresDatabase`.

## CI Test Matrix

Full Python version matrix on Linux. Add macOS and Windows only if your package has platform-specific behavior — when needed, test oldest + newest Python versions only. See the `ci-cd` skill for the full GitHub Actions workflow and reusable workflow patterns.

```yaml
strategy:
  fail-fast: false
  matrix:
    python-version: ["3.10", "3.11", "3.12", "3.13"]
    os: [ubuntu-latest]
    include:
      # Add these only if your package has platform-specific behavior
      - { python-version: "3.10", os: macos-latest }
      - { python-version: "3.13", os: macos-latest }
      - { python-version: "3.10", os: windows-latest }
      - { python-version: "3.13", os: windows-latest }
```

Test with `uv sync --resolution lowest-direct` to verify minimum dependency bounds are correct.

## Reference Configuration

Combine the pytest and coverage sections from above into `pyproject.toml`:

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
xfail_strict = true
filterwarnings = ["error"]
addopts = ["--strict-markers", "--strict-config", "-ra"]
asyncio_mode = "auto"

[tool.coverage.run]
source_pkgs = ["my_library"]
branch = true
parallel = true

[tool.coverage.report]
show_missing = true
fail_under = 85
exclude_also = ["if TYPE_CHECKING:", "@overload", "raise NotImplementedError", "assert_never", "\\.\\.\\.",]
```

## Review Checklist

When reviewing tests and test configuration:

- [ ] `xfail_strict = true` is set -- unexpectedly passing xfail tests fail the build
- [ ] `filterwarnings = ["error"]` is set with only targeted, module-specific ignores
- [ ] `--strict-markers` and `--strict-config` are in `addopts`
- [ ] All custom markers are declared in the `markers` list
- [ ] Factory fixtures with defaults are used instead of one fixture per test variant
- [ ] `pytest.raises` always includes `match="..."` -- no bare exception catching
- [ ] Parametrized tests use `ids` for readable output and include expected values in parameters
- [ ] Coverage uses `branch = true` and `fail_under` is set (minimum 80)
- [ ] `TYPE_CHECKING` blocks and `@overload` are excluded from coverage
- [ ] Async tests use `asyncio_mode = "auto"` -- no manual decorators
- [ ] Mocks target external services only -- own code tested directly via dependency injection
- [ ] `fail_under` is treated as a ratchet -- raise it as coverage improves, never lower it
- [ ] Hypothesis profiles exist for CI (`max_examples=1000`) and dev (`max_examples=50`)
- [ ] Hypothesis regression cases are pinned with `@example()` decorators
- [ ] CI matrix tests all Python versions on Linux; oldest + newest on macOS/Windows only if platform-specific behavior exists
- [ ] Tests verify behavior and outcomes, not internal method call order
