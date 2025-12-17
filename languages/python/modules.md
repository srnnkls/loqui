---
paths: "**/*.py, **/pyproject.toml"
---

# Python Modules - Imperative Skill

**When to invoke**: Organizing code, creating packages, exposing public APIs, module structure.

## Core Commands

### ALWAYS Use src Layout

**NEVER use flat layout. ALWAYS use src layout.**

```
# ✓ CORRECT: src layout
project-root/
├── src/
│   └── myproject/
│       ├── __init__.py
│       ├── chat/
│       ├── storage/
│       └── llm/
├── tests/
└── pyproject.toml

# ✘ WRONG: Flat layout (tests can import from source tree)
project-root/
├── myproject/
│   ├── chat/
│   └── storage/
└── tests/
```

**Why src layout:**
- Ensures tests run against installed package, not source directory
- Prevents accidentally importing from local directory
- Catches packaging issues early

### Feature-Based Organization (NOT Layer-Based)

**Organize by domain feature, NOT by technical layer.**

```python
# ✓ CORRECT: Feature-based
src/myproject/
├── chat/
│   ├── __init__.py
│   ├── messages.py          # Message types
│   ├── session.py           # Session coordination
│   ├── formatting.py        # Message formatting
│   └── validation.py        # Message validation
├── storage/
│   ├── __init__.py
│   ├── backends.py          # Storage implementations
│   └── serialization.py
└── llm/
    ├── __init__.py
    ├── providers.py
    └── parsing.py

# ✘ WRONG: Layer-based organization
src/myproject/
├── models/                  # All dataclasses mixed
│   ├── message.py
│   ├── session.py
│   ├── storage.py
├── services/                # All business logic mixed
│   ├── chat_service.py
│   ├── storage_service.py
└── utils/                   # Grab bag
    ├── formatting.py
    └── validation.py
```

### Module Cohesion

**Keep related types and functions together. Split at ~500 lines.**

```python
# ✓ CORRECT: Cohesive module
# src/myproject/chat/messages.py
@dataclass(frozen=True, kw_only=True)
class UserMessage: ...

@dataclass(frozen=True, kw_only=True)
class AssistantMessage: ...

Message = UserMessage | AssistantMessage | SystemMessage

def format_message(message: Message) -> str: ...
def validate_message(message: Message) -> None: ...
```

**When to split modules:**
- Module exceeds ~500 lines
- Distinct concerns within module
- Natural separation emerges

**DON'T split prematurely (< 100 lines per file is too fragmented).**

### Explicit Public APIs

**ALWAYS use `__all__` in `__init__.py` to define public API.**

```python
# ✓ CORRECT: Explicit public API
# src/myproject/chat/__init__.py
from myproject.chat.messages import AssistantMessage, Message, UserMessage
from myproject.chat.session import Session

__all__ = [
    "Session",
    "Message",
    "UserMessage",
    "AssistantMessage",
]

# Usage: clean imports
from myproject.chat import Session, UserMessage

# ✘ WRONG: No __init__.py, forcing deep imports
from myproject.chat.session import Session
from myproject.chat.messages import UserMessage

# ✘ WRONG: Star imports without __all__
from myproject.chat.messages import *  # What did I just import?
```

### Dependencies Flow Toward Domain Core

**Domain has no dependencies. Services depend on domain. API depends on services.**

```python
# ✓ CORRECT: Dependencies flow inward
# src/myproject/domain/messages.py
@dataclass(frozen=True, kw_only=True)
class Message: ...  # No external dependencies

# src/myproject/services/chat.py
from myproject.domain.messages import Message

class ChatService:
    def send(self, message: Message): ...  # Depends on domain

# src/myproject/api/endpoints.py
from myproject.services.chat import ChatService

def chat_endpoint(service: ChatService): ...  # Depends on service

# ✘ WRONG: Circular dependencies
# domain/messages.py imports from services/chat.py
# services/chat.py imports from domain/messages.py
```

### Module-Level Constants

**Constants at module level. Separate configuration if needed.**

```python
# ✓ CORRECT: Module-level constants
# src/myproject/llm/constants.py
DEFAULT_MODEL = "gpt-4"
DEFAULT_TEMPERATURE = 0.0
MAX_RETRIES = 3
TIMEOUT_SECONDS = 30

# ✘ WRONG: Constants in unnecessary class
class LLMConfig:  # Unnecessary wrapper
    DEFAULT_MODEL = "gpt-4"
    DEFAULT_TEMPERATURE = 0.0
```

---

## Commands Summary

- **DO** ALWAYS use src layout (`src/myproject/`)
- **DO** organize by feature/domain, NOT layer
- **DO** keep related types + functions together
- **DO** split modules at ~500 lines or when distinct concerns emerge
- **DO** use explicit `__all__` in `__init__.py`
- **DO** ensure dependencies flow toward domain core
- **DO** use module-level constants (NOT classes-as-namespaces)
- **DON'T** use flat layout (`myproject/` at root)
- **DON'T** organize by technical layer (models/, services/, utils/)
- **DON'T** split prematurely (< 100 lines per file)
- **DON'T** use star imports without `__all__`
- **NEVER** create circular dependencies

---

## Related Skills
- **python-composition**: Classes vs modules (use modules for namespacing)
- **python-quality**: When to split files (section dividers = time to split)

## Supporting Documentation
- `examples.md`: Package structures, public API patterns, dependency flows
