#!/bin/bash
# Usage: run.sh /path/to/saved_acl2
#
# Ordinary edit cycle, no file is touched by hand: sub.lisp defines an inline
# function and a macro, top.lisp includes sub and uses both.  Both books are
# certified.  sub.lisp is edited and recertified; top is not.
# (include-book "top") then prints an [Uncertified] warning ("recertification is
# probably required") and still loads top's old compiled file and takes top's
# translated bodies from its old certificate.  tf then runs the old inlined
# code while its logical definition calls the new si, and *tc* has the old
# macro's value.
ACL2=${1:?path to saved_acl2}; cd "$(dirname "$0")" || exit 2
rm -f sub.* top.* ./*.out
printf '(in-package "ACL2")\n(defmacro sm (x) `(cons ,x (quote old)))\n(defun-inline si (x) (declare (xargs :guard t)) (cons x (quote old)))\n' > sub.lisp
printf '(in-package "ACL2")\n(include-book "sub")\n(defun tf (x) (declare (xargs :guard t)) (si x))\n(defconst *tc* (sm 1))\n' > top.lisp
printf '(certify-book "sub")\n(quit)\n' | "$ACL2" > certify-sub.out 2>&1
printf '(certify-book "top")\n(quit)\n' | "$ACL2" > certify-top.out 2>&1
sleep 1
printf '(in-package "ACL2")\n(defmacro sm (x) `(cons ,x (quote new)))\n(defun-inline si (x) (declare (xargs :guard t)) (cons x (quote new)))\n' > sub.lisp
printf '(certify-book "sub")\n(quit)\n' | "$ACL2" > recertify-sub.out 2>&1
cat > include.lsp <<'EOT'
(include-book "top")
(cw "@R (tf 1) evaluates to ~x0; logical body of tf: ~x1~%" (tf 1) (getpropc 'tf 'unnormalized-body nil (w state)))
(cw "@R world value of *tc*: ~x0; (sm 1) now: ~x1~%" (getpropc '*tc* 'const nil (w state)) (sm 1))
(defthm by-definition (equal (tf 1) '(1 . new)) :rule-classes nil :hints (("Goal" :in-theory (disable (:e tf)))))
(defthm by-execution (equal (tf 1) '(1 . old)) :rule-classes nil)
(defthm contradiction nil :rule-classes nil :hints (("Goal" :use (by-definition by-execution))))
(cw "@R NIL proved: ~x0~%" (if (equal (getpropc 'contradiction 'theorem t (w state)) ''nil) :YES :no))
EOT
"$ACL2" < include.lsp > include.out 2>&1
echo "warnings: $(grep -a -o 'ACL2 Warning \[[^]]*\]' include.out | sort | uniq -c | tr '\n' ' ')"
grep -a -o '@R .*' include.out
