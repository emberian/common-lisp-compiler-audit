#!/bin/bash
# Stale / missing / foreign artifact scenarios for certify-book + include-book.
#
#   run.sh HOST [SCENARIO...]      HOST: head (SBCL) | ccl
#
# Scenarios are the rows of scenarios.tsv (id, expected, group, description);
# each has a function sc_<id> in scenarios.sh.  One ACL2 process runs at a time
# per invocation.  Results go to results-HOST.tsv:
#   id  expected  observed  verdict  included/certified  warnings  control  description
#
# observed:
#   equal          include succeeded, no warning, records = fresh ld of current sources
#   warned-equal   as equal, and ACL2 printed a warning (the tags are listed;
#                  [Skip-proofs] is not counted)
#   refused        include-book did not add the book.  Where the scenario models
#                  "nothing was included" as its reference (session conflicts),
#                  the records after the failed include are compared with it and
#                  "refused-DIRTY" means the failed include changed the session.
#   STALE-silent   records differ from the reference and no warning was printed
#   STALE-warned   records differ from the reference; a warning was printed
#   ERROR          timeout, Lisp crash, or implementation error
# control: ok when the reference records differ from those of the stale version
#   (so the comparison could have seen stale code), "-" when the scenario has no
#   stale version, FAIL when it has one and the queries cannot tell.
set -u
cd "$(dirname "$0")" || exit 2
. ./lib.sh
host_setup "${1:?host}"; shift
. ./scenarios.sh
WORK=$ROOT/work-$HOST
mkdir -p "$WORK"
RES=$ROOT/results-$HOST.tsv
want=" $* "
[ $# -eq 0 ] && : > "$RES"

classify() { # in $W: inc.out ref.out [ctl.out]; prints observed<TAB>inc<TAB>warnings<TAB>control
  local obs warn n ncert ex control
  rec inc.out > inc.rec; rec ref.out > ref.rec 2>/dev/null
  warn=$(grep -a -o 'ACL2 Warning \[[^]]*\]' inc.out | sed 's/ACL2 Warning \[\(.*\)\]/\1/' | grep -v -x 'Skip-proofs' | sort -u | paste -sd, -)
  n=$(grep -a -o '@I [0-9]* [0-9]*' inc.out | head -1 | cut -d' ' -f2)
  ncert=$(grep -a -o '@I [0-9]* [0-9]*' inc.out | head -1 | cut -d' ' -f3)
  ex=$(grep -a -o '@EXIT [0-9]*' inc.out | cut -d' ' -f2)
  if [ -s setup.err ]; then obs=SETUP-FAILED
  elif grep -a -q '@LD :FAILED' ref.out; then obs=REF-FAILED
  elif [ "$ex" != 0 ] || grep -a -q 'Implementation error\|Unhandled memory fault\|fatal error\|Fatal error\|debugger invoked\|Contact the ACL2 implementors' inc.out; then obs=ERROR
  elif [ "${n:-0}" -lt "${INCN:-1}" ]; then
    if [ -z "${DIRTYCHK:-}" ] || diff -q inc.rec ref.rec > /dev/null; then obs=refused; else obs=refused-DIRTY; fi
  elif diff -q inc.rec ref.rec > /dev/null && [ -s inc.rec ]; then
    if [ -n "$warn" ]; then obs=warned-equal; else obs=equal; fi
  else
    if [ -n "$warn" ]; then obs=STALE-warned; else obs=STALE-silent; fi
  fi
  if [ -f ctl.out ]; then
    rec ctl.out > ctl.rec
    if diff -q ctl.rec ref.rec > /dev/null; then control=FAIL; else control=ok; fi
  else control=-; fi
  printf '%s\t%s\t%s\t%s' "$obs" "${n:-?}/${ncert:-?}" "${warn:--}" "$control"
}

while IFS=$'\t' read -r id expected group desc; do
  case $id in ''|'#'*) continue ;; esac
  if [ "$want" != "  " ]; then case $want in *" $id "*) ;; *) continue ;; esac; fi
  W=$WORK/$id
  rm -rf "$W"; mkdir -p "$W"
  out=$(
    cd "$W" || exit 2
    INCN=1
    "sc_$id" > scenario.log 2>&1
    [ -f inc.out ] || echo "no inc.out" >> setup.err
    [ -f ref.out ] || : > ref.out
    echo "INCN=$INCN" > incn; classify
  )
  obs=${out%%$'\t'*}
  if echo "$obs" | grep -q -x -E "$expected"; then verdict=as-expected; else verdict=UNEXPECTED; fi
  rm -f "$W"/zimg*   # saved images are large
  line=$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$id" "$expected" "$obs" "$verdict" "${out#*$'\t'}" "$desc")
  echo "$line"
  if [ $# -eq 0 ]; then echo "$line" >> "$RES"
  else # single-scenario rerun: replace the row
    if [ -f "$RES" ]; then grep -v "^$id	" "$RES" > "$RES.tmp"; echo "$line" >> "$RES.tmp"; mv "$RES.tmp" "$RES"; else echo "$line" > "$RES"; fi
  fi
done < scenarios.tsv
# keep the rows in table order
if [ -f "$RES" ]; then
  grep -v '^#' scenarios.tsv | cut -f1 | while read -r id; do grep "^$id	" "$RES" | tail -1; done > "$RES.tmp"; mv "$RES.tmp" "$RES"
fi
