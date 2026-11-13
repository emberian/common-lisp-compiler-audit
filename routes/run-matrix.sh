#!/bin/bash
# Route matrix: one generated book of typed REF/OPT function pairs, queried
# through every route by which its code can reach an ACL2 image.
#
#   session  defuns admitted and compiled in the running image (guard checking :all)
#   gc-t, gc-none  the same queries under guard checking T and :NONE
#   memo1/2  the OPT functions memoized (table miss, then table hit)
#   redo     undo to before the first function, re-admit
#   book     certify-book in a fresh image, include-book in another (fasl load)
#   image    save-exec after admission, queries run in the restarted image
#
# Every route replays the same queries.  Each query compares the logical value
# (REF under :all guard checking) with the raw value (OPT) inside that route,
# and prints a residue of the logical value so routes can be compared with each
# other.  Usage: run-matrix.sh SEED NFUNCTIONS HOST WORKDIR   (HOST: head | ccl)
set -u
SEED=$1; N=$2; HOST=$3; W=$4
ACL2=/Users/ember/dev/acl2-fix/$HOST-worktree/saved_acl2
GEN=/Users/ember/dev/compiler-audit/synth/synth.lisp
mkdir -p "$W" && cd "$W" || exit 2
rm -f book.cert book.port book.*fsl book.fasl sub.cert sub.port sub.*fsl sub.fasl zimg* ./*.out ./*.rec
# PREGEN=1: the work directory already holds a generated program (book.lisp,
# queries.lisp, memo.lisp, unmemo.lisp and optionally sub.lisp, portcullis.lisp).
if [ "${PREGEN:-0}" != 1 ]; then
  /opt/homebrew/bin/sbcl --script "$GEN" "$SEED" "$N" "$W/" || exit 2
fi
# Context envelope: an included sub-book is certified first; portcullis
# commands are run before the book in every route that starts from a bare image.
PORT=""; [ -f portcullis.lisp ] && PORT='(ld "portcullis.lisp")'
if [ -f sub.lisp ]; then
  printf '(in-package "ACL2")\n(certify-book "sub" 0 t :skip-proofs-okp t)\n(quit)\n' > s0.lisp
  nice -n 15 timeout 900 "$ACL2" < s0.lisp > s0.out 2>&1
fi

# The same queries with guard checking T and :NONE (first line of the file sets the mode).
sed '1s/:all/t/' queries.lisp > queries-t.lisp
sed '1s/:all/:none/' queries.lisp > queries-none.lisp

QUIET="(set-inhibit-output-lst (remove1 'comment *valid-output-names*))"
# FAST=1: only the session and book routes (used when one program is crossed
# with many contexts).
ROUTES="session gc-t gc-none memo1 memo2 redo book image"
if [ "${FAST:-0}" = 1 ]; then
ROUTES="session book"
cat > s1.lisp <<EOF
(in-package "ACL2")
$QUIET
$PORT
(ld "book.lisp")
(cw "@ROUTE session~%")
(ld "queries.lisp" :ld-error-action :continue)
(quit)
EOF
else
cat > s1.lisp <<EOF
(in-package "ACL2")
$QUIET
$PORT
(ld "book.lisp")
(cw "@ROUTE session~%")
(ld "queries.lisp" :ld-error-action :continue)
(cw "@ROUTE gc-t~%")
(ld "queries-t.lisp" :ld-error-action :continue)
(cw "@ROUTE gc-none~%")
(ld "queries-none.lisp" :ld-error-action :continue)
(ld "memo.lisp")
(cw "@ROUTE memo1~%")
(ld "queries.lisp" :ld-error-action :continue)
(cw "@ROUTE memo2~%")
(ld "queries.lisp" :ld-error-action :continue)
(ld "unmemo.lisp")
(ubt! 'zhash)
(ld "book.lisp")
(cw "@ROUTE redo~%")
(ld "queries.lisp" :ld-error-action :continue)
(assign zroute-marker 'saved-image)
:q
(save-exec "zimg" nil)
EOF
fi
printf '(in-package "ACL2")\n%s\n(certify-book "book" ? t :skip-proofs-okp t)\n(quit)\n' "$PORT" > s2.lisp
cat > s3.lisp <<EOF
(in-package "ACL2")
(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment warning)))
(include-book "book")
(cw "@ROUTE book~%")
(ld "queries.lisp" :ld-error-action :continue)
(quit)
EOF
cat > s4.lisp <<EOF
$QUIET
(cw "@ROUTE image~%")
(cw "@E ~x0~%" (@ zroute-marker))
(ld "queries.lisp" :ld-error-action :continue)
(quit)
EOF

nice -n 15 timeout 1500 "$ACL2" < s1.lisp > s1.out 2>&1
nice -n 15 timeout 900 "$ACL2" < s2.lisp > s2.out 2>&1
nice -n 15 timeout 900 "$ACL2" < s3.lisp > s3.out 2>&1
# IMG_TIMEOUT: the restarted CCL image can hang in a stobj array store (finding F3).
if [ -x zimg ]; then nice -n 15 timeout ${IMG_TIMEOUT:-900} ./zimg < s4.lisp > s4.out 2>&1; else : > s4.out; fi
rm -f zimg zimg.core zimg.*   # the saved image is large and only needed for s4

cat s1.out s3.out s4.out | grep -o '@[A-Z]* .*\|@END' |
  awk '/^@ROUTE/ {r=$2; next} r!="" {print > (r ".rec")}'

expected=$(grep -c '"@Q ' queries.lisp)
status=0
printf '%-8s %8s %6s %6s %8s %5s %7s %s\n' route queries ok diff control end unverif same-as-session
for r in $ROUTES; do
  f=$r.rec; [ -f "$f" ] || : > "$f"
  q=$(grep -c '^@Q' "$f"); ok=$(grep -c '^@Q.*:OK$' "$f"); d=$(grep -c '^@Q.*:DIFF$' "$f")
  c=$(grep '^@C' "$f" | cut -d' ' -f2); e=$(grep -c '^@END' "$f")
  if diff -q <(grep '^@Q' session.rec) <(grep '^@Q' "$f") > /dev/null; then same=yes; else same=NO; fi
  g=$(grep '^@G' "$f" | cut -d' ' -f2)
  printf '%-8s %8s %6s %6s %8s %5s %7s %s\n' "$r" "$q/$expected" "$ok" "$d" "${c:-MISSING}" "$e" "${g:-?}" "$same"
  [ "${g:-}" = 0 ] || status=1
  # Queries discarded by the reference twin (invalid input or unsound inference)
  # are allowed but reported; a route must discard exactly what session does.
  [ "$q" -gt 0 ] && [ "$d" = 0 ] && [ "${c:-}" = ":DIFF" ] && [ "$same" = yes ] || status=1
done
# ACL2 warns "[Compiled file]" when include-book falls back to source.
fallback=$(grep -c 'Compiled file' s3.out)
[ "$fallback" = 0 ] || status=1
# An uncertified book still loads (from source), which would silently void the book route.
[ -f book.cert ] || status=1
if [ -f sub.lisp ]; then [ -f sub.cert ] || status=1; fi
[ -n "$(ls book.*fsl book.fasl 2>/dev/null | head -1)" ] || status=1
echo "book certified: $([ -f book.cert ] && echo yes || echo NO)   compiled file: $(ls book.*fsl book.fasl 2>/dev/null | head -1)   fasl-load fallback warnings: $fallback   image marker: $(grep '^@E ' image.rec | cut -d' ' -f2)"
exit $status
