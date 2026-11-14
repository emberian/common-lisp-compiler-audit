#!/usr/bin/env bash
# W4-KC-1: ACL2 8.7+ float-b.lisp:409-430 (to-dfp-of-rize / to-df-of-df-rationalize)
# Unsound Axiom on Clozure CL 1.14 (ARM64 & x86-64) + CCL ANSI CL RATIONALIZE/FLOAT
# Round-Trip Violation -> 1-Event, 13-Step (defthm nil-proved nil) in Pure :ttag nil ACL2.
set -euo pipefail

CCL_BIN="${CCL_BIN:-/Users/ember/dev/ccl/darm64cl}"
ACL2_CCL="${ACL2_CCL:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

TMP_DIR="$(mktemp -d /tmp/w4-kc-rize-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== [1/2] Standalone Clozure CL 1.14 (safety 3): CLHS (= (float (rationalize f) f) f) Violation ==="
"$TIMEOUT_BIN" --kill-after=10s 30s "$CCL_BIN" -n -Q -b <<'EOF' > "$TMP_DIR/ccl.out" 2>&1
(declaim (optimize (speed 1) (safety 3) (debug 3)))
(let* ((exact-rat 740037605959421/324518553658426726783156020576256)
       (f (float exact-rat 0.0d0))
       (r (rationalize f))
       (f2 (float r f)))
  (format t "f              = ~S (rational = ~S)~%" f (rational f))
  (format t "(rationalize f)= ~S (den fixnump = ~S, integer-length den = ~D)~%"
          r (typep (denominator r) 'fixnum) (integer-length (denominator r)))
  (format t "(float r f)    = ~S (rational = ~S)~%" f2 (rational f2))
  (format t "CLHS (= (float (rationalize f) f) f) => ~S~%" (= f2 f))
  (assert (eql (rational f) exact-rat))
  (assert (not (= f2 f)))
  (format t "[REPRODUCED-CCL-RATIONALIZE-FLOAT-ROUNDTRIP-FAILURE]~%"))
(quit 0)
EOF
cat "$TMP_DIR/ccl.out"
grep -q '\[REPRODUCED-CCL-RATIONALIZE-FLOAT-ROUNDTRIP-FAILURE\]' "$TMP_DIR/ccl.out"

echo ""
echo "=== [2/2] Pure :ttag nil ACL2 8.7+ on CCL 1.14: 1-Event (defthm nil-proved nil) ==="
"$TIMEOUT_BIN" --kill-after=10s 60s "$ACL2_CCL" <<'EOF' > "$TMP_DIR/acl2.out" 2>&1
(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal" :use ((:instance to-dfp-of-rize
                                   (x 740037605959421/324518553658426726783156020576256))))))

(value-triple
 (cw "~%[AUDIT-CHECK] ttag=~x0 ttags-seen=~x1 skip-proofs-seen=~x2 redef-seen=~x3~%"
     (ttag (w state))
     (global-val 'ttags-seen (w state))
     (global-val 'skip-proofs-seen (w state))
     (global-val 'redef-seen (w state))))
:q
(quit 0)
EOF
grep -E 'Q\.E\.D\.|^ NIL-PROVED$|\[AUDIT-CHECK\]' "$TMP_DIR/acl2.out"
grep -q '^ NIL-PROVED$' "$TMP_DIR/acl2.out"
grep -q '\[AUDIT-CHECK\] ttag=NIL ttags-seen=NIL skip-proofs-seen=NIL redef-seen=NIL' "$TMP_DIR/acl2.out"
echo "[PASS] W4-KC-1 reproduced cleanly."
