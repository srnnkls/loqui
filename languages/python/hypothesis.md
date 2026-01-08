---
paths: "**/*.py, **/pyproject.toml"
---

# Property-Based Testing with Hypothesis

Strategies, composition, and pytest integration.

## Core Concept

**Property-based testing verifies invariants across generated inputs, not specific examples.**

Example-based tests check `f(specific_input) == expected_output`. Property-based tests check `for all valid x: property(f(x)) holds`.

```python
# Example-based: tests ONE case
def test_sort_example():
    assert sorted([3, 1, 2]) == [1, 2, 3]

# Property-based: tests the INVARIANT across many cases
@given(st.lists(st.integers()))
def test_sort_is_idempotent(xs: list[int]):
    assert sorted(sorted(xs)) == sorted(xs)
```

Hypothesis generates ~100 random inputs per test, shrinks failures to minimal reproductions, and remembers failing cases across runs.

---

## Basic Patterns

### The @given Decorator

```python
from hypothesis import given, strategies as st

@given(st.integers(), st.integers())
def test_addition_is_commutative(a: int, b: int):
    assert a + b == b + a

@given(st.text(min_size=1))
def test_string_reversal_is_involutory(s: str):
    assert s[::-1][::-1] == s
```

### Common Properties to Test

| Property | Description | Example |
|----------|-------------|---------|
| Idempotence | `f(f(x)) == f(x)` | `sorted(sorted(xs)) == sorted(xs)` |
| Roundtrip | `decode(encode(x)) == x` | `json.loads(json.dumps(obj)) == obj` |
| Invariant | Some condition always holds | `len(sorted(xs)) == len(xs)` |
| Commutativity | `f(a, b) == f(b, a)` | `a + b == b + a` |
| Associativity | `f(f(a, b), c) == f(a, f(b, c))` | `(a + b) + c == a + (b + c)` |

### Strategy Composition

```python
# Constrained integers
st.integers(min_value=0, max_value=100)

# Lists with size bounds
st.lists(st.integers(), min_size=1, max_size=10)

# Choice from options
st.sampled_from(["GET", "POST", "PUT", "DELETE"])

# Combining strategies
st.tuples(st.integers(), st.text())
st.dictionaries(st.text(min_size=1), st.integers())

# Filtering (use sparingly)
st.integers().filter(lambda x: x % 2 == 0)

# Mapping
st.integers(min_value=0).map(lambda x: x * 2)  # Even numbers
```

---

## Custom Strategies with @composite

**Use `@composite` when strategies depend on previously drawn values.**

```python
from hypothesis import strategies as st
from hypothesis.strategies import composite, DrawFn

@composite
def sorted_pair(draw: DrawFn) -> tuple[int, int]:
    a = draw(st.integers())
    b = draw(st.integers(min_value=a))
    return (a, b)

@given(sorted_pair())
def test_pair_is_sorted(pair: tuple[int, int]):
    a, b = pair
    assert a <= b
```

### Domain-Specific Strategies

```python
@composite
def valid_user(draw: DrawFn) -> User:
    return User(
        id=draw(st.integers(min_value=1)),
        email=draw(st.emails()),
        name=draw(st.text(min_size=1, max_size=100)),
        created_at=draw(st.datetimes()),
    )

@composite
def user_with_orders(draw: DrawFn) -> tuple[User, list[Order]]:
    user = draw(valid_user())
    orders = draw(st.lists(valid_order(user_id=user.id), max_size=5))
    return user, orders
```

### Registering Type Strategies

**Register strategies for domain types to use `st.from_type()` automatically.**

```python
# conftest.py
from hypothesis import strategies as st

st.register_type_strategy(
    UserId,
    st.integers(min_value=1).map(UserId),
)

st.register_type_strategy(
    Email,
    st.emails().map(Email),
)

st.register_type_strategy(
    User,
    st.builds(
        User,
        id=st.from_type(UserId),
        email=st.from_type(Email),
        name=st.text(min_size=1, max_size=100),
    ),
)
```

Now tests can use `st.from_type()` directly:

```python
@given(st.from_type(User))
def test_user_serialization_roundtrip(user: User):
    assert User.from_json(user.to_json()) == user

@given(st.lists(st.from_type(User)))
def test_bulk_operations(users: list[User]):
    ...
```

