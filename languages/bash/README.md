# Bash Guide

Patterns and anti-patterns for bash commands and shell scripts.

---

## Resources

| Resource | When to Use |
|----------|-------------|
| [reference/commands.md](reference/commands.md) | Interactive commands, one-liners, CLI usage |
| [reference/scripts.md](reference/scripts.md) | Shell scripts (`.sh` files) |

---

## Related

- **bash-use**: Ultra-concise bash command skill
- **code-test**: TDD workflow

# Advanced Bash Patterns

## Parameter Expansion

```bash
# Default values
${var:-default}              # Use default if var unset
${var:=default}              # Assign default if var unset
${var:?error msg}            # Exit with error if var unset

# String manipulation
${var#pattern}               # Remove shortest match from start
${var##pattern}              # Remove longest match from start
${var%pattern}               # Remove shortest match from end
${var%%pattern}              # Remove longest match from end
${var/pattern/replacement}   # Replace first match
${var//pattern/replacement}  # Replace all matches
${var^}                      # Uppercase first char
${var^^}                     # Uppercase all
${var,}                      # Lowercase first char
${var,,}                     # Lowercase all

# Extract filename components
file="/path/to/file.tar.gz"
${file##*/}                  # file.tar.gz (basename)
${file%/*}                   # /path/to (dirname)
${file%%.*}                  # /path/to/file (strip all extensions)
${file%.*}                   # /path/to/file.tar (strip last extension)
${file##*.}                  # gz (last extension)
```

## Process Substitution

```bash
# Compare outputs
diff <(cmd1) <(cmd2)

# Multiple inputs to single command
paste <(cut -f1 file1) <(cut -f2 file2)

# Avoid temp files
while read line; do ...; done < <(complex | pipeline)

# Feed string as file
cmd <(echo "content")
cmd <(cat <<< "$variable")
```

## Brace Expansion

```bash
# Sequences
{1..10}                      # 1 2 3 ... 10
{01..10}                     # 01 02 03 ... 10 (zero-padded)
{a..z}                       # a b c ... z
{10..1}                      # 10 9 8 ... 1 (reverse)
{1..10..2}                   # 1 3 5 7 9 (step)

# Combinations
{a,b}{1,2}                   # a1 a2 b1 b2
{a..c}{1..3}                 # a1 a2 a3 b1 b2 b3 c1 c2 c3

# Practical uses
mkdir -p {src,test}/{unit,integration}/{fixtures,mocks}
mv file.txt{,.bak}           # Rename file.txt to file.txt.bak
cp file.{txt,bak}            # Copy file.txt to file.bak
echo {1..5}.log              # 1.log 2.log 3.log 4.log 5.log
```

## Advanced Globs

```bash
# Enable extended globbing
shopt -s extglob globstar nullglob

# Extended glob patterns
*(pattern)                   # Zero or more occurrences
+(pattern)                   # One or more occurrences
?(pattern)                   # Zero or one occurrence
@(pattern)                   # Exactly one occurrence
!(pattern)                   # Anything except pattern

# Examples
ls !(*.txt)                  # All files except .txt
ls !(*.@(txt|log))          # Exclude .txt and .log
rm +(*.tmp|*.cache)         # Remove .tmp and .cache files
ls file?(s).txt             # Match file.txt and files.txt

# Recursive globbing
**/*.js                      # All .js files recursively (requires globstar)
**/*test*.py                # All test Python files in any subdirectory

# Character classes
[[:alnum:]]                  # Alphanumeric
[[:alpha:]]                  # Alphabetic
[[:digit:]]                  # Digits
[[:lower:]]                  # Lowercase
[[:upper:]]                  # Uppercase
[[:space:]]                  # Whitespace

# Practical combinations
rm -rf **/!(node_modules)/  # Remove all except node_modules
ls **/*.@(yml|yaml)         # All YAML files recursively
```

## Compound Commands

```bash
# Conditional execution
cmd1 && cmd2 || cmd3         # If cmd1 succeeds, run cmd2, else cmd3
[[ condition ]] && cmd       # Run cmd only if condition true

# Command grouping
(cd dir && make)             # Run in subshell, no cd side effect
{ cmd1; cmd2; } > file       # Group output to single file

# Here-strings (avoid echo | cmd)
grep pattern <<< "$variable"
bc <<< "scale=2; 10/3"
read var1 var2 <<< "$line"

# Here-docs with variable expansion
cat <<EOF
Value: $var
Date: $(date)
EOF

# Here-docs without expansion
cat <<'EOF'
Literal $var $(cmd)
EOF

# Here-docs to variable
config=$(cat <<EOF
key=value
foo=bar
EOF
)
```

