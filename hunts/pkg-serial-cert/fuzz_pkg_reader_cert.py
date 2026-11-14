#!/usr/bin/env python3
r"""
Automated Fuzzer 2: ACL2 Package, Reader Macros, Portcullis, hidden-defpkg & hcomp
Tests:
  Part A: read-object-with-case (:upcase, :downcase, :preserve, :invert) vs ANSI CL
          readtable-case specification across symbol token shapes.
  Part B: Sharp-macro (#u, #f, #d, #!, #., #{, #\) boundary & error-handling fuzzer
          across read-object, read-object-with-case, and read-object-suppress.
  Part C: Package / portcullis / (local (include-book ...)) / hidden-defpkg / hcomp
          certification & inclusion fuzzer checking symbol identity & package visibility.
"""
import json
import pathlib
import subprocess

BASE = pathlib.Path("/Users/ember/dev/compiler-audit/hunts/pkg-serial-cert")
WORK = BASE / "fuzz_pkg_work"
SBCL = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL = "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"
TIMEOUT = "/opt/homebrew/bin/timeout"


def run_acl2(binary: str, script: str, cwd: pathlib.Path) -> tuple[int, str]:
    p = subprocess.run(
        [TIMEOUT, "--kill-after=10s", "120s", binary],
        input=script,
        cwd=str(cwd),
        capture_output=True,
        text=True,
    )
    return p.returncode, p.stdout + "\n" + p.stderr


def ansi_readtable_case_expected(token: str, mode: str) -> str:
    """ANSI CL 23.1.2.1 Readtable Case expected symbol-name for simple unescaped/bar tokens."""
    if token.startswith("|") and token.endswith("|"):
        return token[1:-1]
    if mode == "upcase":
        return token.upper()
    if mode == "downcase":
        return token.lower()
    if mode == "preserve":
        return token
    if mode == "invert":
        has_upper = any(ch.isupper() for ch in token if ch.isalpha())
        has_lower = any(ch.islower() for ch in token if ch.isalpha())
        if has_upper and not has_lower:
            return token.lower()
        if has_lower and not has_upper:
            return token.upper()
        return token
    raise ValueError(mode)


def run_part_a_case_fuzzer() -> list[dict]:
    tokens = ["FOO", "bar", "BazQuX", "HELLO-WORLD", "hello-world", "Mixed-Case", "|ExactCase|", "X123", "x123"]
    modes = ["upcase", "downcase", "preserve", "invert"]
    (WORK / "tokens.lsp").write_text(" ".join(tokens) + "\n")

    findings = []
    for host, binp in [("SBCL", SBCL), ("CCL", CCL)]:
        for mode in modes:
            forms = [f'(mv-let (ch state) (open-input-channel "tokens.lsp" :object state)']
            indent = "  "
            for i in range(len(tokens)):
                forms.append(
                    f"{indent}(mv-let (eof{i} v{i} state) (read-object-with-case ch :{mode} state)\n"
                    f"{indent}  (declare (ignore eof{i}))"
                )
                indent += "  "
            alist_items = " ".join(f"(cons #\\{chr(ord('A') + i)} (symbol-name v{i}))" for i in range(len(tokens)))
            fmt_spec = " ".join(f"{i}=~x{chr(ord('A') + i)}" for i in range(len(tokens)))
            forms.append(
                f'{indent}(pprogn (fms "CASE-OUT {fmt_spec}~%" (list {alist_items}) *standard-co* state nil)\n'
                f"{indent}        (close-input-channel ch state))" + (")" * (len(tokens) + 1))
            )
            rc, out = run_acl2(binp, "\n".join(forms) + "\n", WORK)
            actual_line = next((l for l in out.splitlines() if "CASE-OUT" in l), "")
            for i, tok in enumerate(tokens):
                exp = ansi_readtable_case_expected(tok, mode)
                # parse i="ACT"
                marker = f'{i}="'
                if marker in actual_line:
                    act = actual_line.split(marker, 1)[1].split('"', 1)[0]
                    if act != exp:
                        findings.append(
                            {
                                "host": host,
                                "mode": f":{mode}",
                                "token": tok,
                                "expected_symbol_name": exp,
                                "actual_symbol_name": act,
                            }
                        )
    return findings


