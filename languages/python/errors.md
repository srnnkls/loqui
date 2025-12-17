---
paths: "**/*.py, **/pyproject.toml"
---

# Python Errors - Imperative Skill

**When to invoke**: Designing error handling, exception hierarchies, error propagation.

---

## Core Commands

### Exceptions are the Default

**USE exceptions by default. Result types are for specific scenarios only.**

```python
# ✓ CORRECT: Exception hierarchy for domain errors
class ConfigError(Exception):
    """Base for configuration errors."""
    def __init__(self, message: str, *, path: Path | None = None):
        super().__init__(message)
        self.message = message
        self.path = path

class MissingFieldError(ConfigError):
    """Raised when required fields are missing."""
    def __init__(self, fields: list[str], *, path: Path | None = None):
        super().__init__(f"Missing required fields: {fields}", path=path)
        self.fields = fields

def parse_config(path: Path) -> Config:
    """Parse configuration file. Raises ConfigError on invalid input."""
    if not path.exists():
        raise ConfigError(f"Config not found: {path}", path=path)

    data = json.loads(path.read_text())  # May raise JSONDecodeError

    if missing := [f for f in REQUIRED_FIELDS if f not in data]:
        raise MissingFieldError(missing, path=path)

    return Config(**data)
```

### When to Catch vs Propagate

**Catch at application boundaries. Propagate in core logic.**

```python
# ✓ CORRECT: Catch at application boundaries
def api_handler(request: Request) -> Response:
    try:
        result = process_request(request)
        return Response(data=result)
    except ValidationError as e:
        return Response(error=str(e), status=400)
    except AuthenticationError as e:
        return Response(error=e.message, status=401)
    except Exception as e:
        logger.exception("Unexpected error")
        return Response(error="Internal error", status=500)

# ✓ CORRECT: Propagate in core logic
def process_request(request: Request) -> ProcessedData:
    # Let exceptions bubble up to boundary
    user = authenticate(request.token)  # May raise AuthenticationError
    data = validate_payload(request.body)  # May raise ValidationError
    return transform(user, data)
```

**DON'T catch and re-wrap without adding context.**

```python
# ✘ WRONG: Catching and re-wrapping without value
def process_request(request: Request) -> ProcessedData:
    try:
        user = authenticate(request.token)
    except AuthenticationError as e:
        raise ProcessingError(f"Auth failed: {e}") from e  # Just noise
```

### Result Types: ONLY for Specific Scenarios

**Result types are appropriate for TWO scenarios ONLY:**

1. **Async task coordination**: Collect all results (successes and failures) without canceling
2. **Batching validation errors**: Accumulate multiple errors to show user at once

```python
@dataclass(frozen=True, kw_only=True)
class Success[T]:
    value: T

@dataclass(frozen=True, kw_only=True)
class Failure[E]:
    error: E

type Result[T, E] = Success[T] | Failure[E]

# ✓ Scenario 1: Async task coordination
async def fetch_with_result(url: str) -> Result[Response, Exception]:
    """Wrapper that captures exceptions as Result."""
    try:
        return Success(value=await fetch(url))
    except Exception as e:
        return Failure(error=e)

async def fetch_all(urls: list[str]) -> list[Result[Response, Exception]]:
    """Fetch all URLs, collecting both successes and failures."""
    async with asyncio.TaskGroup() as group:
        tasks = [group.create_task(fetch_with_result(url)) for url in urls]
    return [task.result() for task in tasks]

# ✓ Scenario 2: Batching validation errors
def validate_user_form(data: dict[str, Any]) -> Result[User, list[str]]:
    """Collect all validation errors instead of failing on first."""
    errors = []

    if not data.get("email") or "@" not in data["email"]:
        errors.append("Invalid email format")

    if not data.get("age") or not isinstance(data["age"], int):
        errors.append("Age must be an integer")

    if data.get("age", 0) < 18:
        errors.append("Must be 18 or older")

    if errors:
        return Failure(error=errors)

    return Success(value=User(email=data["email"], age=data["age"]))
```

**DON'T use Result types for general error handling.**

### Trustful Delegation

**Validate YOUR invariants, not theirs. DON'T duplicate validation that dependencies already do.**

```python
# ✓ CORRECT: Trust the dependency's API
def serialize_features(features):
    # getml_io.serialize_features handles path validation and creation
    return getml_io.serialize_features(
        features,
        path=get_target_storage_directory()
    )

# ✘ WRONG: Duplicating validation that getml_io already does
def serialize_features(features):
    storage_path = get_target_storage_directory()

    # Unnecessary: reimplementing serialize_features' internal logic
    if not storage_path.exists():
        storage_path.mkdir(parents=True)

    return getml_io.serialize_features(features, path=storage_path)
```

**Validate YOUR invariants only:**

```python
# ✓ CORRECT: Validate YOUR invariant (normalized absolute path)
def save_normalized_path(raw_path: str) -> None:
    """Your contract: must pass normalized absolute path."""
    # Validate YOUR invariant
    normalized = Path(raw_path).resolve()

    # Trust storage.save to handle its own concerns
    storage.save(normalized)
```

---

## Commands Summary

- **DO** use exceptions by default
- **DO** create exception hierarchies for domain errors
- **DO** catch at application boundaries
- **DO** propagate in core logic (let exceptions bubble)
- **DO** use Result types ONLY for: (1) async task coordination, (2) batching validation errors
- **DO** validate YOUR invariants, trust dependencies for theirs
- **DON'T** catch and re-wrap without adding context
- **DON'T** use Result types for general error handling
- **DON'T** duplicate validation that dependencies already do
- **NEVER** use Result types as default (Python isn't Rust)

---

## Related Skills

- **python-async-io**: Result types for async error coordination
- **python-domain-types**: Parse-don't-validate at boundaries

## Supporting Documentation

- `patterns.md`: Exception hierarchies, Result type patterns, async error coordination