## One-Liners

```bash
# Create and cd into directory
mkdir -p dir/subdir && cd $_

# Backup and modify file in-place
sed -i.bak 's/old/new/' file

# Loop over command output
while IFS= read -r line; do ...; done < <(cmd)

# Find and process files (no xargs)
while IFS= read -r -d '' file; do ...; done < <(find . -name "*.txt" -print0)

# Quick HTTP server
python3 -m http.server 8000

# Search and replace across multiple files
find . -name "*.js" -exec sed -i 's/old/new/g' {} +

# Parallel execution (GNU parallel or xargs -P)
find . -name "*.jpg" | parallel convert {} {.}.png
ls *.txt | xargs -P 4 -I {} wc -l {}

# JSON processing with jq
curl api.com/data | jq -r '.items[] | "\(.id): \(.name)"'

# Filter unique/duplicate lines
sort file | uniq                # Unique lines
sort file | uniq -d             # Duplicate lines only
sort file | uniq -c | sort -rn  # Count occurrences, most common first

# Archive excluding patterns
tar czf backup.tar.gz --exclude='*.log' --exclude='.git' project/

# Mass rename with pattern
for f in *.txt; do mv "$f" "${f%.txt}.bak"; done
for f in *; do mv "$f" "prefix_$f"; done

# Date arithmetic
date -d "yesterday" +%Y-%m-%d
date -d "5 days ago" +%Y-%m-%d
date -d "2 weeks" +%Y-%m-%d

# Command output to clipboard (macOS)
cmd | pbcopy

# Inline editing with temp file cleanup
awk 'script' input > tmp && mv tmp input
```

## Advanced Patterns

```bash
# Default to stdin or file
cat "${1:-/dev/stdin}"

# Retry logic
for i in {1..5}; do cmd && break || sleep 2; done

# Timeout command
timeout 10s long-running-cmd

# Lock file pattern
lockfile=/tmp/script.lock
if mkdir "$lockfile" 2>/dev/null; then
    trap 'rmdir "$lockfile"' EXIT
    # critical section
fi

# Atomic writes
tmp=$(mktemp) && echo "content" > "$tmp" && mv "$tmp" target

# Safe sourcing
[[ -f config.sh ]] && source config.sh

# Array manipulation
arr=(a b c d)
${arr[@]}                    # All elements
${arr[0]}                    # First element
${arr[@]:1}                  # All except first
${arr[@]:1:2}                # Elements 1-2
${#arr[@]}                   # Array length
arr+=(e f)                   # Append elements

# Read into array
mapfile -t lines < file.txt
IFS=$'\n' read -d '' -r -a lines < file.txt

# Associative arrays
declare -A map
map[key]=value
${map[key]}                  # Get value
${!map[@]}                   # All keys
${map[@]}                    # All values

# Command substitution with error handling
if output=$(cmd 2>&1); then
    echo "Success: $output"
else
    echo "Failed: $output"
fi

# Multiple parallel background jobs
for i in {1..5}; do
    (cmd "$i") &
done
wait                         # Wait for all background jobs
```

## Testing & Conditionals

```bash
# File tests
[[ -e file ]]                # Exists
[[ -f file ]]                # Regular file
[[ -d dir ]]                 # Directory
[[ -L link ]]                # Symbolic link
[[ -r file ]]                # Readable
[[ -w file ]]                # Writable
[[ -x file ]]                # Executable
[[ -s file ]]                # Non-empty
[[ file1 -nt file2 ]]        # file1 newer than file2
[[ file1 -ot file2 ]]        # file1 older than file2

# String tests
[[ -z $var ]]                # Empty string
[[ -n $var ]]                # Non-empty string
[[ $a == $b ]]               # Equal
[[ $a != $b ]]               # Not equal
[[ $a < $b ]]                # Less than (lexical)
[[ $a > $b ]]                # Greater than (lexical)
[[ $a =~ regex ]]            # Regex match

# Numeric tests
[[ $a -eq $b ]]              # Equal
[[ $a -ne $b ]]              # Not equal
[[ $a -lt $b ]]              # Less than
[[ $a -le $b ]]              # Less than or equal
[[ $a -gt $b ]]              # Greater than
[[ $a -ge $b ]]              # Greater than or equal

# Logical operators
[[ cond1 && cond2 ]]         # AND
[[ cond1 || cond2 ]]         # OR
[[ ! cond ]]                 # NOT
```
>>>>>>> 8ea89cd7b446b0c22bfee0710300e41997bb46bd
||||||| Stash base
=======
# Advanced Bash Patterns

