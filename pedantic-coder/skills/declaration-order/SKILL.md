---
name: declaration-order
description: "Use when organizing declarations within a source file, ordering class members or struct fields, structuring module exports in Python TypeScript or Go, reviewing files where constants are mixed with functions and classes in unpredictable order, reordering CRUD methods for consistency across service classes, placing private helper functions near their callers, or alphabetizing __all__ and export statements. Enforces a universal file shape (docstring, imports, constants, types, classes, functions, entry point), class member ordering (constants, constructor, public methods, private methods, static methods, special methods), alphabetized exports, and consistent CRUD method order across all service modules."
version: 1.0.0
---

# Declaration Order

Every file in a project follows the same shape. Every class follows the same member order. The reader learns the convention once and navigates by muscle memory.

## File-Level Order

Every file follows this top-to-bottom sequence. Absent items are skipped; the order of what remains does not change.

```
1. Module docstring / file header comment
2. Imports (per the import-discipline skill)
3. Constants / module-level configuration
4. Type definitions / interfaces / type aliases
5. Classes
6. Module-level functions
7. Main / entry point (if applicable)
```

## Class Member Order

```
1. Class-level constants / static properties
2. Constructor / __init__ / New
3. Public methods (grouped logically — CRUD together, domain actions together)
4. Private / internal methods
5. Static methods / class methods
6. Special / dunder methods (__str__, __repr__, __eq__)
```

**Logical grouping, not alphabetical:** CRUD methods in `create, get, list, update, delete` order. If a method has a private helper, the helper follows it immediately.

## Export Ordering

Alphabetize explicit exports (`__all__`, `export` statements). Exports are a lookup table — alphabetical order makes scanning efficient.

```python
__all__ = [
    "CreateUserRequest",
    "DeleteUserRequest",
    "UpdateUserRequest",
    "User",
    "UserResponse",
    "UserService",
]
```

## Helpers Near Callers

A private helper belongs directly below the function that calls it, not at the bottom of the file.

```python
# GOOD — helper follows its caller
def process_payment(order: Order) -> PaymentResult:
    validated = _validate_payment_details(order)
    ...

def _validate_payment_details(order: Order) -> bool:
    ...
```

Exception: shared utilities used by many functions belong in a separate utility module.

## Consistency Across Files

If `UserService` orders methods as `create, get, list, update, delete`, then `ProductService`, `OrderService`, and every other service uses the same order. Document the convention once in a style guide or `CLAUDE.md`.

## Complete File Examples

Full working examples for Python, TypeScript, and Go are in `examples/`:
- **`examples/file-structure.md`** — Complete file structures with correct declaration ordering, class member ordering, and consistent patterns across service modules

## Common Violations to Flag

- Constants scattered between functions instead of grouped after imports
- Types defined after the functions that reference them
- Constructor buried in the middle of a class
- Private helpers dumped at file bottom, far from their callers
- Inconsistent CRUD order across service classes
- Unalphabetized `__all__` or `export` statements

## Review Checklist

- [ ] File follows universal order: docstring, imports, constants, types, classes, functions, entry point
- [ ] Constants grouped at top after imports — not scattered between functions
- [ ] Type definitions appear before classes and functions that use them
- [ ] Class members ordered: constants, constructor, public, private, static, special
- [ ] Public methods grouped logically (CRUD together) — not alphabetically
- [ ] Private helpers placed directly after the public method that calls them
- [ ] Exports (`__all__`, `export` statements) alphabetized
- [ ] CRUD method order consistent across all service classes
- [ ] File shape consistent — any two files of the same type have the same structure
- [ ] Entry point / main function at the bottom
- [ ] Shared utilities in utility modules, not at bottom of unrelated files
