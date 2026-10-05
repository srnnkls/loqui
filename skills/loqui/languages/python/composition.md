---
paths: "**/*.py, **/pyproject.toml"
---

# Python Composition

Structuring behavior, classes vs functions vs modules, and composition patterns.

## Core Commands

### NO Behavioral Inheritance (Except Exceptions)

**NEVER use inheritance for code reuse. ONLY for exception hierarchies.**

```python
# ✓ Exception hierarchy OK
class APIError(Exception): ...

# ✘ WRONG: Behavioral inheritance
class BaseRequest:
    def validate(self): ...
class FeatureRequest(BaseRequest): ...  # FORBIDDEN

# ✓ CORRECT: Composition
@dataclass
class FeatureRequest:
    def validate(self):
        return validate_request(self)  # Composed function
```

**This rule is absolute.**

### USE Protocols for Structural Contracts

**Protocols are the default.**

```python
from typing import Protocol

@runtime_checkable
class Storage(Protocol):
    def save(self, key: str, value: bytes) -> None: ...
    def load(self, key: str) -> bytes | None: ...
```

**Protocol (default)**: Structural typing, type-checked, no runtime enforcement
**ABC (rare)**: When you need runtime enforcement or want default implementations

### ONLY Create Classes for Mutable and Encapsulated State

**Classes exist ONLY when you need mutable state encapsulated across multiple method calls.**

```python
# ✓ Class managing mutable state
@dataclass
class MessageBuffer:
    messages: list[Message] = field(default_factory=list)

    def add(self, message: Message):
        self.messages.append(message)

# ✘ WRONG: Class as namespace
class MessageUtils:
    @staticmethod
    def parse_tags(tags): ...

# ✓ CORRECT: Module functions
def parse_tags(tags): ...
```

### NEVER Use @staticmethod

**@staticmethod is ALWAYS wrong. Use module-level functions.**

```python
# ✘ WRONG: Staticmethod
class Session:
    @staticmethod
    def validate_message(msg): ...

# ✓ CORRECT: Module-level function
def validate_message(msg): ...
```

**Python already has namespaces: modules. This is not Java.**

### USE @classmethod for Alternative Constructors

**@classmethod is valid because it receives the class as its first argument.**

```python
@dataclass(frozen=True, kw_only=True)
class User:
    email: str
    age: int

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Self:
        """Alternative constructor - needs cls."""
        return cls(email=data["email"], age=data["age"])

    @classmethod
    def from_json(cls, json_str: str) -> Self:
        """Another alternative constructor."""
        return cls.from_dict(json.loads(json_str))
```

### Pragmatic State Management

**Immutable by default. Encapsulate mutation with explicit APIs.**

```python
# ✓ Immutable value objects
@dataclass(frozen=True, kw_only=True)
class FeatureDescription:
    name: str

# ✓ Encapsulated mutable state
@dataclass
class MessageBuffer:
    messages: list[Message] = field(default_factory=list)

    def commit(self):
        self.messages.extend(self.pending)
        self.pending.clear()  # DO: .clear(), NOT self.pending = []
```

### Renderer/Adapter Pattern

**Keep domain pure. Extract presentation to adapters.**

```python
# ✓ Pure domain
@dataclass(frozen=True, kw_only=True)
class Message:
    content: str
    role: Role

# ✓ Separate renderer
class MessageRenderer(JupyterMixin):
    def __init__(self, message: Message):
        self.message = message
```

**DON'T pollute domain with mixins (JupyterMixin, rich, UI).**

### Pragmatic Separation

**Simple logic on classes OK. Extract when complex, shared, or has dependencies.**

```python
# ✓ Simple logic on class
@dataclass(frozen=True, kw_only=True)
class Message:
    def __str__(self) -> str:
        return f"{self.role}: {self.content}"

# ✓ Extract complex logic
def format_message_detailed(message: Message) -> str:
    """Complex formatting extracted."""
    ...
```

## Architecture Layers

**Build from simple pieces:**

- **Data layer**: Immutable, validated domain types
- **Function layer**: Pure functions and services
- **Orchestration layer**: Stateful coordinators (when necessary)

## Summary

- **NEVER** use behavioral inheritance (except exceptions)
- **NEVER** use `@staticmethod` - use module functions
- **DO** use Protocols for structural contracts (default choice)
- **DO** use ABC only when you need runtime enforcement or default implementations
- **DO** create classes ONLY for mutable state management
- **DO** use `@classmethod` for alternative constructors
- **DO** use immutability by default (`@dataclass(frozen=True)`)
- **DO** encapsulate mutation with explicit state transition APIs
- **DO** use renderer/adapter pattern to keep domain models pure
- **DO** keep simple logic on classes, extract complex/shared logic to functions
- **DO** use modules for namespacing, not classes

---

## Related

- **python-domain-types**: When to add methods to value objects
- **python-modules**: Organizing functions into cohesive modules
- **python-quality**: When simple logic belongs on class vs extracted

## Supporting Documentation

- `patterns.md`: Protocols, decorators, generics, context managers
- `state-management.md`: When to use classes, encapsulation patterns

## References

- [Python Subclassing Redux](https://hynek.me/articles/python-subclassing-redux/) - Why inheritance is problematic
- [The Wrong Abstraction](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction) - Duplication is better than wrong abstraction
