---
paths: "**/*.py, **/pyproject.toml"
---

# Python Domain Types - Imperative Skill

**When to invoke**: Designing domain models, data structures, API contracts, or type definitions.

---

## Core Commands

### START with Types

**ALWAYS start by modeling your domain with types FIRST.**

- Types ARE the design, not documentation
- Even 50-line scripts benefit from explicit types over dicts
- Create your domain vocabulary as types before writing logic

### USE Value Objects (Frozen Dataclasses)

```python
from pydantic import Field
from pydantic.dataclasses import dataclass

@dataclass(frozen=True, kw_only=True)
class Measurement:
    value: float = Field(ge=0, description="Non-negative measurement")
    unit: str = Field(min_length=1, description="Unit of measurement")
```

**MUST use:**
- `frozen=True` for immutable value objects
- `kw_only=True` to enforce explicit construction
- `Field(description=...)` for API documentation
- Pydantic dataclasses at boundaries, plain frozen dataclasses internally

**NEVER pass `dict[str, Any]` into core logic.**

### PARSE Don't Validate

**Accept permissive input at boundaries, immediately parse to strict canonical types internally.**

```python
# DO: Parse many formats into one canonical type
def _parse_tag(tag: dict[str, str] | tuple[str, str, str] | Tag) -> Tag:
    match tag:
        case {"key": key, "value": value}:
            return Tag(key, value)
        case (key, value, color):
            return Tag(key, value, color=TagColor(color))
        case Tag() as tag:
            return tag

Tags = Annotated[
    set[Tag],
    BeforeValidator(_parse_tags),  # Accept list, set, dict, tuple
    PlainSerializer(_serialize_tags)  # Always output canonical form
]
```

**Core logic MUST work with guaranteed-valid, typed data only.**

### MAKE Illegal States Unrepresentable

**USE discriminated unions with Literal types:**

```python
@dataclass(frozen=True, kw_only=True)
class UserMessage:
    content: str
    role: Literal[Role.USER] = Role.USER

@dataclass(frozen=True, kw_only=True)
class AssistantMessage:
    content: str | None = None
    function_call: FunctionCall | None = None
    role: Literal[Role.ASSISTANT] = Role.ASSISTANT

# Discriminated union - type-safe, exhaustive
Message = Annotated[
    UserMessage | AssistantMessage | SystemMessage | FunctionMessage,
    Field(discriminator="role")
]
```

**NEVER use stringly-typed enums or runtime validation for structural variants.**

### USE Pydantic Field Constraints

**At boundaries:**
```python
@dataclass(frozen=True, kw_only=True)
class User:
    email: str = Field(pattern=r'^[^@]+@[^@]+\.[^@]+$')
    age: int = Field(ge=0, le=150)
```

**Internally (after parsing):**
```python
@dataclass(frozen=True, kw_only=True)
class User:
    email: str
    age: int
```

**USE Pydantic at boundaries. Plain dataclasses internally.**

### Type Alias Patterns

**Simple assignment (Python 3.12+):**

```python
# DO: Implicit type alias
FeatureDescriptions = dict[str, FeatureDescription]

# DON'T: Unnecessary TypeAlias import
from typing import TypeAlias
FeatureDescriptions: TypeAlias = dict[str, FeatureDescription]
```

### Generic Type-Safe Functions

**USE PEP 695 syntax (Python 3.12+):**

```python
type Result[T, E] = Success[T] | Failure[E]

def parse[T](data: str, parser: Callable[[str], T]) -> Result[T, ValueError]:
    try:
        return Success(parser(data))
    except ValueError as e:
        return Failure(e)
```

---

## Domain-Driven Design Through Types

- **Value Objects**: `@dataclass(frozen=True)` for immutable types
- **Ubiquitous Language**: Named types = explicit vocabulary
- **Invariants**: Parse-don't-validate + Pydantic constraints

**Progression**: Define value objects → Add methods → Extract shared behavior → Extract complex logic

---

## Commands Summary

- **DO** start with types to model your domain
- **DO** use `@dataclass(frozen=True, kw_only=True)` for value objects
- **DO** use Pydantic dataclasses at boundaries for validation
- **DO** use plain frozen dataclasses internally after parsing
- **DO** use discriminated unions with Literal types for variants
- **DO** use `Field()` for validation constraints and documentation
- **DO** make illegal states unrepresentable through types
- **DO** parse permissive input to strict canonical types immediately
- **DON'T** pass `dict[str, Any]` into core logic
- **DON'T** use stringly-typed enums (`role: str`)
- **DON'T** use mutable defaults (`def foo(items=[]):`)
- **NEVER** skip validation at boundaries

---

## Related Skills

- **python-composition**: When to add methods vs extract functions
- **python-control-flow**: Pattern matching on discriminated unions
- **python-modules**: Organizing domain types into bounded contexts

## Supporting Documentation

- `philosophy.md`: Full DDD concepts and rationale
- `examples.md`: Extensive value object and type design examples

## References

- [Parse, Don't Validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/) - Original concept
- [Parse, Don't Validate (Python Edition)](https://stianlagstad.no/2022/05/parse-dont-validate-python-edition/) - Python-specific patterns
- [Cosmic Python: Domain Modeling](https://www.cosmicpython.com/book/chapter_01_domain_model.html) - Domain-driven design in Python
- [Exploring Four Languages](https://v4.chriskrycho.com/exploring-four-languages.html) - Type system thinking
