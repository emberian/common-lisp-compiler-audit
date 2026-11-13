#!/bin/bash
# Usage: run.sh /path/to/saved_acl2
#
# A compiled file left over from an OLDER version of a book is loaded by
# include-book whenever its write date is >= that of the certificate.  No other
# check ties it to the book.  Deterministic variant, using only "cp -p":
#
#   1. server/: the NEW book is certified first (say, a shared build).
#   2. local/:  two seconds later the OLD book is certified here (compiled file).
#   3. the new book.lisp and book.cert are copied into local/ with their times
#      preserved (cp -p, like rsync -t or unpacking an archive); the compiled
#      file is not part of the copy.
#   4. a fresh session does (include-book "book") in local/.
#
# Expected: a [Compiled file] warning and the new definitions, or a refusal.
ACL2=${1:?path to saved_acl2}; cd "$(dirname "$0")" || exit 2
rm -rf server local; mkdir server local
cp book-new.lisp server/book.lisp
(cd server && printf '(certify-book "book")\n(quit)\n' | "$ACL2" > certify.out 2>&1)
sleep 2
cp book-old.lisp local/book.lisp
(cd local && printf '(certify-book "book")\n(quit)\n' | "$ACL2" > certify.out 2>&1)
cp -p server/book.lisp server/book.cert local/
(cd local && "$ACL2" < ../check.lsp > ../include.out 2>&1)
echo "new certificate in place: $(cmp -s server/book.cert local/book.cert && echo yes || echo no)"
echo "warnings printed by include-book: $(grep -a -c 'ACL2 Warning' include.out)"
grep -a -o '@R .*' include.out
