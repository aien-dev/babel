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

# 6. --exclude manifest. exl DIR prints "excluded_count walked_as" and one "kind|item|reason|matched_by"
#    line per excluded item. Manifests live in $work, outside the walked tree, unless a test says so.
exl() {
  python3 -c 'import json,sys
c=json.load(open(sys.argv[1]))["completion"]; m=c["manifest"]
assert c["excluded_count"]==len(c["excluded"])
print(c["excluded_count"], m["walked_as"] if m else "-")
for x in c["excluded"]: assert x["verdict"]=="EXCLUDED"; print("|".join(str(x[k]) for k in ("kind","item","reason","matched_by")))' "$1/report.json"
}
rm -rf "$work/cg" "$work/cg.babel"
cp -r "$here/examples/complete" "$work/cg"
echo 'notes for people' > "$work/cg/README.txt"
# (g) README.txt makes it PARTIAL (exit 3); a manifest excluding it with a reason makes it COMPLETE (exit 0)
(cd "$work" && "$B" cg --to c --adapters "$BABEL_ADAPTERS" --complete > "$work/cg0.out" 2>&1); r0=$?
s0=$(comp "$work/cg.babel")
printf '# documentation is not translated\n\nREADME.txt   human notes, no code \n' > "$work/g.exclude"
(cd "$work" && "$B" cg --to c --adapters "$BABEL_ADAPTERS" --complete --exclude g.exclude --no-color > "$work/cg1.out" 2>&1); r1=$?
s1=$(comp "$work/cg.babel")
exl "$work/cg.babel" > "$work/cg1.exl"
sha8=$(sha256sum "$work/g.exclude" | cut -c1-8)
set -- $s0; d0=$2
set -- $s1
if [ $r0 -eq 3 ] && [ "${s0%% *}" = PARTIAL ] && [ $r1 -eq 0 ] && [ "$1" = COMPLETE ] && [ "$2" -eq "$d0" ] && [ "$4" -eq 0 ] \
   && [ "$(head -1 "$work/cg1.exl")" = "1 None" ] && grep -qx 'file|README.txt|human notes, no code|README.txt' "$work/cg1.exl" \
   && grep -q "COMPLETE  $3 of $2 items covered, 1 excluded by manifest $sha8" "$work/cg1.out" \
   && grep -qF '| file | `README.txt` | EXCLUDED | `README.txt` (line 3) | human notes, no code |' "$work/cg.babel/REPORT.md"; then
  ok "complete (g): +README.txt exits $r0 ($s0); --exclude README.txt exits 0, record $s1, denominator unchanged $d0, excluded_count 1, manifest $sha8"
else
  bad "complete (g): exits $r0/$r1, records $s0 / $s1"; cat "$work/cg1.exl" "$work/cg1.out"
fi
# (g2) the manifest inside the walked tree is counted (covered); a hidden non-source entry may be excluded
printf 'x\n' > "$work/cg/.gitignore"
printf 'README.txt human notes\n.gitignore VCS metadata, no code\n' > "$work/cg/babel.exclude"
(cd "$work" && "$B" cg --to c --adapters "$BABEL_ADAPTERS" --complete --exclude cg/babel.exclude > "$work/cg2.out" 2>&1); r=$?
s=$(comp "$work/cg.babel")
exl "$work/cg.babel" > "$work/cg2.exl"
set -- $s
if [ $r -eq 0 ] && [ "$1" = COMPLETE ] && [ "$2" -eq $((d0 + 2)) ] && [ "$3" -eq "$d0" ] && [ "$(head -1 "$work/cg2.exl")" = "2 babel.exclude" ] \
   && grep -qx 'skipped|.gitignore|VCS metadata, no code|.gitignore' "$work/cg2.exl"; then
  ok "complete (g2): in-tree manifest covered, .gitignore excluded: exits 0, record $s, excluded_count 2, walked_as babel.exclude"
else
  bad "complete (g2): exit $r, record $s"; cat "$work/cg2.exl"; openl "$work/cg.babel"
fi
rm -f "$work/cg/.gitignore" "$work/cg/babel.exclude"
# (h)-(k) negative controls: each bad manifest exits 2 with a line diagnostic and writes no output folder
xneg() { # name manifest-text expected-stderr
  rm -rf "$work/cg.babel"
  printf "$2" > "$work/$1.exclude"
  (cd "$work" && "$B" cg --to c --adapters "$BABEL_ADAPTERS" --complete --exclude "$1.exclude" > "$work/$1.out" 2>&1); r=$?
  if [ $r -eq 2 ] && grep -qF "$3" "$work/$1.out" && [ ! -e "$work/cg.babel" ]; then
    ok "complete ($1) negative control: exits 2, no output folder: $(grep -- '--exclude' "$work/$1.out" | head -1)"
  else
    bad "complete ($1): exit $r, expected 2 and /$3/"; cat "$work/$1.out"
  fi
}
xneg h 'src/arith.c not wanted\n' "line 1: entry names source babel splits, which cannot be excluded: src/arith.c -> src/arith.c"
xneg h2 'src/ the whole tree\n' "line 1: entry names source babel splits, which cannot be excluded: src -> src/arith.c"
xneg i 'README.txt human notes\nnothere.txt gone\n' "line 2: entry matches nothing in the walked tree (stale manifest): nothere.txt"
xneg j '# no reason below\nREADME.txt\n' "line 2: entry has no reason (each line is <path> <reason>): README.txt"
xneg j2 'src/*.txt glob\n' "line 1: globs are not supported"
echo 'uint64_t ghost(uint64_t x) { return x; }' > "$work/cg/src/.ghost.c"
xneg k 'README.txt human notes\nsrc/.ghost.c hidden scratch\n' "line 2: entry names source babel splits, which cannot be excluded: src/.ghost.c -> src/.ghost.c"
rm -f "$work/cg/src/.ghost.c"
ln -s arith.c "$work/cg/src/alias.c"
xneg k2 'README.txt human notes\nsrc/alias.c a link\n' "line 2: entry names source babel splits, which cannot be excluded: src/alias.c -> src/alias.c"
rm -f "$work/cg/src/alias.c"

