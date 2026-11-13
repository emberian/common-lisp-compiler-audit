#!/bin/bash
# Usage: run.sh /path/to/saved_acl2
#
# top.lisp is certified in a world whose portcullis is (include-book "sub").
# sub.lisp is then changed and recertified.  (include-book "top") in a new
# session should fail softly and say that sub's book-hash no longer matches
# (or include top as uncertified with a warning).  Instead it aborts from raw
# Lisp with "There is a problem with the certificate, which may be described
# below in detail." and no detail; when ACL2 reads its commands from a pipe, the
# forms after the include-book are discarded as well.
ACL2=${1:?path to saved_acl2}; cd "$(dirname "$0")" || exit 2
rm -f sub.* top.* ./*.out
printf '(in-package "ACL2")\n(defun sf (x) (cons x 1))\n' > sub.lisp
printf '(in-package "ACL2")\n(defun tf (x) (sf x))\n' > top.lisp
printf '(certify-book "sub")\n(quit)\n' | "$ACL2" > certify-sub.out 2>&1
printf '(include-book "sub")\n(certify-book "top" 1)\n(quit)\n' | "$ACL2" > certify-top.out 2>&1
sleep 1
printf '(in-package "ACL2")\n(defun sf (x) (cons x 22))\n' > sub.lisp
printf '(certify-book "sub")\n(quit)\n' | "$ACL2" > recertify-sub.out 2>&1
printf '(include-book "top")\n(cw "@R next form was evaluated~%%")\n(quit)\n' | "$ACL2" > include.out 2>&1
echo "certificates: $(ls sub.cert top.cert 2>/dev/null | tr '\n' ' ')"
echo "raw Lisp aborts: $(grep -a -c 'ABORTING from raw Lisp' include.out)"
grep -a 'Error:' include.out
echo "mentions of book-hash or sub.lisp in the include output: $(grep -a -c 'book-hash\|sub\.lisp' include.out)"
echo "forms after the include-book evaluated: $(grep -a -c '@R next form' include.out)"
