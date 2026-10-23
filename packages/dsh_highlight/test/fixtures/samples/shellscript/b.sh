export PATH="$HOME/bin:$PATH"
alias ll='ls -la --color=auto'
x=$(( 3 * (4 + 5) ))
files=$(find . -name '*.log' -mtime +7 | sort)
until ping -c1 -W1 example.org >/dev/null 2>&1; do sleep 1; done
trap 'rm -f "$tmp"; exit' INT TERM EXIT
tmp=$(mktemp)
awk -F: '{ print $1 }' /etc/passwd | grep -v '^#' > "$tmp"
if ! command -v jq &> /dev/null; then
  echo "jq missing" >&2
fi
function cleanup() {
  local dir=${1:?missing dir}
  rm -rf -- "${dir}"/*.tmp
}
echo ${#files} ${files%.log} ${files/old/new}
