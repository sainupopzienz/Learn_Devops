# Bash Scripting — Interview Guide (4–7 Years Experience)

### What to Know at This Level

At 4–7 years, interviewers expect you to write real scripts on the spot, debug broken scripts, and explain why you made certain choices. Not just syntax — but production thinking.

---

### Core Concepts You Must Know

| Concept | What It Covers |
|---------|---------------|
| Shebang & script structure | `#!/bin/bash`, `set -euo pipefail` |
| Variables & quoting | Strings, arrays, special vars, double vs single quotes |
| Conditionals | `if/elif/else`, `[[ ]]` vs `[ ]`, test operators |
| Loops | `for`, `while`, `until`, `break`, `continue` |
| Functions | Definition, arguments, return values, scope |
| Exit codes | `$?`, `exit`, error handling patterns |
| String manipulation | Substring, replace, trim, split |
| Arrays | Indexed, associative, iteration |
| File & I/O operations | Read, write, append, redirect, pipes |
| Process management | Background jobs, `wait`, `trap`, signals |
| Regex & text processing | `grep`, `sed`, `awk`, `cut`, `tr` |
| Debugging | `set -x`, `set -e`, `bash -n`, `shellcheck` |

---

### Script Structure — Always Start This Way

```bash
#!/bin/bash
set -euo pipefail
# -e  → exit immediately on error
# -u  → treat unset variables as errors
# -o pipefail → catch errors inside pipes

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/myscript.log"

# Logging
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
log_error() { echo "[ERROR] $*" >&2; }

# Cleanup on exit
trap cleanup EXIT
cleanup() {
  log "Script finished"
}

main() {
  log "Starting script"
  # your logic here
}

main "$@"
```

> **Always use `set -euo pipefail`** — it catches most silent failures that bite you in production.

---

### Variables & Quoting

```bash
# Variable assignment — no spaces around =
NAME="devops"
COUNT=5

# Always double-quote variables to prevent word splitting
echo "$NAME"           # correct
echo $NAME             # risky — breaks on spaces

# Command substitution
TODAY=$(date +%Y-%m-%d)
FILES=$(ls /tmp/*.log 2>/dev/null)

# Default value if variable is unset
ENV="${ENVIRONMENT:-production}"

# Read-only
readonly MAX_RETRIES=3

# Special variables
echo "$0"    # script name
echo "$1"    # first argument
echo "$@"    # all arguments (as separate strings)
echo "$#"    # number of arguments
echo "$$"    # current PID
echo "$?"    # exit code of last command
echo "$!"    # PID of last background job
```

---

### Conditionals

```bash
# Use [[ ]] — safer, supports regex, no word splitting issues
if [[ "$ENV" == "production" ]]; then
  echo "prod"
elif [[ "$ENV" == "staging" ]]; then
  echo "staging"
else
  echo "unknown"
fi

# File checks
[[ -f "$FILE" ]]    # file exists and is a regular file
[[ -d "$DIR" ]]     # directory exists
[[ -r "$FILE" ]]    # file is readable
[[ -s "$FILE" ]]    # file exists and is non-empty
[[ -z "$VAR" ]]     # string is empty
[[ -n "$VAR" ]]     # string is non-empty

# Numeric comparison
[[ $COUNT -gt 10 ]]    # greater than
[[ $COUNT -eq 0 ]]     # equal
[[ $COUNT -le 5 ]]     # less than or equal

# String regex match
if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
  echo "is a number"
fi

# Short-circuit operators
[[ -f "$FILE" ]] && echo "exists" || echo "missing"
```

---

### Loops

```bash
# For loop — list
for ENV in dev staging prod; do
  echo "Deploying to $ENV"
done

# For loop — range
for i in {1..5}; do echo "$i"; done

# For loop — C-style
for ((i=0; i<10; i++)); do
  echo "i = $i"
done

# While loop
RETRIES=0
while [[ $RETRIES -lt 3 ]]; do
  deploy && break
  RETRIES=$((RETRIES + 1))
  sleep 5
done

# Loop over files
for FILE in /var/log/*.log; do
  [[ -f "$FILE" ]] || continue
  echo "Processing $FILE"
done

# Read file line by line — correct way
while IFS= read -r LINE; do
  echo "$LINE"
done < /etc/hosts

# Loop with break/continue
for i in {1..10}; do
  [[ $i -eq 5 ]] && continue   # skip 5
  [[ $i -eq 8 ]] && break      # stop at 8
  echo "$i"
done
```

---

### Functions

