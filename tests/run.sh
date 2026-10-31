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

# 5. completion record (policy complete-v1) and --complete exit status.
#    comp DIR prints "state denominator covered n_open" from DIR/report.json and validates the JSON;
#    openl DIR prints one "kind|item|name|verdict|reason" line per open item.
comp() {
  python3 -m json.tool "$1/report.json" > /dev/null || { echo "JSON-INVALID"; return; }
  python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["completion"]; assert c["policy"]=="complete-v1"; print(c["state"],c["denominator"],c["covered"],len(c["open"]))' "$1/report.json"
}
openl() {
  python3 -c 'import json,sys
for o in json.load(open(sys.argv[1]))["completion"]["open"]: print("|".join(str(o[k]) for k in ("kind","item","name","verdict","reason")))' "$1/report.json"
}
# (f) legacy: no --complete, the sample still exits 0; the record is computed but not enforced
rm -rf "$work/sample.babel"
(cd "$work" && "$B" sample --to c --adapters "$BABEL_ADAPTERS" > "$work/cf.out" 2>&1); r=$?
s=$(comp "$work/sample.babel")
e=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["completion"]["enforced"])' "$work/sample.babel/report.json")
[ $r -eq 0 ] && [ "${s%% *}" = PARTIAL ] && [ "$e" = False ] && ok "complete (f): sample without --complete exits 0, record $s, enforced $e" \
  || bad "complete (f): exit $r, record $s, enforced $e"
# (a) the sample under --complete is PARTIAL (exit 3) and names its open items
rm -rf "$work/sample.babel"
(cd "$work" && "$B" sample --to c --adapters "$BABEL_ADAPTERS" --complete > "$work/ca.out" 2>&1); r=$?
s=$(comp "$work/sample.babel")
openl "$work/sample.babel" > "$work/ca.open"
if [ $r -eq 3 ] && [ "${s%% *}" = PARTIAL ] && [ "${s##* }" -gt 0 ] \
   && grep -q '^unit|src/mix.c:15-17|zero|UNSUPPORTED(68)|' "$work/ca.open" \
   && grep -q '^unit|tools/report.py:1|None|MISSING_IMPLEMENTATION|' "$work/ca.open" \
   && grep -q '^file|README.txt|None|MISSING_IMPLEMENTATION|' "$work/ca.open" \
   && grep -q '^## Completion' "$work/sample.babel/REPORT.md" && grep -q 'State: \*\*PARTIAL\*\*' "$work/sample.babel/REPORT.md"; then
  ok "complete (a): sample --complete exits 3, record $s (state den covered open), open list names zero, tools/report.py, README.txt"
else
  bad "complete (a): exit $r, record $s"; cat "$work/ca.open"
fi
# (d) negative control: the mutated oracle under --complete is FAILED (exit 1)
rm -rf "$work/sample.babel"
(cd "$work" && PATH="$work/bin:$PATH" "$B" sample --to c --adapters "$BABEL_ADAPTERS" --complete > "$work/cd.out" 2>&1); r=$?
s=$(comp "$work/sample.babel")
openl "$work/sample.babel" > "$work/cd.open"
if [ $r -eq 1 ] && [ "${s%% *}" = FAILED ] && grep -q '^unit|src/hash.c:3-5|fold|FAIL|' "$work/cd.open" \
   && grep -q '^check|src/hash.c:3-5|fold|FAIL|differential leg: Omega' "$work/cd.open"; then
  ok "complete (d) negative control: mutated oracle under --complete exits 1, record $s, fold unit and Omega leg FAIL"
else
  bad "complete (d): exit $r, record $s"; cat "$work/cd.open"
fi
# (b) examples/complete (three S1 functions + the stdint include) is COMPLETE (exit 0)
cp -r "$here/examples/complete" "$work/complete"
for t in c rust; do
  rm -rf "$work/complete.babel"
  (cd "$work" && "$B" complete --to "$t" --adapters "$BABEL_ADAPTERS" --complete > "$work/cb.out" 2>&1); r=$?
  s=$(comp "$work/complete.babel")
  set -- $s
  if [ $r -eq 0 ] && [ "$1" = COMPLETE ] && [ "$2" -eq "$3" ] && [ "$4" -eq 0 ] && grep -q 'State: \*\*COMPLETE\*\*' "$work/complete.babel/REPORT.md"; then
    ok "complete (b) $t: examples/complete --complete exits 0, record $s, covered == denominator"
  else
    bad "complete (b) $t: exit $r, record $s"; openl "$work/complete.babel"
  fi
done
# (c) negative controls: the same input plus one hidden file, or plus one symbolic link, is PARTIAL (exit 3)
for kind in hidden symlink; do
  rm -rf "$work/cc" "$work/cc.babel"
  cp -r "$here/examples/complete" "$work/cc"
  if [ $kind = hidden ]; then
    echo 'uint64_t ghost(uint64_t x) { return x; }' > "$work/cc/src/.ghost.c"; want='^skipped|src/.ghost.c|None|SKIPPED|hidden'
  else
    ln -s arith.c "$work/cc/src/alias.c"; want='^skipped|src/alias.c|None|SKIPPED|symbolic link'
  fi
  (cd "$work" && "$B" cc --to c --adapters "$BABEL_ADAPTERS" --complete > "$work/ccc.out" 2>&1); r=$?
  s=$(comp "$work/cc.babel")
  openl "$work/cc.babel" > "$work/cc.open"
  if [ $r -eq 3 ] && [ "${s%% *}" = PARTIAL ] && [ "$(wc -l < "$work/cc.open")" -eq 1 ] && grep -q "$want" "$work/cc.open"; then
    ok "complete (c) negative control ($kind): exits 3, record $s, the only open item: $(cut -d'|' -f2,4 "$work/cc.open")"
  else
    bad "complete (c) $kind: exit $r, record $s"; cat "$work/cc.open"
  fi
done
# (e) a missing target toolchain is BLOCKED (exit 4)
rm -rf "$work/complete.babel"
(cd "$work" && ZIG=/nonexistent "$B" complete --to zig --adapters "$BABEL_ADAPTERS" --complete > "$work/ce.out" 2>&1); r=$?
s=$(comp "$work/complete.babel")
openl "$work/complete.babel" > "$work/ce.open"
if [ $r -eq 4 ] && [ "${s%% *}" = BLOCKED ] && grep -q '^toolchain|zig|None|NOT_RUN|' "$work/ce.open" \
   && grep -q '^check|src/arith.c:3-5|blend|NOT_RUN|differential leg: target zig did not run' "$work/ce.open"; then
  ok "complete (e): ZIG=/nonexistent --to zig --complete exits 4, record $s"
else
  bad "complete (e): exit $r, record $s"; cat "$work/ce.open"
fi

echo "failures: $fails"
[ $fails -eq 0 ]
