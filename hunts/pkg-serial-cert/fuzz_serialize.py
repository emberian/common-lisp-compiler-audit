#!/usr/bin/env python3
"""
Automated Fuzzer 1: ACL2 serialize-write / serialize-read / #Y / #Z
Tests:
  Part A: Valid-object round-trips & cross-host SBCL <-> CCL equivalence across
          :hons-mode (:smart, :always, :never) and #Y / #Z reader macros.
  Part B: Adversarial .sao V1/V2/V3 grammar & byte-level fuzzer (no trust tags)
          checking bad-lisp-objectp, universe partition, faltable invariants, and raw crashes.
"""
import json
import pathlib
import random
import subprocess

BASE = pathlib.Path("/Users/ember/dev/compiler-audit/hunts/pkg-serial-cert")
WORK = BASE / "fuzz_ser_work"
SBCL = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL = "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"
TIMEOUT = "/opt/homebrew/bin/timeout"

MAGIC_V1 = bytes([0xAC, 0x12, 0x0B, 0xC7])
MAGIC_V2 = bytes([0xAC, 0x12, 0x0B, 0xC8])
MAGIC_V3 = bytes([0xAC, 0x12, 0x0B, 0xC9])


def enc_nat(n: int) -> bytes:
    assert n >= 0
    out = bytearray()
    while n >= 128:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    out.append(n)
    return bytes(out)


def enc_str(s: bytes, v3: bool = True, normed: bool = False) -> bytes:
    header = (len(s) << 1) | (1 if normed else 0) if v3 else len(s)
    return enc_nat(header) + s


def build_sao(
    magic: bytes,
    size_or_idx: int,
    nats: list[int] = (),
    rats: list[tuple[int, int, int]] = (),
    complexes: list[tuple[tuple[int, int, int], tuple[int, int, int]]] = (),
    chars: list[int] = (),
    strs: list[tuple[bytes, bool]] = (),
    pkgs: list[tuple[bytes, list[bytes]]] = (),
    conses: list[tuple[int, int]] = (),
    fals: list[tuple[int, int]] | None = (),
    trailer: bytes | None = None,
) -> bytes:
    """
    Exact encoder for ACL2 serialize-raw V1/V2/V3 stream format:
      - V1: magic=C7, size_or_idx = arr-size (free starts at 0!), no fals section, trailer=C7.
      - V2: magic=C8, size_or_idx = final-obj index (arr[0]=nil, arr[1]=t, free starts at 2,
            arr-size = 2 if size_or_idx==0 else size_or_idx+1), no fals section, trailer=C8.
      - V3: magic=C9, same size_or_idx as V2, fals section (index, count)* terminated by 0, trailer=C9.
    """
    v1 = magic == MAGIC_V1
    v3 = magic == MAGIC_V3
    if trailer is None:
        trailer = magic
    buf = bytearray(magic)
    buf += enc_nat(size_or_idx)
    # nats
    buf += enc_nat(len(nats))
    for x in nats:
        buf += enc_nat(x)
    # rats
    buf += enc_nat(len(rats))
    for sgn, num, den in rats:
        buf += enc_nat(sgn) + enc_nat(num) + enc_nat(den)
    # complexes
    buf += enc_nat(len(complexes))
    for (rs, rn, rd), (is_, in_, id_) in complexes:
        buf += enc_nat(rs) + enc_nat(rn) + enc_nat(rd)
        buf += enc_nat(is_) + enc_nat(in_) + enc_nat(id_)
    # chars
    buf += enc_nat(len(chars))
    for c in chars:
        buf.append(c & 0xFF)
    # strs
    buf += enc_nat(len(strs))
    for b, nrm in strs:
        buf += enc_str(b, v3=v3, normed=nrm)
    # pkgs
    buf += enc_nat(len(pkgs))
    for pname, syms in pkgs:
        buf += enc_str(pname, v3=v3, normed=False)
        buf += enc_nat(len(syms))
        for sym in syms:
            buf += enc_str(sym, v3=v3, normed=False)
    # conses
    buf += enc_nat(len(conses))
    for first_idx, cdr_idx in conses:
        buf += enc_nat(first_idx) + enc_nat(cdr_idx)
    # fals (V3 only!)
    if v3 and fals is not None:
        for fidx, fcnt in fals:
            buf += enc_nat(fidx) + enc_nat(fcnt)
        buf += enc_nat(0)
    buf += trailer
    return bytes(buf)


