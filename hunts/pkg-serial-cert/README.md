# Wave-2 Lane D Fuzzers: Packages, Reader, Portcullis / `.cert`, and `serialize-raw`

This directory contains the two automated fuzzing harnesses built for the ACL2 8.7+ (`1d2b39a424`) audit of packages, reader sharp-macros, certification/inclusion boundaries, and `serialize-write` / `serialize-read`.

## Harnesses

1. **`fuzz_serialize.py`** (results saved in `fuzz_serialize_results.json`):
   - **Part A (Valid-object round-trip & cross-host SBCL <-> CCL fuzzer)**: Encodes edge-case ACL2 objects (large bignums, negative/unusual rationals & complexes, all character boundary codes `0..255`, normed & unnormed strings, multi-package symbols, shadowed fast alists, atom-only fast alists, improper fast alists, and shared Hons DAGs) on both SBCL and CCL via `serialize-write`, `#Y`, and `#Z`, then verifies `equal`, `hons-equal`, and `(not (bad-lisp-objectp val))` across all `:hons-mode` settings (`:smart`, `:always`, `:never`) and cross-host combinations.
   - **Part B (Adversarial `.sao` V1/V2/V3 grammar & byte-mutation fuzzer)**: Generates 87 targeted and mutated V1 (`#xAC120BC7`), V2 (`#xAC120BC8`), and V3 (`#xAC120BC9`) `.sao` streams and tests `serialize-read` (without trust tags) on both SBCL and CCL, checking ACL2 universe partition predicates, `bad-lisp-objectp`, `hons-equal` reflexivity, and Hons `faltable` structural invariants (`slot1`/`slot2`/`table` key non-atomicity and empty-slot invariants).
   - **Isolated checks**: Tests normed-spine fast-alist `BREAK$-RAW` debugger entry under default `slow-alist-action`, bignum FAL `count` (`2^100`) `make-hash-table` raw error, and large fixnum `(expt 2 57)` stack-allocated array behavior on CCL.

2. **`fuzz_pkg_reader_cert.py`** (results saved in `fuzz_pkg_reader_results.json`):
   - **Suite 1 (`read-object` & `read-object-with-case`)**: Differential testing across `:upcase`, `:downcase`, `:preserve`, and `:invert` case modes.
   - **Suite 2 (Sharp-macro fuzzer)**: Boundary inputs for `#u` (`sharp-u-read`), `#f` (`sharp-f-read`), `#!` (`sharp-bang-read`), `#d`, `#{"""..."""}`, `#\...` character names, and `#.` suppression.
   - **Suite 3 (Package / Portcullis / `hidden-defpkg` / Reincarnation / `hcomp`)**: Multi-book certification and inclusion chains testing `local` sub-book `defpkg` (`hidden-defpkg`), incompatible package reincarnation, `ACL2`/`COMMON-LISP` import invariants, and `#!HIDDEN-PKG` visibility in `read-object`.

## Running

```bash
python3 /Users/ember/dev/compiler-audit/hunts/pkg-serial-cert/fuzz_serialize.py
python3 /Users/ember/dev/compiler-audit/hunts/pkg-serial-cert/fuzz_pkg_reader_cert.py
```

Every `saved_acl2` subprocess invocation is wrapped in `/opt/homebrew/bin/timeout --kill-after=10s 120s`.