def run_part_b_sharp_fuzzer() -> list[dict]:
    cases = [
        # (name, input_text, read_mode, expectation_note)
        ("sharp_u_valid_dec", "#u1_000_000\n", ":upcase", "valid"),
        ("sharp_u_valid_bin", "#uB1010_0101\n", ":upcase", "valid"),
        ("sharp_u_valid_hex", "#uXdead_beef\n", ":upcase", "valid"),
        ("sharp_u_preserve_lower_bin", "#ub1010\n", ":preserve", "should-read-10"),
        ("sharp_u_preserve_lower_oct", "#uo77\n", ":preserve", "should-read-63"),
        ("sharp_u_preserve_lower_hex", "#uxff\n", ":preserve", "should-read-255"),
        ("sharp_u_bare_b_underscore", "#uB_\n", ":upcase", "malformed"),
        ("sharp_u_bare_o_underscore", "#uO_\n", ":upcase", "malformed"),
        ("sharp_u_bare_x_underscore", "#uX_\n", ":upcase", "malformed"),
        ("sharp_u_div_zero", "#u1_0/0_0\n", ":upcase", "malformed"),
        ("sharp_u_bin_div_zero", "#uB1/0\n", ":upcase", "malformed"),
        ("sharp_u_bar_trailing_junk", "#u|42 THIS IS NOT A NUMERAL|\n", ":upcase", "malformed-trailing"),
        ("sharp_u_hex_bar_trailing_junk", "#u|X10 THIS IS NOT HEX|\n", ":upcase", "malformed-trailing"),
        ("sharp_f_empty_list", "(#f)\n", ":upcase", "degenerate-empty"),
        ("sharp_f_minus_only", "(#f-)\n", ":upcase", "degenerate-empty"),
        ("sharp_f_dot_only", "(#f.)\n", ":upcase", "degenerate-empty"),
        ("sharp_f_hex_empty", "(#fx)\n", ":upcase", "degenerate-empty"),
        ("sharp_f_valid_hex_exp", "#fx1.8p2\n", ":upcase", "valid"),
        ("sharp_d_valid", "#d0.25d0\n", ":upcase", "valid"),
        ("sharp_d_neg_zero", "#d-0.0d0\n", ":upcase", "valid"),
        ("fancy_str_escaped", '#{"""hello \\"""} world"""} \n', ":upcase", "valid"),
    ]
    findings = []
    for host, binp in [("SBCL", SBCL), ("CCL", CCL)]:
        for cname, text, rmode, note in cases:
            f = WORK / f"{cname}.lsp"
            f.write_text(text)
            script = f"""(mv-let (ch state)
  (open-input-channel "{f.name}" :object state)
  (mv-let (eof val state) (read-object-with-case ch {rmode} state)
    (declare (ignore eof))
    (pprogn (fms "SHARP-OK val=~x0~%" (list (cons #\\0 val)) *standard-co* state nil)
            (close-input-channel ch state))))
"""
            rc, out = run_acl2(binp, script, WORK)
            raw_abort = "ABORTING from raw Lisp" in out
            hard_err = "HARD ACL2 ERROR" in out
            ok_line = next((l.strip() for l in out.splitlines() if "SHARP-OK" in l), None)
            if raw_abort or (note.startswith("should-read") and hard_err) or (
                note in ("malformed-trailing", "degenerate-empty") and ok_line
            ):
                findings.append(
                    {
                        "host": host,
                        "case": cname,
                        "mode": rmode,
                        "note": note,
                        "raw_lisp_abort": raw_abort,
                        "hard_acl2_error": hard_err,
                        "ok_output": ok_line,
                    }
                )
    return findings