```bash
# Definition
greet() {
  local name="$1"         # local scope — doesn't leak
  local greeting="Hello"
  echo "$greeting, $name"
}

# Call
greet "DevOps"

# Return value — bash functions return exit codes (0-255)
# To return strings, use echo + command substitution
get_timestamp() {
  echo "$(date +%s)"
}
TS=$(get_timestamp)

# Return exit code
is_running() {
  pgrep -x "$1" > /dev/null 2>&1
}

if is_running "nginx"; then
  echo "nginx is up"
fi

# Function with error handling
create_dir() {
  local dir="$1"
  if [[ -z "$dir" ]]; then
    log_error "create_dir: directory name required"
    return 1
  fi
  mkdir -p "$dir" || { log_error "Failed to create $dir"; return 1; }
  log "Created directory: $dir"
}
```

---

### Exit Codes & Error Handling

```bash
# Every command returns an exit code: 0 = success, non-zero = failure
ls /tmp
echo "Exit code: $?"       # 0 if success

# Check exit code explicitly
if ! cp source.txt dest.txt; then
  log_error "Copy failed"
  exit 1
fi

# OR pattern for error handling
mkdir /mydir || { echo "Failed to create dir"; exit 1; }

# Trap errors — run function on any error
trap 'log_error "Error on line $LINENO"; exit 1' ERR

# Trap multiple signals
trap 'cleanup; exit 0' SIGINT SIGTERM EXIT

# Custom exit codes — document them
readonly EXIT_OK=0
readonly EXIT_ERROR=1
readonly EXIT_USAGE=2

usage() {
  echo "Usage: $0 <env> <version>"
  exit $EXIT_USAGE
}

[[ $# -lt 2 ]] && usage
```

---

### String Manipulation

```bash
STR="hello-world-devops"

# Length
echo "${#STR}"              # 18

# Substring — ${var:start:length}
echo "${STR:6:5}"           # world

# Remove prefix (shortest match)
echo "${STR#hello-}"        # world-devops

# Remove prefix (longest match)
echo "${STR##*-}"           # devops

# Remove suffix (shortest match)
echo "${STR%-*}"            # hello-world

# Remove suffix (longest match)
echo "${STR%%-*}"           # hello

# Replace first match
echo "${STR/world/earth}"   # hello-earth-devops

# Replace all matches
echo "${STR//-/_}"          # hello_world_devops

# Uppercase / lowercase
echo "${STR^^}"             # HELLO-WORLD-DEVOPS
echo "${STR,,}"             # hello-world-devops

# Split string into array
IFS='-' read -ra PARTS <<< "$STR"
echo "${PARTS[0]}"          # hello
echo "${PARTS[1]}"          # world
```

---

### Arrays

```bash
# Indexed array
SERVERS=("web-01" "web-02" "db-01")

# Access
echo "${SERVERS[0]}"         # web-01
echo "${SERVERS[@]}"         # all elements
echo "${#SERVERS[@]}"        # length = 3
echo "${!SERVERS[@]}"        # indices: 0 1 2

# Append
SERVERS+=("cache-01")

# Slice
echo "${SERVERS[@]:1:2}"     # web-02 db-01

# Loop
for SERVER in "${SERVERS[@]}"; do
  echo "Checking $SERVER"
done

# Associative array (dictionary)
declare -A CONFIG
CONFIG["env"]="production"
CONFIG["region"]="us-east-1"
CONFIG["replicas"]="3"

echo "${CONFIG["env"]}"      # production
echo "${!CONFIG[@]}"         # all keys
echo "${CONFIG[@]}"          # all values

for KEY in "${!CONFIG[@]}"; do
  echo "$KEY = ${CONFIG[$KEY]}"
done
```

---

### File & I/O Operations

```bash
# Read file
content=$(cat /etc/os-release)

# Write / overwrite
echo "log entry" > /tmp/out.log

# Append
echo "another entry" >> /tmp/out.log

# Read line by line — correct pattern
while IFS= read -r line; do
  echo "Line: $line"
done < /tmp/out.log

# Redirect stderr
command 2>/dev/null         # suppress errors
command 2>&1                # merge stderr into stdout
command > out.log 2>&1      # redirect both to file
command &>/dev/null         # bash shorthand for both

# Here-doc
cat > /tmp/config.yaml << EOF
server:
  host: localhost
  port: 8080
  env: ${ENVIRONMENT}
EOF

# Check if file has content
if [[ -s "/tmp/errors.log" ]]; then
  log_error "Errors found:"
  cat /tmp/errors.log
fi

# Find and process files
find /var/log -name "*.log" -mtime +7 -exec gzip {} \;
```

---

### Process Management & Signals

