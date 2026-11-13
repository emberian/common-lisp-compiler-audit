#!/bin/bash
# Usage: run.sh /path/to/saved_acl2
# Loads lambda-ignore-ok.lisp with LD and evaluates (g 7), then tries to certify it.
ACL2=$1; cd "$(dirname "$0")" || exit 2
rm -f lambda-ignore-ok.cert lambda-ignore-ok.port lambda-ignore-ok.fasl lambda-ignore-ok.da64fsl
printf '(ld "lambda-ignore-ok.lisp")\n(g 7)\n(quit)\n' | "$ACL2" > session.out 2>&1
printf '(certify-book "lambda-ignore-ok")\n(quit)\n' | "$ACL2" > certify.out 2>&1
echo "session: implementation errors=$(grep -c 'Implementation error' session.out)  value printed=$(grep -c '^ACL2 !>7$' session.out)"
echo "certify: implementation errors=$(grep -c 'Implementation error' certify.out)  certified=$([ -f lambda-ignore-ok.cert ] && echo yes || echo no)"
