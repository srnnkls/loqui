# Bash Interactive Commands

Ultra-concise patterns for interactive bash commands and one-liners.

---

## Core Principles

### 1. Quote Paths with Spaces
```bash
# WRONG
cd /path with spaces/dir

# CORRECT
cd "/path with spaces/dir"
```

Double-quote paths containing spaces.

### 2. Use Relative Paths with rm
```bash
# WRONG (blocked by policy)
rm -rf "$HOME/project/build"

# CORRECT
rm -rf ./build
```

Always use relative paths with `rm`.

### 3. Chain Commands Safely
```bash
# Fail if any command fails
command1 && command2 && command3

# Continue regardless
command1; command2; command3

# Stop on first failure (in scripts)
command1 || exit 1
```

Use `&&` to chain dependent commands.

### 4. Command Substitution
```bash
# WRONG
result=`command`

# CORRECT
result=$(command)
```

Use `$()` for command substitution, not backticks.

### 5. Check Command Existence
```bash
command -v jq &>/dev/null || echo "jq not found"
```

Use `command -v` to check if programs exist.

### 6. Output Redirection
```bash
# Redirect stderr to stdout
command 2>&1

# Suppress all output
command &>/dev/null

# Suppress stderr only
command 2>/dev/null

# Append to file
command >> file.txt
```

### 7. Process Substitution
```bash
# Compare outputs of two commands
diff <(cmd1) <(cmd2)

# Feed command output as file
wc -l <(find . -name "*.txt")
```

Use `<()` to treat command output as a file.

### 8. Find and Process Files
```bash
# Find by pattern
find . -name "*.txt"

# Find and delete
find . -name "*.tmp" -delete

# Find and execute
find . -name "*.log" -exec wc -l {} +

# Using xargs
find . -name "*.txt" -print0 | xargs -0 grep "pattern"
```

Use `-print0` and `xargs -0` for files with spaces.

---

## Quick Anti-Patterns Checklist

**Quoting:**
- ✘ Unquoted paths with spaces
- ✘ Unquoted variable expansions: `$var` → Use `"$var"`

**Paths:**
- ✘ Absolute paths with `rm`
- ✘ Missing quotes in paths with spaces

**Command chaining:**
- ✘ Using `;` when `&&` is needed
- ✘ Not checking exit codes for critical commands

**Redirection:**
- ✘ Using backticks `` `cmd` `` → Use `$(cmd)`
- ✘ Redirecting wrong stream (>&1 vs 2>&1)

---

## Common Patterns

### Search and Filter
```bash
# Grep with context
grep -C 3 "pattern" file.txt

# Recursive grep
grep -r "pattern" .

# Case-insensitive
grep -i "pattern" file.txt

# Count matches
grep -c "pattern" file.txt
```

### Working with Files
```bash
# Count lines
wc -l file.txt

# Head/tail
head -n 10 file.txt
tail -n 10 file.txt

# Follow file updates
tail -f logfile.log

# Sort and unique
sort file.txt | uniq
```

### Pipes and Filters
```bash
# Chain transformations
cat file.txt | grep "pattern" | sort | uniq -c

# Using column
ps aux | column -t

# Using awk
ps aux | awk '{print $1, $2}'
```

### JSON Processing (jq)
```bash
# Pretty print
cat data.json | jq '.'

# Extract field
jq '.field' data.json

# Filter array
jq '.items[] | select(.active == true)' data.json
```

---

## References

- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