def run_acl2(binary: str, script: str, cwd: pathlib.Path) -> tuple[int, str]:
    p = subprocess.run(
        [TIMEOUT, "--kill-after=10s", "120s", binary],
        input=script,
        cwd=str(cwd),
        capture_output=True,
        text=True,
    )
    return p.returncode, p.stdout + "\n" + p.stderr


def generate_adversarial_cases(out_dir: pathlib.Path) -> list[dict]:
    cases = []

    def add(name: str, data: bytes, modes=("smart", "always", "never")):
        p = out_dir / f"{name}.sao"
        p.write_bytes(data)
        cases.append({"name": name, "path": p.name, "modes": list(modes), "len": len(data)})

    # 1. V1 size_or_idx=0: arr-size=0, free=0, final-obj=-1 -> (svref arr -1) at (safety 0)!
    add("v1_size0_oob", build_sao(MAGIC_V1, size_or_idx=0))
    # 2. V3 valid minimal NIL (size_or_idx=0, arr-size=2, free=2) and T (size_or_idx=1, arr-size=2, free=2)
    add("v3_minimal_nil", build_sao(MAGIC_V3, size_or_idx=0))
    add("v3_minimal_t", build_sao(MAGIC_V3, size_or_idx=1))
    # 3. V3 size_or_idx=2 with 0 items -> free=2 != arr-size=3 -> clean error
    add("v3_free_mismatch", build_sao(MAGIC_V3, size_or_idx=2))
    # 4. V3 FAL count=0 desync under :never (valid fast alist '(1): arr[2]=1, arr[3]=(1 . nil), size_or_idx=3)
    add(
        "v3_fal_count0_desync",
        build_sao(
            MAGIC_V3,
            size_or_idx=3,
            nats=[1],
            conses=[(2 << 1, 0)],
            fals=[(3, 0)],
        ),
    )
    # 5. V3 FAL count=50 (> arr-size=4) desync under :never -> "FAL index to restore is too large!"
    add(
        "v3_fal_count50_desync",
        build_sao(
            MAGIC_V3,
            size_or_idx=3,
            nats=[1],
            conses=[(2 << 1, 0)],
            fals=[(3, 50)],
        ),
    )
    # 6. V3 FAL atom index=1 (arr[1]=T bound in faltable, violating Fast Alist Invariant 1!)
    add("v3_fal_atom_t", build_sao(MAGIC_V3, size_or_idx=1, fals=[(1, 5)]))
    # 7. V3 FAL atom index=2 where arr[2] = ACL2::NIL = NIL! (slot key=NIL with non-nil val!)
    add(
        "v3_fal_atom_nil_via_pkg",
        build_sao(
            MAGIC_V3,
            size_or_idx=2,
            pkgs=[(b"ACL2", [b"NIL"])],
            fals=[(2, 5)],
        ),
    )
    # 8. V3 FAL atom index=2 where arr[2] = integer 42 (integer bound in faltable!)
    add(
        "v3_fal_atom_int42",
        build_sao(
            MAGIC_V3,
            size_or_idx=2,
            nats=[42],
            fals=[(2, 5)],
        ),
    )
    # 10. V3 FAL unnormed string key under :smart
    add(
        "v3_fal_unnormed_str_key",
        build_sao(
            MAGIC_V3,
            size_or_idx=4,
            strs=[(b"unnormed", False)],  # arr[2]
            conses=[
                (2 << 1, 1),  # arr[3] = ("unnormed" . T)
                (3 << 1, 0),  # arr[4] = (("unnormed" . T))
            ],
            fals=[(4, 1)],
        ),
    )
    # 11. Rationals & complexes edge cases
    add("v3_rat_unreduced_2_4", build_sao(MAGIC_V3, size_or_idx=2, rats=[(0, 2, 4)]))
    add("v3_rat_neg_zero", build_sao(MAGIC_V3, size_or_idx=2, rats=[(1, 0, 5)]))
    add("v3_rat_div0", build_sao(MAGIC_V3, size_or_idx=2, rats=[(0, 1, 0)]))
    add("v3_rat_bad_sign", build_sao(MAGIC_V3, size_or_idx=2, rats=[(2, 1, 1)]))
    add("v3_cplx_imag0", build_sao(MAGIC_V3, size_or_idx=2, complexes=[((0, 3, 1), (0, 0, 1))]))
    add("v3_cplx_unreduced", build_sao(MAGIC_V3, size_or_idx=2, complexes=[((1, 4, 2), (0, 6, 9))]))
    # 12. Package boundary cases
    for tag, pn, sn in [
        ("pkg_empty", b"", b"X"),
        ("pkg_unknown", b"NO_SUCH_PKG_XYZ", b"X"),
        ("pkg_invisible", b"ACL2_INVISIBLE", b"HONS"),
        ("pkg_cl_user", b"COMMON-LISP-USER", b"FOO"),
        ("pkg_cl_eval", b"COMMON-LISP", b"EVAL"),
        ("pkg_cl_fresh", b"COMMON-LISP", b"FRESH_CL_SYM_999"),
        ("pkg_kw", b"KEYWORD", b"MY-KW"),
    ]:
        add(f"v3_{tag}", build_sao(MAGIC_V3, size_or_idx=2, pkgs=[(pn, [sn])]))
    # 13. Cons self-reference / bignum first-index
    add("v3_cons_self_ref", build_sao(MAGIC_V3, size_or_idx=2, conses=[(2 << 1, 0)]))
    add("v3_cons_bignum_idx", build_sao(MAGIC_V3, size_or_idx=2, conses=[(1 << 70, 0)]))
    # 14. Equal unnormed strings under :always (V1 and V3) -> verify hons-equal invariant!
    add(
        "v1_dup_str_always",
        build_sao(
            MAGIC_V1,
            size_or_idx=3,  # arr[0]="abc", arr[1]="abc", arr[2]=(0 . 1)
            strs=[(b"abc", False), (b"abc", False)],
            conses=[(0, 1)],
        ),
    )
    add(
        "v3_dup_unnormed_str_always",
        build_sao(
            MAGIC_V3,
            size_or_idx=4,  # arr[2]="abc", arr[3]="abc", arr[4]=(2 . 3)
            strs=[(b"abc", False), (b"abc", False)],
            conses=[((2 << 1) | 1, 3)],
        ),
    )

    # 15. Deterministic pseudo-random byte-mutation fuzzing (60 mutated .sao streams)
    rng = random.Random(20261113)
    seeds = [
        build_sao(
            MAGIC_V3,
            size_or_idx=7,
            nats=[0, 127, 128, (1 << 63) + 7],
            conses=[((2 << 1) | 1, 3), ((4 << 1), 6)],
            fals=[(7, 1)],
        ),
        build_sao(MAGIC_V1, size_or_idx=2, strs=[(b"hello", False)], conses=[(0, 0)]),
        build_sao(MAGIC_V2, size_or_idx=3, rats=[(1, 7, 3)], conses=[(2 << 1, 0)], fals=None),
    ]
    for i in range(60):
        base = bytearray(rng.choice(seeds))
        op = i % 4
        if op == 0 and len(base) > 5:
            pos = rng.randrange(4, len(base) - 4)
            base[pos] ^= rng.randrange(1, 256)
        elif op == 1:
            pos = rng.randrange(4, len(base))
            base = base[:pos]
        elif op == 2 and len(base) > 6:
            pos = rng.randrange(4, len(base) - 4)
            base[pos:pos] = bytes([rng.randrange(256) for _ in range(rng.randint(1, 4))])
        else:
            base[-1] ^= 0xFF
        add(f"mut_{i:02d}", bytes(base), modes=("smart", "never"))

    return cases


