# `integer-length` result-type derivation — SBCL 2.6.10 (aarch64, 64-bit)

**Verdict: SAFE.**

## Method

Compiled `(lambda (x) (declare <decl> (optimize (speed 3) (safety 0))) (integer-length x))`
and read the compiler's result type with `(sb-kernel:%simple-fun-type (compile nil lam))`.
SBCL `/opt/homebrew/bin/sbcl`, version 2.6.10, source at `~/dev/sbcl`.
Script: `scratchpad/il-test.lisp`. Each process run once under `timeout 120`.

Control (known-correct): `(unsigned-byte 8)` input → `(VALUES (MOD 9) ...)`, i.e. `(integer 0 8)`,
exactly the true range of `(integer-length <8-bit>)`. Method validated.

## Derived result type per input type

| input declaration                | derived result type        | = integer range            |
|-----------------------------------|----------------------------|----------------------------|
| `integer` (unconstrained)         | `(UNSIGNED-BYTE 38)`       | `(integer 0 274877906943)` |
| `(integer 0 *)` (unsigned-byte)   | `(UNSIGNED-BYTE 38)`       | `(integer 0 274877906943)` |
| `(unsigned-byte 64)`              | `(MOD 65)`                 | `(integer 0 64)`           |
| `bignum`                          | `(INTEGER 63 274877906943)`| `(integer 63 (2^38-1))`    |
| `(integer 0 (expt 2 100))`        | `(MOD 102)`                | `(integer 0 101)`          |
| `(unsigned-byte 8)` *(control)*   | `(MOD 9)`                  | `(integer 0 8)`            |

`274877906943 = 2^38 - 1`.

## Source reason

Two mechanisms, both sound:

1. **Bounded inputs** follow the input's own range via the derive-type optimizer
   — `src/compiler/srctran.lisp:3359-3386`:
   ```lisp
   (defoptimizer (integer-length derive-type) ((x))
     (one-arg-derive-type x
       (lambda (x-type)
         ... (let ((lo (numeric-type-low x-type)) (hi (numeric-type-high x-type)))
               (cond ((and lo hi) (make-numeric-type 'integer ... (max-il lo hi))) ...)))))
   ```
   For `(integer lo hi)` the upper bound is `(max (integer-length lo) (integer-length hi))`
   — a function of the input's bounds, never a flat cap. Confirmed: `(expt 2 100)` input →
   `(mod 102)`, i.e. tracks the declared bound exactly.

2. **Unbounded inputs** (`integer`, `(integer 0 *)`, `bignum`'s open side): all `lo`/`hi`
   branches above return `NIL`, so the result falls back to the declared ftype in the
   `defknown` — `src/compiler/fndb.lisp:543`:
   ```lisp
   (defknown (logcount integer-length) (integer) bit-index ...)
   ```
   `bit-index` is **not** an arbitrary flat constant; it is derived from the largest
   representable bignum — `src/compiler/generic/vm-type.lisp:73-74`:
   ```lisp
   (sb-xc:deftype sb-bignum:bit-index ()
     `(integer 0 ,(- (* (1+ maximum-bignum-length) sb-vm:n-word-bits) 1)))
   ```
   with `maximum-bignum-length = #xFFFFFFFF = 2^32-1` (64-bit) —
   `src/compiler/generic/early-vm.lisp:74-79` — and `n-word-bits = 64`. So
   `bit-index = (integer 0 ((2^32)*64 - 1)) = (integer 0 (2^38 - 1)) = (unsigned-byte 38)`.

## Why the cap cannot be exceeded (soundness)

The cap `2^38 - 1` over-approximates the true maximum. The largest magnitude a bignum can
hold is `maximum-bignum-length` words = `(2^32 - 1) * 64` bits, and the top (sign) bit is
unavailable for magnitude, so the **largest `integer-length` of any representable integer is
`(2^32 - 1)*64 - 1 = 2^38 - 65`**, which is `< 2^38 - 1`. The declared result type contains
the true result for every representable input; it exceeds the real maximum by 64 bits.

To fall outside `(unsigned-byte 38)` an integer would need `integer-length >= 2^38`, i.e.
`>= 2^38` bits `= 2^35 bytes = 32 GiB` of magnitude — which simultaneously **exceeds
`maximum-bignum-length`**, so SBCL cannot represent it at all (it signals an error on the
operation that would create it, well before `integer-length` is reached). No witness exists
even in principle; the question is moot the way `length`/`(unsigned-byte 45)` is moot via
`array-dimension-limit`.

**Verdict: SAFE** — the `(unsigned-byte 38)` cap on `integer-length` is a sound
over-approximation; no representable integer has `integer-length > 2^38 - 65 < 2^38`.
