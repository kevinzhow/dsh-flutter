#!/bin/sh
# Edge cases: arithmetic, process substitution, case, here-strings, indented heredoc.
readonly NAME="world"
count=0
case "$1" in
  start|run) echo "starting $NAME";;
  stop) echo 'stopping' ;;
  *.txt) cat -- "$1" ;;
  *) echo "unknown: ${1:-none}" >&2; exit 1 ;;
esac
diff <(sort a.txt) <(sort b.txt) | head -n 5
while read -r line; do
  ((count++))
  [[ $line =~ ^([a-z]+)=([0-9]+)$ ]] && echo "${BASH_REMATCH[1]}"
done <<< "k=1"
cat <<-EOF
	indented heredoc $NAME
	EOF
for ((i = 0; i < 3; i++)); do echo $i; done
arr=(one two three); echo "${arr[@]:1:2} ${#arr[@]} ${!arr[@]}"
echo "$(date +%s)" `whoami` $'ansi\tstring' $"locale"
f() { local -r x=$1; return $(( x > 0 )); }
if [ "$(id -u)" -eq 0 ] || [ -w /tmp ]; then echo ok; fi
echo "a" > /dev/null 2>&1 &
wait $!
curl -sS "https://example.org/api?x=1&y=2" -H 'Accept: application/json' | jq -r '.items[] | .name'
export FOO=bar BAZ="qux quux"