VALID_ROUNDTRIP_LISP = r"""(in-package "ACL2")
(defpkg "FUZZP" '(car cdr cons))

(defconst *valid-test-objs*
  (list
   (cons 'empty-nil nil)
   (cons 'bool-t t)
   (cons 'edge-ints (list 0 1 -1 127 128 -128 (expt 2 60) (- (expt 2 60)) (expt 2 130) (- (expt 2 130))))
   (cons 'rats-cplx (list 1/3 -7/11 #c(1 2) #c(-3/5 7/13) #c(0 -1)))
   (cons 'all-chars (list (code-char 0) (code-char 1) #\Newline #\Space (code-char 127) (code-char 128) (code-char 255)))
   (cons 'strings (list "" "abc" (hons-copy "normed-str") (coerce (list (code-char 0) #\A (code-char 255)) 'string)))
   (cons 'pkgs-syms (list 'acl2::foo 'common-lisp::car 'common-lisp::eval :kw 'fuzzp::local-sym 'fuzzp::car))
   (cons 'fal-normal (make-fast-alist (list (cons (hons-copy "k1") 10) (cons 'a 20) (cons '(1 . 2) 30))))
   (cons 'fal-shadow-and-atom (make-fast-alist (list (cons 'dup 1) 'bare-atom (cons 'dup 2) (cons 'uniq 3))))
   (cons 'fal-only-atoms (make-fast-alist '(only-atom-1 only-atom-2)))
   (cons 'fal-improper (hons-acons 'k 'v 'improper-tail))
   (cons 'hons-dag (let* ((x (hons "shared" '(1 2))) (y (hons x x))) (hons y y)))))

:q
#+sbcl (sb-ext:disable-debugger)

(defun write-all-valid (prefix)
  (#+sbcl sb-ext:without-package-locks #-sbcl progn
  (loop for (name . obj) in *valid-test-objs* do
    (let ((sao (format nil "~a-~a.sao" prefix (string-downcase (symbol-name name))))
          (ylsp (format nil "~a-~a-y.lsp" prefix (string-downcase (symbol-name name))))
          (zlsp (format nil "~a-~a-z.lsp" prefix (string-downcase (symbol-name name)))))
      (serialize-write-fn sao obj nil *the-live-state*)
      (with-open-file (s ylsp :direction :output :if-exists :supersede)
        (let ((*ser-char* #\Y))
          (write-char #\# s) (write-char #\Y s)
          (ser-encode-to-stream obj s)))
      (with-open-file (s zlsp :direction :output :if-exists :supersede)
        (let ((*ser-char* #\Z))
          (write-char #\# s) (write-char #\Z s)
          (ser-encode-to-stream obj s)))))))

(defun check-all-valid (writer-prefix reader-label)
  (#+sbcl sb-ext:without-package-locks #-sbcl progn
  (loop for (name . expected) in *valid-test-objs* do
    (let ((base (string-downcase (symbol-name name))))
      (dolist (mode '(:smart :always :never))
        (let ((sao (format nil "~a-~a.sao" writer-prefix base)))
          (handler-case
              (multiple-value-bind (val st)
                  (serialize-read-fn sao mode nil *the-live-state*)
                (declare (ignore st))
                (let ((bad (bad-lisp-objectp val))
                      (eqv (equal val expected))
                      (heqv (hons-equal val expected)))
                  (when (or bad (not eqv) (not heqv))
                    (format t "VALID-MISMATCH reader=~a writer=~a obj=~a mode=~a bad=~s eq=~s heq=~s~%"
                            reader-label writer-prefix base mode bad eqv heqv))))
            (serious-condition (c)
              (format t "VALID-ERROR reader=~a writer=~a obj=~a mode=~a err=~a~%"
                      reader-label writer-prefix base mode c)))))
      (dolist (kind '("y" "z"))
        (let ((fn (format nil "~a-~a-~a.lsp" writer-prefix base kind)))
          (handler-case
              (multiple-value-bind (ch st)
                  (open-input-channel fn :object *the-live-state*)
                (multiple-value-bind (eof val st2)
                    (read-object ch st)
                  (declare (ignore eof))
                  (close-input-channel ch st2)
                  (let ((bad (bad-lisp-objectp val))
                        (eqv (equal val expected))
                        (heqv (hons-equal val expected)))
                    (when (or bad (not eqv) (not heqv))
                      (format t "READER-MISMATCH reader=~a writer=~a obj=~a #~a bad=~s eq=~s heq=~s~%"
                              reader-label writer-prefix base kind bad eqv heqv)))))
            (serious-condition (c)
              (format t "READER-ERROR reader=~a writer=~a obj=~a #~a err=~a~%"
                      reader-label writer-prefix base kind c)))))))))
"""


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    for f in WORK.iterdir():
        if f.is_file():
            f.unlink()

    print("[1/3] Running Part A: Valid-object round-trip & cross-host SBCL <-> CCL fuzzer...")
    rc_s, out_s = run_acl2(
        SBCL,
        VALID_ROUNDTRIP_LISP + '\n(write-all-valid "sbcl")\n(check-all-valid "sbcl" "SBCL")\n(quit)\n',
        WORK,
    )
    rc_c, out_c = run_acl2(
        CCL,
        VALID_ROUNDTRIP_LISP
        + '\n(write-all-valid "ccl")\n(check-all-valid "ccl" "CCL")\n(check-all-valid "sbcl" "CCL")\n(quit)\n',
        WORK,
    )
    rc_s2, out_s2 = run_acl2(
        SBCL,
        VALID_ROUNDTRIP_LISP + '\n(check-all-valid "ccl" "SBCL")\n(quit)\n',
        WORK,
    )

    part_a_findings = []
    for out in (out_s, out_c, out_s2):
        for line in out.splitlines():
            for tag in ("VALID-MISMATCH", "VALID-ERROR", "READER-MISMATCH", "READER-ERROR"):
                if tag in line:
                    part_a_findings.append(line[line.index(tag):].strip())
                    break

    print(f"  Part A findings ({len(part_a_findings)}):")
    for f in part_a_findings:
        print("   ", f)

    print("\n[2/3] Generating Part B adversarial .sao corpus...")
    cases = generate_adversarial_cases(WORK)
    print(f"  Generated {len(cases)} adversarial .sao files.")

    def build_driver(host_label: str) -> str:
        body = [
            "(set-slow-alist-action :warning)",
            ":q",
            "#+sbcl (sb-ext:disable-debugger)",
            "(#+sbcl sb-ext:without-package-locks #-sbcl progn",
            "(defun check-faltable-invariants ()",
            "  (let* ((hs *default-hs*)",
            "         (ft (hl-hspace-faltable hs))",
            "         (s1 (hl-faltable-slot1 ft))",
            "         (s2 (hl-faltable-slot2 ft))",
            "         (issues nil))",
            "    (when (and (null (hl-falslot-key s1)) (hl-falslot-val s1))",
            "      (push :slot1-nil-key-has-val issues)",
            "      (setf (hl-falslot-val s1) nil))",
            "    (when (and (null (hl-falslot-key s2)) (hl-falslot-val s2))",
            "      (push :slot2-nil-key-has-val issues)",
            "      (setf (hl-falslot-val s2) nil))",
            "    (when (and (hl-falslot-key s1) (atom (hl-falslot-key s1)))",
            "      (push (list :slot1-atom-key (hl-falslot-key s1)) issues)",
            "      (setf (hl-falslot-key s1) nil) (setf (hl-falslot-val s1) nil))",
            "    (when (and (hl-falslot-key s2) (atom (hl-falslot-key s2)))",
            "      (push (list :slot2-atom-key (hl-falslot-key s2)) issues)",
            "      (setf (hl-falslot-key s2) nil) (setf (hl-falslot-val s2) nil))",
            "    (maphash (lambda (k v) (declare (ignore v))",
            "               (when (atom k) (push (list :table-atom-key k) issues) (remhash k (hl-faltable-table ft))))",
            "             (hl-faltable-table ft))",
            "    issues))",
        ]
        for c in cases:
            for m in c["modes"]:
                body.append(
                    f'(catch \'raw-ev-fncall '
                    f'  (handler-case '
                    f'    (multiple-value-bind (val st) (serialize-read-fn "{c["path"]}" :{m} nil *the-live-state*) '
                    f'      (declare (ignore st)) '
                    f'      (let* ((universe-ok (or (consp val) (acl2-numberp val) (symbolp val) (characterp val) (stringp val))) '
                    f'             (bad (and universe-ok (bad-lisp-objectp val))) '
                    f'             (heq-ok (and universe-ok (equal (hons-equal val val) (equal val val)))) '
                    f'             (ft-bad (check-faltable-invariants))) '
                    f'        (when (or (not universe-ok) bad (not heq-ok) ft-bad) '
                    f'          (format t "ADV-FINDING host={host_label} case={c["name"]} mode=:{m} universe-ok=~s bad=~s heq-ok=~s ft-bad=~s~%" '
                    f'                  universe-ok bad heq-ok ft-bad)))) '
                    f'    (serious-condition (e) '
                    f'      (let ((ft-bad (check-faltable-invariants))) '
                    f'        (when (or ft-bad (typep e \'type-error) (typep e \'arithmetic-error)) '
                    f'          (format t "ADV-RAW-COND host={host_label} case={c["name"]} mode=:{m} cond-type=~s ft-bad=~s~%" '
                    f'                  (type-of e) ft-bad))))))'
                )
        body.append(")")
        body.append("(quit)")
        return "\n".join(body) + "\n"

    print("\n[3/3] Running Part B adversarial corpus on SBCL and CCL...")
    part_b_findings = []
    for label, binp in [("SBCL", SBCL), ("CCL", CCL)]:
        rc, out = run_acl2(binp, build_driver(label), WORK)
        print(f"  {label} rc={rc}")
        for line in out.splitlines():
            for tag in ("ADV-FINDING", "ADV-RAW-COND"):
                if tag in line:
                    s = line[line.index(tag):].strip()
                    part_b_findings.append(s)
                    print("   ", s)
                    break

    # Isolated checks for raw breaks / bignum hash-table size / CCL stack array overflow:
    isolated_results = {}

    # (a) Valid normed-spine fast alist triggers BREAK$-RAW on serialize-read in default session:
    honsed_fal_script = (
        '(let* ((x (make-fast-alist (hons-copy \'((a . 1) (b . 2)))))\n'
        '       (state (serialize-write "iso_honsed_fal.sao" x)))\n'
        '  (serialize-read "iso_honsed_fal.sao"))\n'
    )
    for lbl, binp in [("SBCL", SBCL), ("CCL", CCL)]:
        rc_hf, out_hf = run_acl2(binp, honsed_fal_script, WORK)
        triggered_break = "Fast alist stolen by HL-HSPACE-RESTORE-FAL-FOR-SERIALIZE" in out_hf and "BREAK$-RAW" in out_hf
        isolated_results[f"honsed_fal_break_{lbl.lower()}"] = {
            "rc": rc_hf,
            "triggered_break_raw": triggered_break,
        }
        print(f"  {lbl} normed-spine FAL break check: triggered_break_raw={triggered_break}")

    # (b) V3 FAL huge bignum count (2^100 -> make-hash-table :size bignum -> raw Lisp TYPE-ERROR):
    bignum_fal_sao = WORK / "v3_fal_bignum_count.sao"
    bignum_fal_sao.write_bytes(
        build_sao(MAGIC_V3, size_or_idx=3, nats=[1], conses=[((2 << 1) | 1, 0)], fals=[(3, 1 << 100)])
    )
    for lbl, binp in [("SBCL", SBCL), ("CCL", CCL)]:
        rc_bg, out_bg = run_acl2(binp, f'(serialize-read "{bignum_fal_sao.name}")\n', WORK)
        raw_err = "RAW LISP ERROR" in out_bg or "raw Lisp" in out_bg or "not of type" in out_bg or "not a" in out_bg
        isolated_results[f"v3_fal_bignum_count_{lbl.lower()}"] = {
            "rc": rc_bg,
            "raw_lisp_error": raw_err,
        }
        print(f"  {lbl} bignum FAL count (2^100) check: raw_lisp_error={raw_err}")

    # (c) CCL (expt 2 57) stack-allocated array in ser-make-array-wrapper:
    sigsegv_sao = WORK / "ccl_stack_overflow_array.sao"
    sigsegv_sao.write_bytes(build_sao(MAGIC_V3, size_or_idx=(1 << 57)))
    rc_ccl_arr, out_ccl_arr = run_acl2(
        CCL,
        f'(serialize-read "{sigsegv_sao.name}")\n',
        WORK,
    )
    isolated_results["ccl_stack_overflow_array_2_57"] = {
        "rc": rc_ccl_arr,
        "tail": out_ccl_arr.splitlines()[-8:],
    }
    print(f"  CCL (expt 2 57) array test: rc={rc_ccl_arr}")

    summary = {
        "part_a_valid_roundtrip_findings": part_a_findings,
        "part_b_adversarial_findings": part_b_findings,
        "isolated_checks": isolated_results,
        "num_adversarial_cases": len(cases),
    }
    (BASE / "fuzz_serialize_results.json").write_text(json.dumps(summary, indent=2))
    print("\nSaved results to fuzz_serialize_results.json")


if __name__ == "__main__":
    main()
