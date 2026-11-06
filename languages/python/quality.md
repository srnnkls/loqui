---
paths: "**/*.py, **/pyproject.toml"
---

# Python Quality

Naming, comments, documentation, logging, and anti-patterns.

## Core Commands

### The 5x Rule: Naming Over Comments

**Spend 5x more time on names than comments.**

```python
# ✘ Comment for bad names
result = [u.e for u in users if u.s == "active"]

# ✓ Names eliminate comment
active_user_emails = [user.email for user in users if user.status == "active"]
```

### Comments for WHY, Not WHAT

**Write comments ONLY for:** Non-obvious WHY, workarounds, performance choices, invariants

**DON'T write for:** WHAT code does, HOW it works, restating obvious

```python
# ✘ WRONG: Restates code
def get_user_by_id(user_id: int) -> User | None:
    """Get user by ID."""
    return db.query(User).filter(User.id == user_id).first()

# ✓ Self-documenting
def get_user_by_id(user_id: int) -> User | None:
    return db.query(User).filter(User.id == user_id).first()

# ✓ Explains WHY
def validate_age(age: int) -> None:
    # GDPR Article 8: reject under 16 to avoid consent flow complexity
    if age < 16:
        raise ValidationError("Must be 16 or older")
```

### NO Section Dividers - Split Into Modules

**Section dividers = file too large. Split it.**

```python
# ✘ WRONG: Section dividers
# ======== Data Models ========
class User: ...
# ======== Validation ========
def validate_user(user): ...

# ✓ Split into modules
# myapp/models.py
class User: ...
# myapp/validation.py
def validate_user(user): ...
```

**ASCII art dividers = immediate split signal.**

### Docstrings: Use Sparingly

**Write ONLY for:** Public APIs, complex behavior, critical context
**DON'T write for:** Self-explanatory signatures, internal functions, restating names

```python
# ✘ Restates signature
def create_user(email: str, age: int) -> User:
    """Create a user with email and age."""
    return User(email=email, age=age)

# ✓ Self-explanatory
def create_user(email: str, age: int) -> User:
    return User(email=email, age=age)

# ✓ Adds context
def retry_with_backoff(fn: Callable[[], T], backoff_base: float = 2.0) -> T:
    """Retry with exponential backoff.

    Note: backoff_base=2.0 means delays of 1s, 2s, 4s, ...
    """
    ...
```

### Logging: Module-Level Loggers

**Libraries NEVER configure root logger.**

```python
# ✓ Module-level logger
import logging
logger = logging.getLogger(__name__)

def process_data(data: Data) -> Result:
    logger.debug("Processing: %s", data.id)
    ...

# ✘ WRONG: Configuring root logger
logging.basicConfig(level=logging.INFO)  # FORBIDDEN in libraries
```

### Typing Hygiene

```python
# ALWAYS enable future annotations
from __future__ import annotations

def process(self, data: Data) -> Result:  # Forward references work
    ...
```

**Include `py.typed` marker:** Add empty `py.typed` file in package root.

**Google-style docstrings:**
```python
def fetch_user(user_id: str) -> User:
    """Fetch user from database.

    Args:
        user_id: Unique identifier.

    Returns:
        User object.

    Raises:
        UserNotFoundError: If not found.
    """
    ...
```

---

## Anti-Patterns Checklist

- ✘ Behavioral inheritance (except exceptions)
- ✘ Passing `dict[str, Any]` deep into application
- ✘ Global mutable state
- ✘ Dense `if/elif` chains (use `match/case`)
- ✘ Hidden dependencies (globals, singletons)
- ✘ Stringly-typed enums (`role: str` instead of `role: Literal[Role.USER]`)
- ✘ Mutable default arguments (`def foo(items=[]):`)
- ✘ Positional pattern matching (breaks on field changes)
- ✘ `@staticmethod` (use module functions)
- ✘ Classes as namespaces (use modules)
- ✘ Polluting domain with mixins
- ✘ Pydantic `Iterable[T]` (use `Sequence[T]`)
- ✘ Blocking I/O in async (`requests.get()`)
- ✘ Missing timeouts on async I/O
- ✘ `self.pending = []` (use `.clear()`)
- ✘ Comments that restate code
- ✘ Section divider comments (`# ====`)

---

## Summary

- **DO** spend 5x time on naming vs comments
- **DO** write comments for WHY, not WHAT
- **DO** split files when you need section dividers
- **DO** use docstrings only for public APIs and non-obvious behavior
- **DO** use module-level loggers (`logger = logging.getLogger(__name__)`)
- **DO** enable `from __future__ import annotations`
- **DO** include `py.typed` marker in packages
- **DON'T** write comments that restate code
- **DON'T** use section dividers (`# ====`) - split into modules
- **DON'T** write docstrings for self-explanatory signatures
- **NEVER** configure root logger in libraries
- **NEVER** compensate for bad names with comments

---

## Related

- **python-composition**: Classes vs modules (modules for namespacing)
- **python-modules**: When to split files (section dividers = split signal)

## Supporting Documentation

- `guidelines.md`: Detailed comments philosophy, docstrings, logging, typing hygiene
- `anti-patterns.md`: Comprehensive anti-patterns checklist with examples

## References

- [Python Patterns Guide](https://python-patterns.guide/) - Comprehensive Python patterns reference
