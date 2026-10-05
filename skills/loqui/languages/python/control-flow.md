---
paths: "**/*.py, **/pyproject.toml"
---

# Python Control Flow

Conditionals, loops, branching logic, and data transformations.

## Core Commands

### USE Pattern Matching for Structural Inspection

**Pattern matching is the primary branching mechanism for inspecting data structures.**

```python
# ✓ CORRECT: Pattern matching with keyword patterns
match message:
    case AssistantMessage(content=None, function_call=None):
        raise ValueError("Invalid message")
    case AssistantMessage(function_call=FunctionCall(name=name, arguments=args)):
        return handle_function_call(name, args)
    case AssistantMessage(content=content, function_call=None):
        return handle_text_response(content)

# ✓ CORRECT: Pattern matching with guards
match result:
    case FunctionCallResult(value=value, error=None):
        return Success(value)
    case FunctionCallResult(error=error):
        return Failure(error)
    case str() if result.startswith("Error:"):
        return Failure(Error(result.removeprefix("Error:").strip()))
```

**ALWAYS use keyword patterns, NEVER positional patterns.**

```python
# ✓ CORRECT: Keyword patterns (robust to field additions)
match msg:
    case AssistantMessage(content=None, function_call=None): ...

# ✘ WRONG: Positional patterns (breaks if field order changes)
match msg:
    case AssistantMessage(None, None): ...
```

### When to Use Pattern Matching vs Simple If

**Use pattern matching when:**
- Inspecting multiple shapes or structural variants
- Extracting nested data
- Need exhaustive checking

**Use simple `if` when:**
- Single attribute check without destructuring
- No structural inspection needed

```python
# ✓ Simple conditional for single check
if response.status_code == 200:
    return response.data

# ✓ Pattern matching for multiple shapes
match response:
    case Response(status_code=200, data=data):
        return Success(data)
    case Response(status_code=code, error=error) if 400 <= code < 500:
        return ClientError(error)
    case Response(status_code=code, error=error):
        return ServerError(error)
```

### USE Iteration Over Recursion

**Python has no tail-call optimization and low recursion limit (~1000). ALWAYS prefer iteration.**

```python
# ✓ CORRECT: Iterative tree traversal
def find_nodes(root: Node, predicate: Callable[[Node], bool]) -> list[Node]:
    """Find all nodes matching predicate using iteration."""
    results = []
    stack = [root]

    while stack:
        node = stack.pop()
        if predicate(node):
            results.append(node)
        stack.extend(node.children)

    return results

# ✘ WRONG: Recursive traversal (stack overflow risk)
def find_nodes(root: Node, predicate: Callable[[Node], bool]) -> list[Node]:
    results = []
    if predicate(root):
        results.append(root)
    for child in root.children:
        results.extend(find_nodes(child, predicate))  # Recursive
    return results
```

### Iterative Patterns for Trees and Graphs

**Depth calculation:**

```python
def calculate_depth(root: Node) -> int:
    """Calculate tree depth iteratively."""
    if not root:
        return 0

    max_depth = 0
    stack = [(root, 1)]

    while stack:
        node, depth = stack.pop()
        max_depth = max(max_depth, depth)
        for child in node.children:
            stack.append((child, depth + 1))

    return max_depth
```

**Path finding:**

```python
def find_path(root: Node, target: Node) -> list[Node] | None:
    """Find path from root to target iteratively."""
    stack = [(root, [root])]

    while stack:
        node, path = stack.pop()
        if node == target:
            return path

        for child in node.children:
            stack.append((child, path + [child]))

    return None
```

### When Recursion is Acceptable

**Only when:**
- Algorithm inherently recursive with guaranteed shallow depth (< 100 levels)
- Code clarity dramatically improved
- Depth proven to be bounded

---

## Summary

- **DO** use `match/case` for structural inspection of data
- **DO** use keyword patterns (`content=None`), NEVER positional
- **DO** use simple `if` for single attribute checks
- **DO** use pattern matching for multiple shapes or nested extraction
- **DO** use iteration over recursion (Python has no TCO, ~1000 limit)
- **DO** use stack-based algorithms for tree/graph traversal
- **NEVER** use positional patterns (breaks on field changes)
- **NEVER** use recursion for unbounded data structures
- **ONLY** use recursion for proven shallow depth (< 100 levels)

---

## Related

- **python-domain-types**: Pattern matching on discriminated unions
- **python-errors**: Pattern matching on Result types

## Supporting Documentation

- `examples.md`: Pattern matching patterns, iterative algorithms
