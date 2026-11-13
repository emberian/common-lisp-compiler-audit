# Verification of F8 and F9

Date: 2026-11-13.  Both ACL2 executables reported development snapshot 8.7+, Git
`1d2b39a424eabeab269f189b37c29148d49fc516`; hosts were SBCL 2.6.10 and CCL
1.14 darwinarm64.  Every invocation below started a new ACL2 process through
`lisp-run.sh` (300-second cap).

## Workspace and commands

The workspace guard did not permit changing into or writing in the reproducer
directory.  I therefore ran exact-content copies in
`/Users/ember/dev/compiler-audit/scouts/verify-f8f9`, with no pre-existing F8
certificate.  The filename mapping is:

- `f8-original.lisp` = `stale-type-cache/nil-via-local.lisp`
- `nil-book.lisp` = `stale-type-cache/nil-book.lisp`
- `certify-nil-book.lisp` = `stale-type-cache/certify-nil-book.lisp`
- `include-nil-book.lisp` = `stale-type-cache/include-nil-book.lisp`
- `f9-original.lisp` = `string-stobj/string-stobj.lisp`
- `f8-min.lisp` = minimized F8, intended name `nil-via-local-min.lisp`
- `f9-min.lisp` = minimized F9, intended name `string-stobj-min.lisp`

Commands executed from that workspace (`R` denotes
`/Users/ember/dev/compiler-audit/scouts/lisp-run.sh`):

```sh
R acl2-sbcl f8-original.lisp
R acl2-ccl  f8-original.lisp
R acl2-sbcl certify-nil-book.lisp
R acl2-ccl  certify-nil-book.lisp
R acl2-ccl  include-nil-book.lisp
R acl2-sbcl f9-original.lisp
R acl2-ccl  f9-original.lisp
R acl2-ccl  f8-min.lisp
R acl2-sbcl f9-min.lisp
R acl2-ccl  f9-min.lisp
```

The two certification runs were sequential.  SBCL produced no certificate;
CCL certification therefore started without a `.cert` file.

## F8: stale CCL type cache — CONFIRMED (CCL; soundness)

The original script was run three times in fresh CCL sessions.  Every run gave:

```text
ACL2 !>RESULT (g) = NIL
Form:  ( DEFTHM G-IS-NIL ...)
 G-IS-NIL
Form:  ( DEFTHM CONTRADICTION ...)
 CONTRADICTION
```

The minimized file also ended with:

```text
Q.E.D.
Form:  ( DEFTHM CONTRADICTION ...)
Hint-events: ((:USE G-IS-NIL) (:USE G-IS-T))
 CONTRADICTION
```

On fresh SBCL ACL2, the control run instead gave:

```text
ACL2 !>RESULT (g) = T
ACL2 Error [Failure] in ( DEFTHM G-IS-NIL ...):  See :DOC failure.
******** FAILED ********
```

CCL certification of the exact book contents succeeded after admitting both
`G-IS-T` and `G-IS-NIL`:

```text
Form:  ( DEFTHM CONTRADICTION ...)
CONTRADICTION
* Step 4:  Write the certificate for
Form:  (CERTIFY-BOOK "nil-book" ...)
 "/Users/ember/dev/compiler-audit/scouts/verify-f8f9/nil-book.lisp"
ACL2 !>RESULT certify-book returned
```

SBCL rejected certification at `G-IS-NIL`:

```text
ACL2 Warning in CERTIFY-BOOK:  The attempted CERTIFY-BOOK has failed
ACL2 Error [Failure] in (CERTIFY-BOOK "nil-book" ...):  See :DOC failure.
******** FAILED ********
```

This is a genuine proof and export of `NIL`, not a skipped proof.  The source
uses ordinary logic-mode `defun`, `defstobj`, and `defthm`; it has no
`skip-proofs`, trust tag/defttag, `:program` mode, raw Lisp, redefinition, or
undo.  The book literally contains `(defthm contradiction nil ...)`.  As an
independent certificate check, a fresh CCL session included the certified book
and proved `NIL` from its exported theorem:

```text
Form:  ( THM ...)
Hint-events: ((:USE CONTRADICTION))
Proof succeeded.
```

That include-book session printed `RESULT (g) after include-book = T`, while
the theorem remained available and sufficient to prove `NIL`.

There was no run-to-run variation in three identical fresh CCL executions or
in the minimized run.  The array is explicitly `:initially 1`; the evidence
points to the stale parsed-type cache causing incompatible vector
representation/access, not to dependence on uninitialized memory.

Classification: **soundness on CCL**.  SBCL is a rejecting control, not an
affected host.  Minimized tested source: `f8-min.lisp`; intended installed
name: `stale-type-cache/nil-via-local-min.lisp`.

## F9: single-field stobj represented as a string — CONFIRMED (SBCL and CCL; soundness)

Both fresh host sessions produced the same decisive results:

```text
ACL2 !>RESULT (s8p s8) at top level = NIL
ACL2 !>RESULT (h) = NIL
Form:  ( DEFTHM H-IS-T ...)
 H-IS-T
Form:  ( DEFTHM H-IS-NIL ...)
 H-IS-NIL
Form:  ( DEFTHM CONTRADICTION ...)
 CONTRADICTION
```

Thus the live stobj fails its own recognizer, while logical execution supports
`H-IS-T` and the executable counterpart supports `H-IS-NIL`; their combination
admits the literal theorem `NIL`.  No skip-proofs or trust mechanism is used.

The minimized file independently ended in `Q.E.D.` and `CONTRADICTION` on both
SBCL and CCL.  Classification: **soundness on both hosts**, not merely a host
robustness/admission difference.  Minimized tested source: `f9-min.lisp`;
intended installed name: `string-stobj/string-stobj-min.lisp`.

## Delivery limitation

Permission to write the minimized files beside the originals was requested but
not granted.  The tested minimized files and all fresh transcripts remain in
`/Users/ember/dev/compiler-audit/scouts/verify-f8f9`.  No repository files,
`LEDGER.md`, or prior certification artifacts were edited or removed, and no
commits were made.
