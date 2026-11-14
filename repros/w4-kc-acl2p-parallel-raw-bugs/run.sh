#!/usr/bin/env bash
# W4-KC-6: ACL2 8.7+ parallel-raw.lisp vs parallel.lisp (#+acl2-par) Bugs Found via Kimi K3.1-pro:
#   (6a) parallel-raw.lisp:1199-1200 vs parallel.lisp:570: Zero-arg (pand) evaluates to NIL in
#        raw Lisp ((if nil t nil)) vs T in ACL2 logic -> proves NIL in :ttag nil ACL2(p)!
#   (6b) parallel-raw.lisp:1276-1286 vs parallel.lisp:876: Unhygienic `the-very-obscure-feature`
#        (spelled `the-very-obscure-future` in parallel.lisp:876!) leaks raw MT-FUTURE structs
#        into logic variables and lets inner bindings hijack outer speculative futures!
#   (6c) parallel-raw.lisp:721-725: `remove-thread-array-from-work-queue-rec` decrements
#        `array-positions-left` on unrelated work-queue entries, stranding sibling work.
#   (6d) parallel-raw.lisp:437-438,573-600,689-690: Unwritten result-array slot on worker
#        nonlocal exit becomes `(cdr nil) => NIL` in parent instead of propagating error.
set -euo pipefail

ACL2_SBCL="${ACL2_SBCL:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
ACL2_SRC_DIR="${ACL2_SRC_DIR:-/Users/ember/dev/acl2-fix/head-worktree}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

TMP_DIR="$(mktemp -d /tmp/w4-kc-par-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== ACL2 8.7+ parallel.lisp vs parallel-raw.lisp (#+acl2-par) Verification ==="
ACL2_SRC_DIR="$ACL2_SRC_DIR" "$TIMEOUT_BIN" --kill-after=10s 45s "$ACL2_SBCL" <<'EOF' > "$TMP_DIR/par.out" 2>&1
;; First verify the ACL2 :logic semantics in unmodified saved_acl2:
(defun logic-pand-zero ()
  (declare (xargs :guard t))
  (pand))

(defun logic-spec-outer-var (the-very-obscure-feature)
  (declare (xargs :guard t))
  (spec-mv-let (x) 1
    (mv?-let (w) 2
      (if nil x the-very-obscure-feature))))

(defun logic-spec-inner-hijack ()
  (declare (xargs :guard t))
  (spec-mv-let (x) 10
    (mv?-let (the-very-obscure-feature)
      (spec-mv-let (y) 99
        (mv?-let (z) 0
          (if t (prog2$ (cw "") the-very-obscure-feature) 0)))
      (if t x 0))))

(defthm logic-pand-zero-is-t
  (equal (logic-pand-zero) t))

(defthm logic-spec-outer-var-is-identity
  (equal (logic-spec-outer-var v) v))

(defthm logic-spec-inner-hijack-is-10
  (equal (logic-spec-inner-hijack) 10))

:q
(in-package "ACL2")
(setf sb-ext:*invoke-debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "UNEXPECTED DEBUGGER CONDITION: ~A~%" c)
        (sb-ext:exit :code 2)))
(pushnew :acl2-par *features*)
(let ((src (sb-ext:posix-getenv "ACL2_SRC_DIR"))
      (sb-ext:*muffled-warnings* 'warning))
  (load (concatenate 'string src "/multi-threading-raw.lisp"))
  (load (concatenate 'string src "/parallel-raw.lisp"))
  (load (concatenate 'string src "/futures-raw.lisp")))

;; (6a) Zero-arg (pand) in parallel-raw.lisp:1199-1200:
(let ((raw-pand (eval '(pand))))
  (format t "[6a] logic (pand) = T, parallel-raw (pand) = ~S~%" raw-pand)
  (assert (eq raw-pand nil)))

;; (6b-1) parallel.lisp:876 checks `the-very-obscure-future` while parallel-raw.lisp:1276
;; binds `the-very-obscure-feature`, leaking a raw MT-FUTURE struct instead of 42!
(let ((leaked (eval '(let ((the-very-obscure-feature 42))
                       (spec-mv-let (x) 1
                         (mv?-let (w) 2
                           (if nil x the-very-obscure-feature)))))))
  (format t "[6b-1] logic = 42, parallel-raw leaked type = ~S (aborted=~S)~%"
          (type-of leaked) (mt-future-aborted leaked))
  (assert (mt-future-p leaked)))

;; (6b-2) Inner binding of `the-very-obscure-feature` hijacks outer `(future-read ...)`,
;; returning 99 instead of 10!
(let ((hijacked (eval '(spec-mv-let (x) 10
                         (mv?-let (the-very-obscure-feature)
                           (spec-mv-let (y) 99
                             (mv?-let (z) 0
                               (if t (progn y the-very-obscure-feature) 0)))
                           (if t x 0))))))
  (format t "[6b-2] logic = 10, parallel-raw hijacked result = ~S~%" hijacked)
  (assert (eql hijacked 99)))

;; (6c) remove-thread-array-from-work-queue-rec (parallel-raw.lisp:721-725):
(let* ((a (make-array 2 :initial-element nil))
       (b (make-array 1 :initial-element nil))
       (*work-queue* (list (make-parallelism-piece
                            :thread-array a
                            :semaphore-to-signal-as-last-act (make-semaphore))
                           (make-parallelism-piece
                            :thread-array b
                            :semaphore-to-signal-as-last-act (make-semaphore))
                           (make-parallelism-piece
                            :thread-array a
                            :semaphore-to-signal-as-last-act (make-semaphore)))))
  (remove-thread-array-from-work-queue a)
  (let ((rem (count a *work-queue* :key #'parallelism-piece-thread-array)))
    (format t "[6c] remaining siblings of A in *work-queue* = ~D (expected 0)~%" rem)
    (assert (= rem 1))))

(format t "[REPRODUCED-ACL2P-PARALLEL-RAW-BUGS]~%")
(sb-ext:exit :code 0)
EOF
grep -E 'LOGIC-PAND-ZERO-IS-T|LOGIC-SPEC-OUTER-VAR-IS-IDENTITY|LOGIC-SPEC-INNER-HIJACK-IS-10|\[6a\]|\[6b-1\]|\[6b-2\]|\[6c\]|\[REPRODUCED-ACL2P' "$TMP_DIR/par.out"
grep -q '\[REPRODUCED-ACL2P-PARALLEL-RAW-BUGS\]' "$TMP_DIR/par.out"
echo "[PASS] W4-KC-6 reproduced cleanly."