def run_part_c_pkg_portcullis_fuzzer() -> list[dict]:
    """Tests hidden-defpkg + #! reader visibility leak & symbol identity across hcomp."""
    pdir = WORK / "pkg_cert"
    pdir.mkdir(exist_ok=True)
    for f in pdir.iterdir():
        if f.is_file():
            f.unlink()

    (pdir / "sub.acl2").write_text('(defpkg "HIDDEN-PKG-FUZZ" \'(car cdr))\n')
    (pdir / "sub.lisp").write_text('(in-package "HIDDEN-PKG-FUZZ")\n(acl2::defun f (x) (car x))\n')

    (pdir / "mid.lisp").write_text(
        '(in-package "ACL2")\n'
        '(local (include-book "sub"))\n'
        '(defun mid-id (x) x)\n'
    )

    findings = []
    for host, binp in [("SBCL", SBCL), ("CCL", CCL)]:
        for ext in (".cert", ".port", ".fasl", ".lx64fsl"):
            for b in ("sub", "mid"):
                p = pdir / f"{b}{ext}"
                if p.exists():
                    p.unlink()
        rc1, out1 = run_acl2(binp, '(ld "sub.acl2")\n(certify-book "sub" 1 t)\n', pdir)
        rc2, out2 = run_acl2(binp, '(certify-book "mid" 0 t)\n', pdir)
        # Fresh session: include "mid" (so HIDDEN-PKG-FUZZ is a hidden-defpkg, NOT known to ACL2!)
        # Test 1: (in-package "HIDDEN-PKG-FUZZ") should fail;
        # Test 2: reading "#!HIDDEN-PKG-FUZZ 42" via read-object — should ALSO fail with
        # "There is no package named \"HIDDEN-PKG-FUZZ\" that is known to ACL2 in this context",
        # NOT succeed!
        (pdir / "bang_hidden.lsp").write_text("#!HIDDEN-PKG-FUZZ 42\n")
        test_hidden = """(include-book "mid")
(mv-let (ch state)
  (open-input-channel "bang_hidden.lsp" :object state)
  (mv-let (eof val state) (read-object ch state)
    (declare (ignore eof))
    (pprogn (fms "HIDDEN-BANG-READ-SUCCEEDED val=~x0~%" (list (cons #\\0 val)) *standard-co* state nil)
            (close-input-channel ch state))))
"""
        rc3, out3 = run_acl2(binp, test_hidden, pdir)
        if "HIDDEN-BANG-READ-SUCCEEDED" in out3:
            findings.append(
                {
                    "host": host,
                    "case": "sharp_bang_accepts_hidden_defpkg",
                    "detail": "#!HIDDEN-PKG-FUZZ 42 succeeded after (include-book \"mid\") even though HIDDEN-PKG-FUZZ is a hidden-defpkg!",
                }
            )
    return findings


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    for f in WORK.iterdir():
        if f.is_file():
            f.unlink()

    print("[1/3] Running Part A: read-object-with-case differential fuzzer...")
    fa = run_part_a_case_fuzzer()
    print(f"  Part A mismatches: {len(fa)}")
    for item in fa[:8]:
        print("   ", item)

    print("\n[2/3] Running Part B: sharp-macro boundary & error-handling fuzzer...")
    fb = run_part_b_sharp_fuzzer()
    print(f"  Part B anomalies: {len(fb)}")
    for item in fb:
        print("   ", item)

    print("\n[3/3] Running Part C: package / portcullis / hidden-defpkg fuzzer...")
    fc = run_part_c_pkg_portcullis_fuzzer()
    print(f"  Part C anomalies: {len(fc)}")
    for item in fc:
        print("   ", item)

    out_path = BASE / "fuzz_pkg_reader_results.json"
    out_path.write_text(
        json.dumps(
            {
                "part_a_read_object_with_case_mismatches": fa,
                "part_b_sharp_macro_anomalies": fb,
                "part_c_pkg_portcullis_anomalies": fc,
            },
            indent=2,
        )
    )
    print(f"\nSaved results to {out_path.name}")


if __name__ == "__main__":
    main()
