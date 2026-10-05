# Bash Shell Scripts

Patterns for writing robust shell scripts (`.sh` files).

---

## Core Principles

### 1. Always Use Strict Mode
```bash
#!/usr/bin/env bash
set -euo pipefail
```

- `-e`: Exit on error
- `-u`: Exit on undefined variable
- `-o pipefail`: Exit if any command in pipeline fails

### 2. Quote Everything
```bash
# WRONG
rm -rf $path/$file

# CORRECT
rm -rf "${path}/${file}"
```

**Always quote variable expansions.** Unquoted variables split on whitespace.

### 3. Use `[[` for Conditionals
```bash
# WRONG
if [ "$var" = "value" ]; then

# CORRECT
if [[ "$var" == "value" ]]; then
```

`[[` is bash-native, safer, and more consistent than `[`.

### 4. Use Local Variables in Functions
```bash
process_file() {
  local file=$1
  local result
  result=$(transform "$file")
  echo "$result"
}
```

Prevent variable pollution. Always declare `local`.

### 5. Check Command Existence
```bash
if ! command -v jq &>/dev/null; then
  echo "jq not found" >&2
  exit 1
fi
```

Use `command -v` to check if programs exist.

### 6. Use Arrays for Lists
```bash
# WRONG
files="file1.txt file2.txt file3.txt"
for f in $files; do

# CORRECT
files=("file1.txt" "file2.txt" "file3.txt")
for f in "${files[@]}"; do
```

Arrays handle spaces in names correctly.

### 7. Relative Paths for rm
```bash
# WRONG (blocked by policy)
rm -rf "$HOME/project/build"

# CORRECT
rm -rf ./build
```

Always use relative paths with `rm`.

---

## Quick Anti-Patterns Checklist

**Strict mode:**
- ✘ Missing `set -euo pipefail`
- ✘ Using `set -e` alone (need `-u` and `-o pipefail`)

**Quoting:**
- ✘ Unquoted variables: `$var` → Use `"$var"`
- ✘ Unquoted paths: `$HOME/$file` → Use `"$HOME/$file"`
- ✘ Word splitting: `$list` → Use arrays

**Conditionals:**
- ✘ Using `[` instead of `[[`
- ✘ Unquoted conditionals: `[ $var = x ]` → Use `[[ "$var" == x ]]`

**Functions:**
- ✘ Missing `local` declarations
- ✘ Global variables in functions
- ✘ Not checking command existence

**Arrays:**
- ✘ Space-separated strings instead of arrays
- ✘ Iterating over `$array` instead of `"${array[@]}"`

**Paths:**
- ✘ Absolute paths with `rm`
- ✘ Missing quotes in paths with spaces

---

## Error Handling

```bash
# Check exit status
if ! some_command; then
  echo "Command failed" >&2
  exit 1
fi

# Or with explicit check
some_command || {
  echo "Command failed" >&2
  exit 1
}
```

---

## Output Redirection

```bash
# Stderr
echo "Error message" >&2

# Suppress all output
command &>/dev/null

# Suppress stderr only
command 2>/dev/null
```

---

## Command Substitution

```bash
# WRONG
result=`command`

# CORRECT
result=$(command)
```

Use `$()` for command substitution, not backticks.

---

## References

- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [ShellCheck](https://www.shellcheck.net/) - Bash linting tool
