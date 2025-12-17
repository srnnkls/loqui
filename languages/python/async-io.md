---
paths: "**/*.py, **/pyproject.toml"
---

# Python Async/IO - Imperative Skill

**When to invoke**: Working with async code, I/O operations, streaming data, concurrency.

---

## Core Commands

### Async ONLY for I/O-Bound Operations

```python
# ✓ Async for I/O
async def fetch_user_data(user_id: str) -> UserData:
    async with httpx.AsyncClient() as client:
        return await client.get(f"/users/{user_id}")

# ✘ WRONG: Blocking I/O
async def bad():
    return requests.get(url)  # Blocks event loop!
```

**Use async for:** Network I/O, async file I/O, concurrent operations
**DON'T use for:** CPU-bound work, pure computation

### ALWAYS Set Timeouts

```python
# ✓ MUST have timeout
async def fetch(url: str) -> Response:
    async with httpx.AsyncClient(timeout=10.0) as client:
        return await client.get(url)
```

### USE TaskGroup for Structured Concurrency

```python
# ✓ TaskGroup for concurrent ops
async def process_users(user_ids: list[str]) -> list[UserData]:
    async with asyncio.TaskGroup() as group:
        tasks = [group.create_task(fetch_user_data(uid)) for uid in user_ids]
    return [task.result() for task in tasks]
```

**TaskGroup cancels remaining tasks if any fails. Document this behavior.**

### NEVER Mix Blocking I/O

**Blocking I/O freezes the event loop.**

```python
# ✘ WRONG: Blocks event loop
async def bad():
    requests.get(url)  # FORBIDDEN
    open("file").read()  # FORBIDDEN
    time.sleep(1)  # FORBIDDEN

# ✓ Use async alternatives
async def good():
    async with httpx.AsyncClient() as client:
        await client.get(url)
    await asyncio.sleep(1)
```

### Keep Async Boundaries Explicit

**CPU logic stays sync. Only I/O is async.**

```python
# ✓ Explicit boundaries
async def handle_request(request: Request) -> Response:
    user_data = await fetch_user_data(request.user_id)  # Async I/O
    result = process_data(user_data)  # Sync CPU work
    await save_result(result)  # Async I/O
    return Response(data=result)

def process_data(data: UserData) -> ProcessedData:
    """Sync - no I/O."""
    return ProcessedData(...)
```

**DON'T make functions async just because caller is async.**

### Generators vs Lists

**Generators for streams, lists for small collections.**

```python
# ✓ Generator for large streams
def read_logs(path: Path) -> Iterator[LogEntry]:
    with path.open() as f:
        for line in f:
            if entry := parse_log_line(line):
                yield entry

# ✓ List for small, reusable data
def get_active_users(users: list[User]) -> list[User]:
    return [u for u in users if u.is_active]
```

**Pydantic: Use `Sequence[T]` NOT `Iterable[T]` (Iterable becomes generator!)**

### Async Context Managers & Generators

```python
# ✓ Async context manager
@asynccontextmanager
async def database_transaction(pool: Pool) -> AsyncIterator[Connection]:
    conn = await pool.acquire()
    try:
        await conn.execute("BEGIN")
        yield conn
        await conn.execute("COMMIT")
    except Exception:
        await conn.execute("ROLLBACK")
        raise
    finally:
        await pool.release(conn)

# ✓ Async generator for streaming
async def stream_logs(source: str) -> AsyncIterator[LogEntry]:
    async with httpx.AsyncClient() as client:
        async with client.stream("GET", f"/logs/{source}") as response:
            async for line in response.aiter_lines():
                if entry := parse_log_line(line):
                    yield entry
```

---

## Commands Summary

- **DO** use async ONLY for I/O-bound operations
- **DO** ALWAYS set timeouts on async I/O
- **DO** use TaskGroup for structured concurrency
- **DO** document TaskGroup cancellation behavior
- **DO** keep async boundaries explicit (CPU work stays sync)
- **DO** use generators for large streams, lists for small collections
- **DO** use `Sequence[T]` in Pydantic models (NOT `Iterable[T]`)
- **DO** use async context managers for resource lifecycle
- **DO** use async generators for streaming data
- **NEVER** mix blocking I/O in async functions (`requests`, `open()`, `time.sleep()`)
- **NEVER** make functions async unnecessarily (no awaits = shouldn't be async)
- **NEVER** forget timeouts (can hang indefinitely)

---

## Related Skills

- **python-errors**: Result types for async error coordination
- **python-control-flow**: Generators vs lists

## Supporting Documentation

- `patterns.md`: TaskGroups, async context managers, async generators
- `pitfalls.md`: Event loop blocking, exhausted generators, missing timeouts
