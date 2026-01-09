---
paths: "**/*.py, **/pyproject.toml"
---

# Python Testing

Type-driven test architecture, fixtures, and test doubles.

## Core Principles

**NEVER use test classes.** Use module-level test functions only.

See [composition.md#only-create-classes-for-mutable-and-encapsulated-state](composition.md#only-create-classes-for-mutable-and-encapsulated-state) — test classes violate this principle since they use classes as namespaces, not for mutable and encapsulated state.

```python
# ✓ CORRECT: Module functions
def test_user_create(client: TestClient):
    ...

# ✘ WRONG: Test class
class TestUser:
    def test_create(self, client):
        ...
```

Group tests by **file name** (`test_user.py`), not by class.

---

Tests are first-class code. They follow the same standards as production:

| Production Principle | Testing Application |
|---------------------|---------------------|
| Composition-First | Fixtures compose via dependency injection |
| Type-Driven | Test cases as typed dataclasses, not tuples |
| Radical Explicitness | No hidden fixture setup; dependencies visible |
| Immutable by Default | Test data as frozen dataclasses |
| Parse-Don't-Validate | Test inputs validated at fixture boundaries |
| Protocols Over ABCs | Test doubles implement protocols structurally |

---

## Given / When / Then

**Structure tests as three distinct phases.**

```python
def test_user_registration(user_service: UserService, email_sender: FakeEmailSender):
    # given
    email = "alice@example.com"

    # when
    user = user_service.register(email)

    # then
    assert user.email == email
    assert email_sender.sent_to(email)
```

Phase comments are optional when structure is obvious from whitespace:

```python
def test_parse_tag(parser: TagParser):
    raw = '{"key": "env", "value": "prod"}'

    tag = parser.parse(raw)

    assert tag == Tag("env", "prod")
```

**Keep "when" to ONE action.** Multiple actions usually means multiple tests.

---

## Test Naming

**Name tests after the behavior they verify, not the method they call.**

```python
# ✓ CORRECT: Describes behavior
def test_expired_token_raises_authentication_error(): ...
def test_duplicate_email_rejected_on_registration(): ...
def test_empty_cart_returns_zero_total(): ...

# ✘ WRONG: Describes implementation
def test_validate_token(): ...
def test_register_user(): ...
def test_calculate_total(): ...
```

### Conventions

| Pattern | When to Use | Example |
|---------|-------------|---------|
| `test_<behavior>` | Default | `test_sort_preserves_length` |
| `test_<action>_<condition>` | Conditional behavior | `test_login_with_invalid_password` |
| `test_<action>_<expected>` | Expected outcome | `test_divide_by_zero_raises` |

**File naming:** `test_<module>.py` mirrors the module under test.

```
src/myproject/auth/tokens.py  →  tests/unit/auth/test_tokens.py
src/myproject/cart/pricing.py →  tests/unit/cart/test_pricing.py
```

---

## Testing Exceptions

**Use `pytest.raises` as a context manager with `match` for validation.**

```python
def test_negative_quantity_raises():
    with pytest.raises(ValueError, match="must be positive"):
        OrderLine(product_id=1, quantity=-5)
```

**Access the exception for detailed assertions:**

```python
def test_validation_error_contains_field():
    with pytest.raises(ValidationError, match="invalid email") as exc_info:
        validate_email("not-an-email")

    assert exc_info.value.field == "email"
    assert "not-an-email" in str(exc_info.value)
```

**For multiple exception types:**

```python
def test_parse_handles_malformed_input():
    with pytest.raises((ValueError, TypeError)):
        parse_config("{{invalid")
```

---

## Fixture Composition with DI

**Fixtures compose dependencies exactly like production code.**

```python
# ✓ CORRECT: Composable fixtures
@pytest.fixture
def storage_backend() -> StorageBackend:
    return InMemoryStorage()

@pytest.fixture
def llm() -> LLM:
    return MockLLM(responses=["test response"])

@pytest.fixture
def session(llm: LLM, storage_backend: StorageBackend) -> Session:
    """Dependencies explicit and injected via pytest."""
    return Session(llm=llm, storage_backend=storage_backend)

# ✘ WRONG: Hidden dependency creation
@pytest.fixture
def session() -> Session:
    llm = OpenAI(api_key=os.environ["API_KEY"])  # Hidden global state
    return Session(llm=llm)
```

---

## Type-Safe Parametrization

**Test cases are data - model them as typed dataclasses.**

```python
# ✓ CORRECT: Type-safe test cases
@dataclass(frozen=True)
class ParseTestCase:
    input: str
    expected: Tag
    description: str

PARSE_CASES = [
    ParseTestCase(
        input='{"key": "env", "value": "prod"}',
        expected=Tag("env", "prod"),
        description="dict format",
    ),
]

@pytest.mark.parametrize("case", PARSE_CASES, ids=lambda c: c.description)
def test_parse_tag(case: ParseTestCase):
    assert parse_tag(case.input) == case.expected

# ✘ WRONG: Untyped tuples
@pytest.mark.parametrize("input,expected", [
    ('{"key": "env"}', Tag("env", "prod")),
])
def test_parse_tag(input, expected):
    assert parse_tag(input) == expected
```

---

## Test Doubles and Architecture

**Needing many mocks often signals tight coupling.** Good architecture (ports & adapters, dependency injection) makes fakes natural and mocks unnecessary.

| Use Fakes | Use Mocks |
|-----------|-----------|
| Testing behavior across boundaries | Verifying specific call sequences |
| Dependency is slow/external | Testing precise failure modes |
| Tests should survive refactoring | Temporary scaffolding during TDD |

**Fakes test behavior; mocks test implementation.** If you're mocking internals, the boundary may be wrong.

### Protocol-Based Fakes

**Test doubles implement protocols structurally. No inheritance.**

```python
# ✓ CORRECT: Fake implements protocol
class FakeStorage:
    """Implements StorageBackend protocol structurally."""
    def __init__(self):
        self.data: dict[str, bytes] = {}
        self.save_calls: list[tuple[str, bytes]] = []

    def save(self, key: str, value: bytes) -> None:
        self.save_calls.append((key, value))
        self.data[key] = value

    def load(self, key: str) -> bytes | None:
        return self.data.get(key)

# ✘ WRONG: Using unittest.mock
storage = Mock(spec=StorageBackend)  # Untyped, error-prone
```

### When Mocks Are Appropriate

```python
from unittest.mock import create_autospec

@pytest.fixture
def notification_service() -> Mock:
    return create_autospec(NotificationService, instance=True)

@pytest.fixture
def handler(notification_service: Mock) -> EventHandler:
    return EventHandler(notification_service=notification_service)

def test_sends_notification(handler: EventHandler, notification_service: Mock):
    handler.process(Event(type="completed"))

    notification_service.send.assert_called_once_with(
        recipient="admin@example.com",
        message="Event processed",
    )
```

Use `unittest.mock` sparingly: for verifying interactions at true external boundaries (APIs, message queues) where call verification matters more than behavior. Prefer `create_autospec` over `Mock(spec=...)` for better type safety.

---

## Fixture Lifecycle

**Fixture lifecycle matches resource lifecycle.**

```python
# ✓ CORRECT: Explicit yield for cleanup
@pytest.fixture
def temp_config_file(tmp_path: Path) -> Iterator[Path]:
    config_path = tmp_path / "config.json"
    config_path.write_text('{"key": "value"}')
    yield config_path

@pytest.fixture(scope="session")
def database_connection() -> Iterator[Connection]:
    conn = create_test_database()
    yield conn
    conn.close()

# ✘ WRONG: Cleanup in test
def test_usage(container):
    # test logic
    container.cleanup()  # If test fails, cleanup doesn't run!
```

### Fixture Scoping

| Scope | Lifetime | Use For |
|-------|----------|---------|
| `function` (default) | One test | Mutable state, test isolation |
| `class` | All tests in class | Shared setup for related tests (rare — prefer module) |
| `module` | All tests in file | Expensive setup shared within a test file |
| `package` | All tests in package | Shared across `tests/unit/` subdirectory |
| `session` | Entire test run | Database connections, Docker containers |

**Default to `function` scope.** Only broaden when:
1. Setup is expensive (>100ms) AND
2. The fixture is truly stateless or properly reset between tests

```python
# ✓ CORRECT: Session scope for expensive, stateless resource
@pytest.fixture(scope="session")
def docker_postgres() -> Iterator[str]:
    container = start_postgres_container()
    yield container.connection_string
    container.stop()

# ✓ CORRECT: Module scope with per-test reset
@pytest.fixture(scope="module")
def database(docker_postgres: str) -> Iterator[Database]:
    db = Database(docker_postgres)
    yield db
    db.close()

@pytest.fixture
def clean_database(database: Database) -> Iterator[Database]:
    yield database
    database.truncate_all()  # Reset between tests
```

---

## Async Testing

```python
@pytest.fixture
async def async_client() -> AsyncIterator[AsyncClient]:
    client = AsyncClient()
    yield client
    await client.close()

@pytest.mark.asyncio
async def test_fetch_concurrent():
    results = await fetch_all(["url1", "url2"])
    assert len(results) == 2
```

---

## Property-Based Testing

**Use Hypothesis for invariant validation and edge case discovery.**

See [hypothesis.md](hypothesis.md) for comprehensive patterns.

```python
from hypothesis import given, strategies as st

@given(st.lists(st.integers()))
def test_sort_preserves_length(xs: list[int]):
    assert len(sorted(xs)) == len(xs)

@given(st.lists(st.integers(), min_size=1))
def test_sort_first_is_minimum(xs: list[int]):
    assert sorted(xs)[0] == min(xs)
```

**Key rules:**
- Test properties (invariants), not specific input/output pairs
- Combine with fixtures: Hypothesis generates data, fixtures provide dependencies
- NEVER use `random` in hypothesis tests — let Hypothesis control randomness

---

## Snapshot Testing

**Use snapshots for complex outputs where manual assertions are impractical.**

```bash
pip install syrupy
```

```python
def test_report_generation(snapshot):
    report = generate_quarterly_report(Q3_2024_DATA)
    assert report == snapshot

def test_api_response_format(snapshot):
    response = client.get("/users/1")
    assert response.json() == snapshot
```

### When to Use Snapshots

| Good Fit | Poor Fit |
|----------|----------|
| Serialization output (JSON, HTML, XML) | Simple values with obvious assertions |
| Complex nested structures | Frequently changing outputs |
| Regression testing existing behavior | New code (write explicit assertions first) |
| Generated code / templates | Timestamps, random IDs (non-deterministic) |

### Avoiding Brittle Snapshots

```python
# ✘ WRONG: Snapshot includes volatile fields
def test_user_response(snapshot):
    response = client.get("/users/1")
    assert response.json() == snapshot  # Fails when created_at changes

# ✓ CORRECT: Exclude volatile fields
def test_user_response(snapshot):
    response = client.get("/users/1")
    data = response.json()
    del data["created_at"]
    del data["updated_at"]
    assert data == snapshot
```

**Prefer explicit assertions for core behavior.** Snapshots complement — not replace — targeted tests.

**In CI, fail on mismatches — never auto-update:**

```bash
pytest --snapshot-warn-unused  # Fail if snapshots aren't verified
```

Review snapshot updates carefully in PRs. It's easy to `--snapshot-update` without noticing unintended changes.

---

## Test Organization

```
tests/
├── unit/
│   ├── chat/
│   │   ├── test_messages.py      # Mirrors src/myproject/chat/
│   │   └── test_session.py
│   └── storage/
│       └── test_backends.py
├── integration/
│   └── test_chat_flow.py
└── conftest.py                    # Shared fixtures
```

### conftest.py Organization

**Fixture visibility follows directory hierarchy.** Place fixtures at the narrowest scope where they're needed.

```
tests/
├── conftest.py              # Truly shared: test client, database connection
├── unit/
│   ├── conftest.py          # Unit-test fakes: FakeStorage, MockLLM
│   └── chat/
│       └── conftest.py      # Chat-specific: sample messages, chat fixtures
└── integration/
    └── conftest.py          # Integration: real database, external services
```

| Location | Contains |
|----------|----------|
| `tests/conftest.py` | Fixtures used across unit AND integration |
| `tests/unit/conftest.py` | Fakes, in-memory implementations |
| `tests/integration/conftest.py` | Real connections, Docker containers |
| `tests/<feature>/conftest.py` | Domain-specific test data |

**Signs you need to split:**
- conftest.py exceeds ~200 lines
- Fixtures have unrelated concerns (auth fixtures mixed with payment fixtures)
- Import errors from fixtures not needed in certain test subsets

```python
# tests/conftest.py — shared utilities only
@pytest.fixture(scope="session")
def docker_services():
    ...

# tests/unit/conftest.py — fakes for isolation
@pytest.fixture
def fake_storage() -> FakeStorage:
    return FakeStorage()

# tests/integration/conftest.py — real implementations
@pytest.fixture
def database(docker_services) -> Iterator[Database]:
    ...
```

---

## Anti-Patterns: What NOT to Test

### Don't Test Your Dependencies

```python
# ✘ WRONG: Testing dataclass infrastructure
def test_frozen_dataclass_is_immutable():
    obj = MyFrozenClass(value=42)
    with pytest.raises(FrozenInstanceError):
        obj.value = 100  # Tests Python, not your code

# ✓ CORRECT: Testing YOUR validation
def test_validation_rejects_negative():
    with pytest.raises(ValueError, match="must be positive"):
        MyClass(value=-5)
```

### Test Semantics, Not Mechanics

```python
# ✘ WRONG: Testing internal structure
def test_ir_creates_join_node():
    assert isinstance(view.root, Join)  # Implementation detail

# ✓ CORRECT: Testing observable behavior
def test_join_produces_correct_result():
    result = execute(compile(view))
    assert len(result) == 3
```

### Don't Test Trivial Things

```python
# ✘ WRONG: Testing return type
def test_compile_returns_executable():
    exe = compile(view)
    assert isinstance(exe, Executable)  # Type checker does this

# ✓ CORRECT: Testing edge cases
def test_join_with_empty_table():
    result = join(empty_users, transactions)
    assert len(result) == 0
```

---

## Summary

- **DO** structure tests as Given / When / Then
- **DO** compose fixtures via DI like production code
- **DO** use frozen dataclasses for test cases
- **DO** implement protocols structurally for test doubles
- **DO** prefer fakes over mocks — mocks often signal tight coupling
- **DO** use yield fixtures for resource cleanup
- **DO** use Hypothesis for property-based testing of invariants
- **DON'T** test dataclass/pytest infrastructure
- **DON'T** test implementation details or internal structure
- **DON'T** use `unittest.mock.Mock` for typed protocols
- **NEVER** use `random` inside hypothesis tests

---

## Related

- [hypothesis.md](hypothesis.md) — Property-based testing patterns

## References

- [Python Testing with pytest](https://github.com/jashburn8020/python-testing-with-pytest) - Comprehensive pytest patterns
- [pytest Documentation](https://docs.pytest.org/) - Official reference
- [Hypothesis Documentation](https://hypothesis.readthedocs.io/) - Property-based testing
