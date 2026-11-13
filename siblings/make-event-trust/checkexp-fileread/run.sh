#!/bin/bash
# Usage: run.sh /path/to/saved_acl2
#
# Two make-events whose expansion reads an external file data.txt.  The file is
# CERT_VALUE at certify time and INCLUDE_VALUE at include time.
#
#  bdef.lisp  default make-event (no :check-expansion):  include-book SILENTLY
#             installs the frozen RECORDED expansion (defconst *payload*
#             'CERT_VALUE); the include-time file is ignored.  This diverges
#             from a faithful re-run, but the recorded defconst is
#             self-consistent, so it is sound.  DOCUMENTED (make-event records
#             and reuses its expansion); no divergence warning is printed.
#  bchk.lisp  same with :CHECK-EXPANSION T: include-book RE-RUNS the form, finds
#             (defconst *payload* 'INCLUDE_VALUE) != recorded, and REFUSES
#             ("The current MAKE-EVENT expansion differs ...").  This is the
#             safe mode -- re-derivation plus an equality check.
ACL2=${1:?path to saved_acl2}; cd "$(dirname "$0")" || exit 2
tag=$(basename "$(dirname "$ACL2")")
echo "### host image: $tag"
for b in bdef bchk; do
  rm -f $b.cert $b.port *.lx64fsl *.fasl *.o 2>/dev/null
  printf 'CERT_VALUE\n' > data.txt
  printf "(certify-book \"$b\" 0 nil)\n(quit)\n" | "$ACL2" > cert.$b.$tag.out 2>&1
  printf 'INCLUDE_VALUE\n' > data.txt
  printf "(include-book \"$b\")\n(cw \"@TAG $b payload ~x0~%%\" *payload*)\n(quit)\n" | "$ACL2" > inc.$b.$tag.out 2>&1
  refused=$(grep -azoiE 'current MAKE-EVENT[[:space:]]+expansion differs' inc.$b.$tag.out | tr -d '\0' | head -c1)
  echo "$b: cert=$([ -f $b.cert ] && echo yes || echo no) | include payload='$(grep -ao "@TAG.*" inc.$b.$tag.out)' | refused=$([ -n "$refused" ] && echo YES || echo no)"
done
printf 'CERT_VALUE\n' > data.txt   # leave repo file as committed
rm -f *.lx64fsl *.fasl *.o 2>/dev/null