## Parameter Expansion

```bash
# Default values
${var:-default}              # Use default if var unset
${var:=default}              # Assign default if var unset
${var:?error msg}            # Exit with error if var unset

# String manipulation
${var#pattern}               # Remove shortest match from start
${var##pattern}              # Remove longest match from start
${var%pattern}               # Remove shortest match from end
${var%%pattern}              # Remove longest match from end
${var/pattern/replacement}   # Replace first match
${var//pattern/replacement}  # Replace all matches
${var^}                      # Uppercase first char
${var^^}                     # Uppercase all
${var,}                      # Lowercase first char
${var,,}                     # Lowercase all

# Extract filename components
file="/path/to/file.tar.gz"
${file##*/}                  # file.tar.gz (basename)
${file%/*}                   # /path/to (dirname)
${file%%.*}                  # /path/to/file (strip all extensions)
${file%.*}                   # /path/to/file.tar (strip last extension)
${file##*.}                  # gz (last extension)
```

## Process Substitution

```bash
# Compare outputs
diff <(cmd1) <(cmd2)

# Multiple inputs to single command
paste <(cut -f1 file1) <(cut -f2 file2)

# Avoid temp files
while read line; do ...; done < <(complex | pipeline)

# Feed string as file
cmd <(echo "content")
cmd <(cat <<< "$variable")
```

## Brace Expansion

```bash
# Sequences
{1..10}                      # 1 2 3 ... 10
{01..10}                     # 01 02 03 ... 10 (zero-padded)
{a..z}                       # a b c ... z
{10..1}                      # 10 9 8 ... 1 (reverse)
{1..10..2}                   # 1 3 5 7 9 (step)

# Combinations
{a,b}{1,2}                   # a1 a2 b1 b2
{a..c}{1..3}                 # a1 a2 a3 b1 b2 b3 c1 c2 c3

# Practical uses
mkdir -p {src,test}/{unit,integration}/{fixtures,mocks}
mv file.txt{,.bak}           # Rename file.txt to file.txt.bak
cp file.{txt,bak}            # Copy file.txt to file.bak
echo {1..5}.log              # 1.log 2.log 3.log 4.log 5.log
```

## Advanced Globs

```bash
# Enable extended globbing
shopt -s extglob globstar nullglob

# Extended glob patterns
*(pattern)                   # Zero or more occurrences
+(pattern)                   # One or more occurrences
?(pattern)                   # Zero or one occurrence
@(pattern)                   # Exactly one occurrence
!(pattern)                   # Anything except pattern

# Examples
ls !(*.txt)                  # All files except .txt
ls !(*.@(txt|log))          # Exclude .txt and .log
rm +(*.tmp|*.cache)         # Remove .tmp and .cache files
ls file?(s).txt             # Match file.txt and files.txt

# Recursive globbing
**/*.js                      # All .js files recursively (requires globstar)
**/*test*.py                # All test Python files in any subdirectory

# Character classes
[[:alnum:]]                  # Alphanumeric
[[:alpha:]]                  # Alphabetic
[[:digit:]]                  # Digits
[[:lower:]]                  # Lowercase
[[:upper:]]                  # Uppercase
[[:space:]]                  # Whitespace

# Practical combinations
rm -rf **/!(node_modules)/  # Remove all except node_modules
ls **/*.@(yml|yaml)         # All YAML files recursively
```

## Compound Commands

```bash
# Conditional execution
cmd1 && cmd2 || cmd3         # If cmd1 succeeds, run cmd2, else cmd3
[[ condition ]] && cmd       # Run cmd only if condition true

# Command grouping
(cd dir && make)             # Run in subshell, no cd side effect
{ cmd1; cmd2; } > file       # Group output to single file

# Here-strings (avoid echo | cmd)
grep pattern <<< "$variable"
bc <<< "scale=2; 10/3"
read var1 var2 <<< "$line"

# Here-docs with variable expansion
cat <<EOF
Value: $var
Date: $(date)
EOF

# Here-docs without expansion
cat <<'EOF'
Literal $var $(cmd)
EOF

# Here-docs to variable
config=$(cat <<EOF
key=value
foo=bar
EOF
)
```