Hypothesis also infers strategies for `@dataclass` and `attrs` classes automatically when all fields have registered or inferrable types.

---

## Pytest Integration

### With Fixtures

**Hypothesis generates data; fixtures provide dependencies.**

```python
@pytest.fixture
def repository() -> UserRepository:
    return InMemoryUserRepository()

@given(st.emails())
def test_user_registration(repository: UserRepository, email: str):
    user = repository.create(email=email)
    assert repository.get(user.id).email == email
```

### With Parametrize

**Combine `@given` with `@pytest.mark.parametrize` for cross-product testing.**

```python
@pytest.mark.parametrize("method", ["GET", "POST", "PUT"])
@given(st.text())
def test_request_handling(method: str, body: str):
    request = Request(method=method, body=body)
    response = handler.handle(request)
    assert response.status_code in (200, 201, 400)
```

### Settings and Profiles

```python
from hypothesis import settings, Phase, Verbosity

# Per-test settings
@settings(max_examples=500, deadline=None)
@given(st.binary())
def test_extensive_binary_handling(data: bytes):
    ...

# Profile in conftest.py
settings.register_profile("ci", max_examples=1000)
settings.register_profile("dev", max_examples=50)
settings.load_profile(os.getenv("HYPOTHESIS_PROFILE", "dev"))
```

---

## Stateful Testing

**Test sequences of operations, not just individual calls.**

```python
from hypothesis.stateful import RuleBasedStateMachine, rule, invariant

class ShoppingCartMachine(RuleBasedStateMachine):
    def __init__(self):
        super().__init__()
        self.cart = ShoppingCart()
        self.expected_items: dict[str, int] = {}

    @rule(item=st.text(min_size=1), quantity=st.integers(min_value=1, max_value=10))
    def add_item(self, item: str, quantity: int):
        self.cart.add(item, quantity)
        self.expected_items[item] = self.expected_items.get(item, 0) + quantity

    @rule(item=st.text(min_size=1))
    def remove_item(self, item: str):
        if item in self.expected_items:
            self.cart.remove(item)
            del self.expected_items[item]

    @invariant()
    def items_match(self):
        assert dict(self.cart.items()) == self.expected_items

TestShoppingCart = ShoppingCartMachine.TestCase
```

Hypothesis generates sequences of `add_item` and `remove_item` calls, checking the invariant after each step.

---

## Performance Tuning

### Deadline Management

```python
# Disable deadline for slow operations
@settings(deadline=None)
@given(st.binary(min_size=1000, max_size=10000))
def test_compression_roundtrip(data: bytes):
    assert decompress(compress(data)) == data

# Or set explicit deadline
@settings(deadline=timedelta(milliseconds=500))
@given(...)
def test_with_deadline(...):
    ...
```

### Controlling Example Count

```python
# Fewer examples for slow tests
@settings(max_examples=20)
@given(...)
def test_slow_integration(...):
    ...

# More examples for critical paths
@settings(max_examples=1000)
@given(...)
def test_critical_invariant(...):
    ...
```

### Using assume() Sparingly

```python
# ✘ WRONG: Filtering discards too many examples
@given(st.integers(), st.integers())
def test_division(a: int, b: int):
    assume(b != 0)  # Most examples pass, but this is wasteful
    assert a / b * b == pytest.approx(a)

# ✓ CORRECT: Generate valid data directly
@given(st.integers(), st.integers().filter(lambda x: x != 0))
def test_division(a: int, b: int):
    assert a / b * b == pytest.approx(a)
```

---

## Integrations and Plugins

### NumPy

```python
from hypothesis.extra.numpy import arrays, array_shapes

@given(arrays(dtype=np.float64, shape=(3, 3)))
def test_matrix_transpose_involution(arr: np.ndarray):
    assert np.array_equal(arr.T.T, arr)

@given(arrays(dtype=np.int32, shape=array_shapes(min_dims=1, max_dims=3)))
def test_flatten_preserves_elements(arr: np.ndarray):
    assert arr.flatten().sum() == arr.sum()
```

### Pandas

```python
from hypothesis.extra.pandas import column, data_frames, series

@given(series(dtype=int))
def test_series_operations(s: pd.Series):
    assert len(s.dropna()) <= len(s)

@given(data_frames([
    column("id", dtype=int, unique=True),
    column("value", dtype=float),
]))
def test_dataframe_groupby(df: pd.DataFrame):
    ...
```

