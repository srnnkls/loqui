---
paths: "**/*.py, **/pyproject.toml"
---

# Python Testing - Type-Driven Test Architecture

**When to invoke**: Writing tests, designing fixtures, creating test doubles.

---

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

## Protocol-Based Test Doubles

**Test doubles implement protocols structurally. No inheritance.**

```python
# ✓ CORRECT: Mock implements protocol
class MockStorage:
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

## Commands Summary

- **DO** compose fixtures via DI like production code
- **DO** use frozen dataclasses for test cases
- **DO** implement protocols structurally for test doubles
- **DO** use yield fixtures for resource cleanup
- **DO** test validation failures and edge cases
- **DO** use AAA pattern (Arrange-Act-Assert)
- **DON'T** test dataclass/pytest infrastructure
- **DON'T** test implementation details or internal structure
- **DON'T** use `unittest.mock.Mock` for typed protocols
- **DON'T** write obvious docstrings restating test names
- **NEVER** use `random` inside hypothesis tests

---

## References

- [Python Testing with pytest](https://github.com/jashburn8020/python-testing-with-pytest) - Comprehensive pytest patterns
- [pytest Documentation](https://docs.pytest.org/) - Official reference