# 7. completion gaps: other non-regular file, unreadable directory, missing cc, failing generated test
rm -rf "$work/cf" "$work/cf.babel"
cp -r "$here/examples/complete" "$work/cf"
mkfifo "$work/cf/src/pipe"
(cd "$work" && "$B" cf --to c --adapters "$BABEL_ADAPTERS" --complete > "$work/cf7.out" 2>&1); r=$?
s=$(comp "$work/cf.babel"); openl "$work/cf.babel" > "$work/cf7.open"
if [ $r -eq 3 ] && [ "${s%% *}" = PARTIAL ] && [ "$(wc -l < "$work/cf7.open")" -eq 1 ] && grep -q '^skipped|src/pipe|None|SKIPPED|not a regular file' "$work/cf7.open"; then
  ok "complete gap (fifo): exits 3, record $s, the only open item: $(cut -d'|' -f2,4,5 "$work/cf7.open")"
else
  bad "complete gap (fifo): exit $r, record $s"; cat "$work/cf7.open"
fi
rm -f "$work/cf/src/pipe"
if [ "$(id -u)" = 0 ]; then
  echo "NOT_RUN (root) complete gap (unreadable directory): root reads a mode-000 directory"
else
  mkdir "$work/cf/locked"; echo x > "$work/cf/locked/a.txt"; chmod 000 "$work/cf/locked"
  trap 'chmod 755 "$work/cf/locked" 2>/dev/null; rm -rf "$work"' EXIT
  (cd "$work" && "$B" cf --to c --adapters "$BABEL_ADAPTERS" --complete > "$work/cu.out" 2>&1); r=$?
  chmod 755 "$work/cf/locked"; rm -rf "$work/cf/locked"
  s=$(comp "$work/cf.babel"); openl "$work/cf.babel" > "$work/cu.open"
  if [ $r -eq 3 ] && [ "${s%% *}" = PARTIAL ] && [ "$(wc -l < "$work/cu.open")" -eq 1 ] && grep -q '^skipped|locked|None|SKIPPED|directory could not be read' "$work/cu.open"; then
    ok "complete gap (unreadable directory): exits 3, record $s, the only open item: $(cut -d'|' -f2,4,5 "$work/cu.open")"
  else
    bad "complete gap (unreadable directory): exit $r, record $s"; cat "$work/cu.open"
  fi
fi
# a PATH with every tool but cc: the oracle cannot be built, so the run is BLOCKED (exit 4)
mkdir "$work/nocc"
for d in $(echo "$PATH" | tr ':' ' '); do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    n=${f##*/}; [ "$n" = cc ] && continue; [ -e "$work/nocc/$n" ] || [ -L "$work/nocc/$n" ] || ln -s "$f" "$work/nocc/$n"
  done
done
(cd "$work" && PATH="$work/nocc" "$B" cf --to python --adapters "$BABEL_ADAPTERS" --complete > "$work/cn.out" 2>&1); r=$?
s=$(comp "$work/cf.babel"); openl "$work/cf.babel" > "$work/cn.open"
if [ $r -eq 4 ] && [ "${s%% *}" = BLOCKED ] && grep -q '^toolchain|cc|None|NOT_RUN|cc was not found' "$work/cn.open" && ! grep -q '|FAIL|' "$work/cn.open"; then
  ok "complete gap (no cc): exits 4, record $s, $(grep -c NOT_RUN "$work/cn.open") NOT_RUN items incl. toolchain cc"
else
  bad "complete gap (no cc): exit $r, record $s"; cat "$work/cn.open"
fi
# a cargo that fails only "cargo test": the generated target test is the one FAIL (exit 1)
realcargo=$(command -v cargo)
mkdir "$work/cbin"
printf '#!/bin/sh\nif [ "$1" = test ]; then echo "shim: cargo test forced to fail" >&2; exit 101; fi\nexec "%s" "$@"\n' "$realcargo" > "$work/cbin/cargo"
chmod +x "$work/cbin/cargo"
(cd "$work" && PATH="$work/cbin:$PATH" "$B" cf --to rust --adapters "$BABEL_ADAPTERS" --complete > "$work/ct.out" 2>&1); r=$?
s=$(comp "$work/cf.babel"); openl "$work/cf.babel" > "$work/ct.open"
if [ $r -eq 1 ] && [ "${s%% *}" = FAILED ] && [ "$(wc -l < "$work/ct.open")" -eq 1 ] && grep -q '^check|diff/test.log|None|FAIL|generated target test failed (see diff/test.log), exit 101' "$work/ct.open"; then
  ok "complete gap (generated test): cargo test fails, exits 1, record $s, the only open item: $(cut -d'|' -f2,4,5 "$work/ct.open")"
else
  bad "complete gap (generated test): exit $r, record $s"; cat "$work/ct.open"
fi
echo "NOT_RUN complete gap (lstat failure, skip reason 6): no unprivileged way to make lstat fail on an entry getdents returned"

echo "failures: $fails"
[ $fails -eq 0 ]