### JSON Schema (hypothesis-jsonschema)

```bash
pip install hypothesis-jsonschema
```

```python
from hypothesis_jsonschema import from_schema

user_schema = {
    "type": "object",
    "properties": {
        "name": {"type": "string", "minLength": 1},
        "age": {"type": "integer", "minimum": 0},
    },
    "required": ["name", "age"],
}

@given(from_schema(user_schema))
def test_user_validation(data: dict):
    user = User.from_dict(data)
    assert user.name
    assert user.age >= 0
```

### Other Useful Plugins

| Plugin | Purpose |
|--------|---------|
| `hypothesis-jsonschema` | Generate data from JSON Schema |
| `hypothesis-graphql` | Generate GraphQL queries |
| `hypothesis-csv` | Generate CSV data |
| `hypothesis-regex` | Better regex strategy |
| `hypothesis-fspaths` | File system paths |

---

## Common Strategies Reference

| Strategy | Generates | Example |
|----------|-----------|---------|
| `st.none()` | `None` | |
| `st.booleans()` | `True` / `False` | |
| `st.integers()` | Integers | `st.integers(min_value=0)` |
| `st.floats()` | Floats | `st.floats(allow_nan=False)` |
| `st.text()` | Unicode strings | `st.text(min_size=1, alphabet=st.characters(whitelist_categories=("L",)))` |
| `st.binary()` | Bytes | `st.binary(min_size=1)` |
| `st.lists()` | Lists | `st.lists(st.integers(), min_size=1)` |
| `st.dictionaries()` | Dicts | `st.dictionaries(st.text(), st.integers())` |
| `st.tuples()` | Tuples | `st.tuples(st.integers(), st.text())` |
| `st.one_of()` | Union | `st.one_of(st.none(), st.integers())` |
| `st.sampled_from()` | Choice | `st.sampled_from(["a", "b", "c"])` |
| `st.builds()` | Objects | `st.builds(User, id=st.integers(), name=st.text())` |
| `st.from_type()` | Type inference | `st.from_type(MyDataclass)` |
| `st.emails()` | Email addresses | |
| `st.datetimes()` | Datetime objects | `st.datetimes(min_value=datetime(2020, 1, 1))` |

---

## Anti-Patterns

### Using random in Tests

```python
# ✘ WRONG: Breaks shrinking and reproducibility
@given(st.integers())
def test_with_random(x: int):
    y = random.randint(0, 100)  # NEVER do this
    assert process(x, y) >= 0

# ✓ CORRECT: Let Hypothesis generate all randomness
@given(st.integers(), st.integers(min_value=0, max_value=100))
def test_without_random(x: int, y: int):
    assert process(x, y) >= 0
```

### Over-Filtering

```python
# ✘ WRONG: Rejects most generated examples
@given(st.text())
def test_parse_email(s: str):
    assume("@" in s and "." in s)  # Most strings fail this
    ...

# ✓ CORRECT: Use appropriate strategy
@given(st.emails())
def test_parse_email(email: str):
    ...
```

### Testing Implementation Instead of Properties

```python
# ✘ WRONG: Testing specific implementation detail
@given(st.lists(st.integers()))
def test_sort_uses_quicksort(xs: list[int]):
    # Checking internal algorithm, not behavior

# ✓ CORRECT: Testing observable properties
@given(st.lists(st.integers()))
def test_sort_produces_ordered_output(xs: list[int]):
    result = sorted(xs)
    assert all(result[i] <= result[i + 1] for i in range(len(result) - 1))
```

---

## Summary

- **DO** test properties and invariants, not specific examples
- **DO** use `@composite` for complex dependent data generation
- **DO** combine with fixtures for dependency injection
- **DO** configure profiles for CI vs local development
- **DON'T** use `random` — let Hypothesis control randomness
- **DON'T** over-filter with `assume()` — generate valid data directly
- **DON'T** test implementation details — test observable behavior

---

## Related

- [test.md](test.md) — General testing patterns

## References

- [Hypothesis Documentation](https://hypothesis.readthedocs.io/)
- [Choosing Properties](https://hypothesis.readthedocs.io/en/latest/data.html)
- [Stateful Testing](https://hypothesis.readthedocs.io/en/latest/stateful.html)