## One-Liners

```bash
# Create and cd into directory
mkdir -p dir/subdir && cd $_

# Backup and modify file in-place
sed -i.bak 's/old/new/' file

# Loop over command output
while IFS= read -r line; do ...; done < <(cmd)

# Find and process files (no xargs)
while IFS= read -r -d '' file; do ...; done < <(find . -name "*.txt" -print0)

# Quick HTTP server
python3 -m http.server 8000

# Search and replace across multiple files
find . -name "*.js" -exec sed -i 's/old/new/g' {} +

# Parallel execution (GNU parallel or xargs -P)
find . -name "*.jpg" | parallel convert {} {.}.png
ls *.txt | xargs -P 4 -I {} wc -l {}

# JSON processing with jq
curl api.com/data | jq -r '.items[] | "\(.id): \(.name)"'

# Filter unique/duplicate lines
sort file | uniq                # Unique lines
sort file | uniq -d             # Duplicate lines only
sort file | uniq -c | sort -rn  # Count occurrences, most common first

# Archive excluding patterns
tar czf backup.tar.gz --exclude='*.log' --exclude='.git' project/

# Mass rename with pattern
for f in *.txt; do mv "$f" "${f%.txt}.bak"; done
for f in *; do mv "$f" "prefix_$f"; done

# Date arithmetic
date -d "yesterday" +%Y-%m-%d
date -d "5 days ago" +%Y-%m-%d
date -d "2 weeks" +%Y-%m-%d

# Command output to clipboard (macOS)
cmd | pbcopy

# Inline editing with temp file cleanup
awk 'script' input > tmp && mv tmp input
```

## Advanced Patterns

```bash
# Default to stdin or file
cat "${1:-/dev/stdin}"

# Retry logic
for i in {1..5}; do cmd && break || sleep 2; done

# Timeout command
timeout 10s long-running-cmd

# Lock file pattern
lockfile=/tmp/script.lock
if mkdir "$lockfile" 2>/dev/null; then
    trap 'rmdir "$lockfile"' EXIT
    # critical section
fi

# Atomic writes
tmp=$(mktemp) && echo "content" > "$tmp" && mv "$tmp" target

# Safe sourcing
[[ -f config.sh ]] && source config.sh

# Array manipulation
arr=(a b c d)
${arr[@]}                    # All elements
${arr[0]}                    # First element
${arr[@]:1}                  # All except first
${arr[@]:1:2}                # Elements 1-2
${#arr[@]}                   # Array length
arr+=(e f)                   # Append elements

# Read into array
mapfile -t lines < file.txt
IFS=$'\n' read -d '' -r -a lines < file.txt

# Associative arrays
declare -A map
map[key]=value
${map[key]}                  # Get value
${!map[@]}                   # All keys
${map[@]}                    # All values

# Command substitution with error handling
if output=$(cmd 2>&1); then
    echo "Success: $output"
else
    echo "Failed: $output"
fi

# Multiple parallel background jobs
for i in {1..5}; do
    (cmd "$i") &
done
wait                         # Wait for all background jobs
```

## Testing & Conditionals

```bash
# File tests
[[ -e file ]]                # Exists
[[ -f file ]]                # Regular file
[[ -d dir ]]                 # Directory
[[ -L link ]]                # Symbolic link
[[ -r file ]]                # Readable
[[ -w file ]]                # Writable
[[ -x file ]]                # Executable
[[ -s file ]]                # Non-empty
[[ file1 -nt file2 ]]        # file1 newer than file2
[[ file1 -ot file2 ]]        # file1 older than file2

# String tests
[[ -z $var ]]                # Empty string
[[ -n $var ]]                # Non-empty string
[[ $a == $b ]]               # Equal
[[ $a != $b ]]               # Not equal
[[ $a < $b ]]                # Less than (lexical)
[[ $a > $b ]]                # Greater than (lexical)
[[ $a =~ regex ]]            # Regex match

# Numeric tests
[[ $a -eq $b ]]              # Equal
[[ $a -ne $b ]]              # Not equal
[[ $a -lt $b ]]              # Less than
[[ $a -le $b ]]              # Less than or equal
[[ $a -gt $b ]]              # Greater than
[[ $a -ge $b ]]              # Greater than or equal

# Logical operators
[[ cond1 && cond2 ]]         # AND
[[ cond1 || cond2 ]]         # OR
[[ ! cond ]]                 # NOT
```
