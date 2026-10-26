#!/bin/sh
# babel end-to-end tests. Coordination script only: every check here inspects babel's
# output with independent tools (cmp, python3 -m json.tool); it implements nothing.
# usage: BABEL_ADAPTERS=<built omega-mv adapter clone> tests/run.sh [targets...]
# Optional: ZIG=<zig>, GO=<go> when those toolchains are not on PATH.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
B="$here/build/babel"
: "${BABEL_ADAPTERS:?set BABEL_ADAPTERS to a built omega-mv adapter clone}"
targets=${*:-rust c python cpp zig go}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }

# 1. lint: a statement starting with an unknown name silently becomes an assignment in
#    OM-2, so every bare statement word must be a defined function or a host word.
awk '/^fn /{print $2}' "$here"/build/babel.om | sort -u > "$work/fns"
cat "$here"/src/*.om | awk '$1 ~ /^[a-z][a-z0-9]*$/ && $2 != "=" {print $1}' | sort -u \
  | grep -vxF -f "$work/fns" \
  | grep -vxE 'if|while|for|end|else|ret|put|break|continue|note|text|global|fn|elif|exit|reset' > "$work/lint"
if [ -s "$work/lint" ]; then bad "lint: unknown statement words: $(tr '\n' ' ' < "$work/lint")"; else ok "lint"; fi

# 2. usage paths
"$B" --version > /dev/null; [ $? -eq 0 ] && ok "--version" || bad "--version"
"$B" > /dev/null 2>&1; [ $? -eq 2 ] && ok "no path exits 2" || bad "no path exits 2"
"$B" "$here/examples/sample" --adapters "$BABEL_ADAPTERS" < /dev/null > /dev/null 2>&1; r=$?
[ $r -eq 64 ] && ok "no --to without a terminal exits 64" || bad "no --to without a terminal exits 64 (got $r)"

# 3. every target on the sample: exit status, verdict counts, JSON validity, independent cmp
cp -r "$here/examples/sample" "$work/sample"
for t in $targets; do
  (cd "$work" && "$B" sample --to "$t" --adapters "$BABEL_ADAPTERS" --json > "$work/$t.json" 2> "$work/$t.err")
  r=$?
  [ $r -eq 0 ] && ok "$t: exit 0" || { bad "$t: exit $r"; cat "$work/$t.err"; }
  if python3 -m json.tool "$work/$t.json" > /dev/null && python3 -m json.tool "$work/sample.babel/report.json" > /dev/null; then
    ok "$t: --json and report.json parse"
  else
    bad "$t: JSON does not parse"
  fi
  s=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["summary"]; print(d["translated"],d["unsupported"],d["missing_implementation"],d["fail"],d["not_run"],d["absorbed"])' "$work/sample.babel/report.json")
  [ "$s" = "5 7 5 0 0 2" ] && ok "$t: verdicts 5 TRANSLATED / 7 UNSUPPORTED / 5 MISSING / 0 FAIL / 0 NOT_RUN / 2 ABSORBED" || bad "$t: verdicts $s"
  f0=$fails
  for u in fold square add3 poly mix6; do
    d="$work/sample.babel/diff/$u"
    n=$(head -1 "$d/vectors.txt" | cut -d' ' -f2)
    if [ -s "$d/c-original.out" ] && cmp -s "$d/c-original.out" "$d/omega.out" && cmp -s "$d/c-original.out" "$d/target.out" \
       && [ "$(wc -l < "$d/c-original.out")" -eq "$n" ]; then
      :
    else
      bad "$t: $u three legs not byte-identical (independent cmp)"
    fi
  done
  [ $fails -eq $f0 ] && ok "$t: independent cmp: 3 legs byte-identical, one line per vector, 5 units"
done

# 4. negative control: a cc wrapper that changes fold's original C (- k becomes + k)
#    when it compiles the differential oracle. babel must report FAIL, never TRANSLATED.
mkdir -p "$work/bin"
realcc=$(command -v cc)
cat > "$work/bin/cc" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    */diff/fold/oracle.c)
      sed 's/h \* k + h - k/h * k + h + k/' "\$a" > "$work/mut.c"
      grep -q 'h \* k + h + k' "$work/mut.c" || { echo "mutation did not apply" >&2; exit 99; }
      set -- \$(for b in "\$@"; do [ "\$b" = "\$a" ] && echo "$work/mut.c" || echo "\$b"; done)
      ;;
  esac
done
exec "$realcc" "\$@"
EOF
chmod +x "$work/bin/cc"
(cd "$work" && PATH="$work/bin:$PATH" "$B" sample --to c --adapters "$BABEL_ADAPTERS" > "$work/neg.out" 2>&1)
r=$?
v=$(python3 -c 'import json,sys
for u in json.load(open(sys.argv[1]))["units"]:
    if u.get("name") == "fold": print(u["verdict"], u.get("reason",""))' "$work/sample.babel/report.json")
case "$v" in
  FAIL*differs*) ok "negative control: mutated oracle gives FAIL (exit $r): $v" ;;
  *) bad "negative control: expected FAIL, got exit $r: $v" ;;
esac
[ $r -eq 1 ] && ok "negative control: exit 1" || bad "negative control: exit $r, expected 1"

echo "failures: $fails"
[ $fails -eq 0 ]