```bash
# Run in background
long_task &
BG_PID=$!

# Wait for background job
wait $BG_PID
echo "Exit code: $?"

# Run multiple in parallel and wait all
for SERVER in "${SERVERS[@]}"; do
  ssh "$SERVER" "df -h" &
done
wait    # wait for ALL background jobs

# Kill process
kill -15 $PID    # SIGTERM — graceful
kill -9  $PID    # SIGKILL — force

# Trap signals
trap 'echo "Ctrl+C caught, cleaning up..."; exit 1' SIGINT
trap 'echo "Script exiting"; cleanup' EXIT

# Timeout a command
timeout 30 ./long-running-script.sh || echo "Timed out"

# Check if process is running
if pgrep -x "nginx" > /dev/null; then
  echo "nginx running"
fi
```

---

### Text Processing — grep, sed, awk, cut

```bash
# grep
grep "ERROR" app.log                       # find lines with ERROR
grep -i "error" app.log                    # case insensitive
grep -n "error" app.log                    # with line numbers
grep -v "DEBUG" app.log                    # exclude DEBUG lines
grep -c "ERROR" app.log                    # count matching lines
grep -E "ERROR|WARN" app.log               # extended regex

# sed — stream editor
sed 's/foo/bar/' file.txt                  # replace first match per line
sed 's/foo/bar/g' file.txt                 # replace all matches
sed -i 's/localhost/db.prod.com/g' app.conf  # in-place edit
sed '/^#/d' config.txt                     # delete comment lines
sed -n '10,20p' file.txt                   # print lines 10-20

# awk — column processing
awk '{print $1}' file.txt                  # first column
awk -F: '{print $1}' /etc/passwd           # split by : print col 1
awk '{sum += $3} END {print sum}' data.txt # sum column 3
awk '$3 > 100 {print $1, $3}' data.txt    # filter rows
awk 'NR==5' file.txt                       # print 5th line

# cut
cut -d: -f1 /etc/passwd                    # first field, delimiter :
cut -d, -f2,4 data.csv                     # fields 2 and 4
cut -c1-10 file.txt                        # first 10 characters

# tr
echo "HELLO" | tr 'A-Z' 'a-z'             # lowercase
echo "a:b:c" | tr ':' '\n'                 # replace : with newline
echo "  hello  " | tr -s ' '              # squeeze spaces
```

---

### Debugging Techniques

```bash
# Run with trace — prints every command before executing
bash -x script.sh

# Enable trace inside script
set -x
# ... your code ...
set +x    # disable trace

# Syntax check only — don't run
bash -n script.sh

# ShellCheck — static analysis (install separately)
shellcheck script.sh

# Print variable state
echo "DEBUG: VAR=$VAR, COUNT=$COUNT" >&2

# Trap to show line number on error
trap 'echo "Error at line $LINENO, exit code $?"' ERR

# Verbose mode flag pattern
VERBOSE=false
[[ "${1:-}" == "-v" ]] && VERBOSE=true

debug() {
  [[ "$VERBOSE" == true ]] && echo "[DEBUG] $*" >&2
}
```

---

### Real Interview Questions & Answers

**Q: What does `set -euo pipefail` do and why use it?**

- `-e` — exit immediately if any command fails (non-zero exit)
- `-u` — treat unset variables as errors (catches typos like `$NAEM`)
- `-o pipefail` — if any command in a pipe fails, the whole pipe fails. Without it: `failing_cmd | echo "ok"` returns 0
- Use it at the top of every production script

---

**Q: What is the difference between `$@` and `$*`?**

- `"$@"` — each argument as a separate quoted string → safe for filenames with spaces
- `"$*"` — all arguments joined as one string with IFS separator
- Always use `"$@"` when passing arguments to other commands

---

**Q: Write a script to retry a command up to 3 times with 5s sleep**

```bash
retry() {
  local cmd="$1"
  local max=3
  local delay=5
  local count=0

  until $cmd; do
    count=$((count + 1))
    [[ $count -ge $max ]] && { echo "Failed after $max attempts"; return 1; }
    echo "Attempt $count failed, retrying in ${delay}s..."
    sleep $delay
  done
}

retry "curl -sf https://api.example.com/health"
```

---

**Q: How do you safely delete files older than 30 days?**

```bash
# -mtime +30 = modified more than 30 days ago
# Always dry-run first with -print before -delete
find /var/log/app -name "*.log" -mtime +30 -print
find /var/log/app -name "*.log" -mtime +30 -delete
```

---

**Q: What's wrong with this? `if [ $count == 5 ]`**

Three issues:
1. Use `[[ ]]` not `[ ]` — safer
2. Use `-eq` for numeric comparison, not `==`
3. `$count` is unquoted — breaks if empty

Correct: `if [[ $count -eq 5 ]]`

---

**Q: How do you parse arguments in a script?**

