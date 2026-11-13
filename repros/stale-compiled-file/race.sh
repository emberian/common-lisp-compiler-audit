#!/bin/bash
# Usage: race.sh /path/to/includer_saved_acl2 /path/to/other_host_saved_acl2
#
# The same hole with no file times set or preserved by hand.  Two hosts share a
# book directory (compiled files have host-specific extensions, the certificate
# is shared).  The including host certifies the OLD book; the source is replaced
# by the NEW book and the other host certifies it at once.  certify-book on the
# other host removes only its own compiled file, and include-book accepts this
# host's old compiled file when its write date is >= the certificate's; file
# write dates have one-second resolution, so "at once" is enough.
ACL2=${1:?includer image}; OTHER=${2:?other host image}; cd "$(dirname "$0")" || exit 2
for try in 1 2 3 4 5 6 7 8; do
  rm -rf shared; mkdir shared
  cp book-old.lisp shared/book.lisp
  (cd shared && printf '(certify-book "book")\n(quit)\n' | "$ACL2" > certify-old.out 2>&1)
  cp book-new.lisp shared/book.lisp
  (cd shared && printf '(certify-book "book")\n(quit)\n' | "$OTHER" > certify-new.out 2>&1)
  (cd shared && "$ACL2" < ../check.lsp > ../race.out 2>&1)
  if grep -a -q '@R NIL proved: :YES' race.out; then break; fi
done
echo "attempt $try; files:"; (cd shared && stat -f '  %N %Sm' -t '%H:%M:%S' book.*)
echo "warnings printed by include-book: $(grep -a -c 'ACL2 Warning' race.out)"
grep -a -o '@R .*' race.out