```bash
usage() { echo "Usage: $0 -e <env> -v <version>"; exit 1; }

ENV=""
VERSION=""

while getopts "e:v:h" OPT; do
  case $OPT in
    e) ENV="$OPTARG" ;;
    v) VERSION="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

[[ -z "$ENV" || -z "$VERSION" ]] && usage
echo "Deploying $VERSION to $ENV"
```

---

**Q: How do you check if a service is up and alert if down?**

```bash
check_service() {
  local service="$1"
  local url="$2"

  if ! curl -sf --max-time 5 "$url" > /dev/null; then
    echo "ALERT: $service is DOWN at $(date)" | \
      mail -s "Service Down: $service" ops@company.com
    return 1
  fi
  echo "$service is healthy"
}

check_service "API Gateway" "https://api.example.com/health"
check_service "Auth Service" "https://auth.example.com/ping"
```

---

**Q: Write a log rotation script**

```bash
#!/bin/bash
set -euo pipefail

LOG_DIR="/var/log/myapp"
MAX_SIZE_MB=100
KEEP_DAYS=7

rotate_logs() {
  local log_file="$1"
  local size_mb

  size_mb=$(du -m "$log_file" | cut -f1)

  if [[ $size_mb -gt $MAX_SIZE_MB ]]; then
    mv "$log_file" "${log_file}.$(date +%Y%m%d_%H%M%S)"
    touch "$log_file"
    echo "Rotated: $log_file (was ${size_mb}MB)"
  fi
}

# Rotate large logs
find "$LOG_DIR" -name "*.log" | while read -r f; do
  rotate_logs "$f"
done

# Delete old rotated logs
find "$LOG_DIR" -name "*.log.*" -mtime +$KEEP_DAYS -delete
echo "Deleted logs older than $KEEP_DAYS days"
```

---

**Q: `[[ ]]` vs `[ ]` — what is the difference?**

| Feature | `[ ]` | `[[ ]]` |
|---------|-------|---------|
| POSIX standard | Yes | Bash only |
| Word splitting | Yes (unsafe) | No |
| Regex support | No | Yes (`=~`) |
| && and \|\| inside | No | Yes |
| Empty var safe | No | Yes |

Always prefer `[[ ]]` in bash scripts.

---

**Q: How do you run multiple SSH commands in parallel and collect results?**

```bash
SERVERS=("web-01" "web-02" "db-01")
RESULTS_DIR=$(mktemp -d)

for SERVER in "${SERVERS[@]}"; do
  ssh "$SERVER" "df -h / | tail -1" > "$RESULTS_DIR/$SERVER.out" 2>&1 &
done

wait    # wait for all parallel SSH jobs

echo "=== Disk Usage Results ==="
for SERVER in "${SERVERS[@]}"; do
  echo "--- $SERVER ---"
  cat "$RESULTS_DIR/$SERVER.out"
done

rm -rf "$RESULTS_DIR"
```

---

### Common Mistakes to Avoid

| Mistake | Problem | Fix |
|---------|---------|-----|
| `if [ $var == "x" ]` | Breaks if var is empty | `[[ "$var" == "x" ]]` |
| `for f in $(ls *.log)` | Breaks on spaces in filenames | `for f in *.log` |
| No `set -e` | Silent failures continue running | Add `set -euo pipefail` |
| `cat file \| grep` | Useless cat | `grep pattern file` |
| Missing quotes on `$@` | Breaks on args with spaces | Always use `"$@"` |
| `rm -rf $DIR/` | If `$DIR` is empty, deletes root | `rm -rf "${DIR:?}/"` |
| Parsing with `ls` | Fragile, breaks on special chars | Use `find` or globs |
| Not handling exit codes | Silent failure | Check `$?` or use `||` |

---

### Useful One-Liners for DevOps

```bash
# Check disk usage, sort by size
du -sh /var/log/* | sort -rh | head -10

# Find and kill process by name
pkill -f "python app.py"

# Watch a command every 2 seconds
watch -n 2 'kubectl get pods'

# Extract unique IPs from access log
awk '{print $1}' access.log | sort -u

# Count occurrences of each HTTP status code
awk '{print $9}' access.log | sort | uniq -c | sort -rn

# Tail multiple log files at once
tail -f /var/log/app/*.log

# Test if port is open
timeout 3 bash -c "</dev/tcp/host/port" && echo "open" || echo "closed"

# Run command on multiple servers
for h in web-01 web-02 web-03; do ssh "$h" "uptime"; done

# Base64 encode/decode
echo "secret" | base64
echo "c2VjcmV0Cg==" | base64 -d

# Generate random password
openssl rand -base64 16
```
