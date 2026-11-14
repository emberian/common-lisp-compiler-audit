#!/usr/bin/env python3
"""ACL2 blind-spot prototype fuzzer (w4-astra-fuzz / af-acl2-fuzz slice).

Two pipelines aimed at the two structural blind spots of the existing ACL2 harnesses
(synth/, hunts/w4-kernel-fuzz/, hunts/prover-falsify/):

Pipeline A -- GVBC + EMI (Guard-Verified-By-Construction + Equivalence-Modulo-Inputs)
  * Synthesises plain / recursive / mutually-recursive / mv / let* / loop$ functions whose
    termination (explicit (nfix n) measure + (zp n) base case) and guards (integer /
    (signed-byte 64) parameters, divisors clamped to (+ 1 (nfix d)), shift counts clamped to
    (- (mod s 16) 8), exponents (mod e 70)) hold BY CONSTRUCTION, so ~100% pass admission and
    :verify-guards t with NO skip-proofs (contrast: synth/emit.lisp wraps every twin in
    skip-proofs).
  * An INDEPENDENT Python big-integer / IEEE-double model computes the expected value of every
    query (contrast: synth compares REF vs OPT inside the same image, sharing raw primitives).
  * Profiles live/dead program points on the concrete inputs, then derives EMI variants:
    dead-branch insertion (if <profile-false cond> <junk> e) and live identity wrappers
    (mbe, the, flet, ec-call, prog2$, return-last, nested mv-let, lambda$/apply$, df ops).
  * Checks agreement across guard-checking :all / t / nil / :none, all EMI variants, and a
    certify-book + include-book (compile-file + load) route, on SBCL and CCL images.

Pipeline B -- Model-guided non-ground dual-interpretation falsifier
  * Builds constrained (encapsulate (((f *) => *)) ...) theories with two concrete
    interpretations M_true / M_false that both satisfy every exported constraint (checked on a
    Python grid AND re-proved by ACL2 for M_false), and a conjecture phi that holds in M_true but
    is refuted in M_false at a concrete ground witness.  phi is therefore NOT a theorem of the
    theory; any Q.E.D. of phi (or of its defun-sk / defchoose / forced-rule / congruence
    re-encodings) is a soundness candidate and is automatically pushed to
    (defthm nil-proved nil) via (:instance (:functional-instance phi (f M_false)) ...).
  * Constraint rules are exported with randomly chosen rule classes and force / case-split
    hypotheses (multi-round forcing with :otf-flg t), nat-equivalence congruences
    (defequiv/defcong) and defun-sk (:constrain t/nil) / defchoose (:strengthen t/nil) wrappers.
  * Positive controls (a constraint restated as a theorem) must prove, so a silently broken
    pipeline cannot report "clean".

Usage: fuzz_acl2_emi_non_ground.py [--seed N] [--cases N] [--mode all|emi|nonground]
                                   [--runtime both|sbcl|ccl] [--keep]
Exit status: 0 = campaign ran, no anomalies; 1 = anomalies found (details printed).
All scratch files live in mktemp -d /tmp/w4-astra-acl2-XXXX and are removed on exit.
"""
import argparse
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from fractions import Fraction

sys.dont_write_bytecode = True

TIMEOUT = "/opt/homebrew/bin/timeout"
RUNTIMES = {
    "sbcl": "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2",
    "ccl": "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2",
}
CRASH_RE = re.compile(r"HARD ACL2 ERROR|Raw Lisp|ABORTING from raw Lisp|Unhandled|"
                      r"debugger invoked|Segmentation|memory fault|Stack overflow|"
                      r"CONTROL-STACK-EXHAUSTED|> Error:|Fatal error", re.I)


def run_acl2(rt, script, cwd, secs):
    path = os.path.join(cwd, "in-%d.lisp" % random.getrandbits(40))
    with open(path, "w") as fh:
        fh.write(script)
    with open(path) as fh:
        p = subprocess.run([TIMEOUT, "--kill-after=5s", "%ds" % secs, RUNTIMES[rt]],
                           stdin=fh, cwd=cwd, capture_output=True, text=True, errors="replace")
    os.unlink(path)
    return p.returncode, p.stdout + "\n" + p.stderr


# ======================================================================================
# Pipeline A: GVBC + EMI
# ======================================================================================
BOUNDARY = [0, 1, -1, 2, -2, 3, 7, -7, 100, 255, 256, -256, 65535, 2**31 - 1, -2**31, 2**32,
            2**61 - 1, 2**62 - 1, -2**62, 2**62, 2**63 - 1, -2**63, 2**63, 2**64 + 1, -2**64]
SB64 = (-2**63, 2**63 - 1)


def nfix(v):
    return v if v >= 0 else 0


def trunc(a, d):
    q = abs(a) // d
    return q if a >= 0 else -q


def to_df(q):
    return float(Fraction(q))


# op -> (arity, renderer, python)
def _clampd(b):
    return "(+ 1 (nfix %s))" % b


OPS = {
    "+": (2, lambda a, b: "(+ %s %s)" % (a, b), lambda a, b: a + b),
    "-": (2, lambda a, b: "(- %s %s)" % (a, b), lambda a, b: a - b),
    "*": (2, lambda a, b: "(* %s %s)" % (a, b), lambda a, b: a * b),
    "floor": (2, lambda a, b: "(floor %s %s)" % (a, _clampd(b)), lambda a, b: a // (1 + nfix(b))),
    "mod": (2, lambda a, b: "(mod %s %s)" % (a, _clampd(b)), lambda a, b: a % (1 + nfix(b))),
    "truncate": (2, lambda a, b: "(truncate %s %s)" % (a, _clampd(b)),
                 lambda a, b: trunc(a, 1 + nfix(b))),
    "rem": (2, lambda a, b: "(rem %s %s)" % (a, _clampd(b)),
            lambda a, b: a - (1 + nfix(b)) * trunc(a, 1 + nfix(b))),
    "logand": (2, lambda a, b: "(logand %s %s)" % (a, b), lambda a, b: a & b),
    "logior": (2, lambda a, b: "(logior %s %s)" % (a, b), lambda a, b: a | b),
    "logxor": (2, lambda a, b: "(logxor %s %s)" % (a, b), lambda a, b: a ^ b),
    "ash": (2, lambda a, b: "(ash %s (- (mod %s 16) 8))" % (a, b),
            lambda a, b: (a << ((b % 16) - 8)) if (b % 16) >= 8 else (a >> (8 - (b % 16)))),
    "min": (2, lambda a, b: "(min %s %s)" % (a, b), min),
    "max": (2, lambda a, b: "(max %s %s)" % (a, b), max),
    "abs": (1, lambda a: "(abs %s)" % a, abs),
    "lognot": (1, lambda a: "(lognot %s)" % a, lambda a: -a - 1),
    "neg": (1, lambda a: "(- %s)" % a, lambda a: -a),
    "pow2": (1, lambda a: "(expt 2 (mod %s 70))" % a, lambda a: 2 ** (a % 70)),
    "logcount": (1, lambda a: "(logcount %s)" % a,
                 lambda a: bin(a).count("1") if a >= 0 else bin(-a - 1).count("1")),
    "sb64wrap": (1, lambda a: "(- (logand (+ %s 9223372036854775808) 18446744073709551615) "
                              "9223372036854775808)" % a,
                 lambda a: ((a + 2**63) & (2**64 - 1)) - 2**63),
    # clamps (never generated randomly; trivially provable guard/type obligations)
    "natclamp": (1, lambda a: "(nfix (mod %s 7))" % a, lambda a: a % 7),
    "sb64clamp": (1, lambda a: "(let ((w4v %s)) (if (signed-byte-p 64 w4v) w4v 0))" % a,
                  lambda a: a if SB64[0] <= a <= SB64[1] else 0),
}
CLAMPS = ("natclamp", "sb64clamp")
GEN_OPS = [o for o in OPS if o not in CLAMPS]
CMPS = {"<": lambda a, b: a < b, "<=": lambda a, b: a <= b, "=": lambda a, b: a == b,
        "equal": lambda a, b: a == b}


class Gen:
    def __init__(self, rng, uid):
        self.rng = rng
        self.uid = uid
        self.site = 0

    def k(self):
        r = self.rng
        return r.choice(BOUNDARY) if r.random() < 0.4 else r.randint(-20, 20)

    def expr(self, d, env, helpers):
        """Integer-valued, guard-safe expression over integer vars ENV."""
        r = self.rng
        if d <= 0 or r.random() < 0.18:
            if env and r.random() < 0.75:
                return ("v", r.choice(env))
            return ("k", self.k())
        c = r.random()
        if c < 0.50:
            op = r.choice(GEN_OPS)
            ar = OPS[op][0]
            return ("op", op, [self.expr(d - 1, env, helpers) for _ in range(ar)])
        if c < 0.64:
            return ("if", self.cond(d - 1, env, helpers), self.expr(d - 1, env, helpers),
                    self.expr(d - 1, env, helpers))
        if c < 0.76:
            v = "l%d" % r.randint(0, 999)
            while v in env:
                v += "x"
            return ("let", v, self.expr(d - 1, env, helpers), self.expr(d - 1, env + [v], helpers))
        if c < 0.86 and helpers:
            h = r.choice(helpers)
            args = [self.expr(d - 1, env, helpers) for _ in range(h["arity"])]
            if h["mv"]:
                p, q = "p%d" % r.randint(0, 999), "q%d" % r.randint(0, 999)
                return ("mvlet", h["name"], args, p, q, self.expr(d - 1, env + [p, q], helpers))
            return ("call", h["name"], args, h.get("ecall", False))
        if c < 0.93:
            return ("df", self.expr(d - 1, env, helpers), self.expr(d - 1, env, helpers))
        return ("site", self.newsite(), self.expr(d - 1, env, helpers))

    def newsite(self):
        self.site += 1
        return self.site

    def cond(self, d, env, helpers):
        r = self.rng
        if r.random() < 0.15:
            return ("evenp", self.expr(d, env, helpers))
        return ("cmp", r.choice(list(CMPS)), self.expr(d, env, helpers), self.expr(d, env, helpers))


def render(e):
    t = e[0]
    if t == "v":
        return e[1]
    if t == "k":
        return str(e[1])
    if t == "op":
        return OPS[e[1]][1](*[render(a) for a in e[2]])
    if t == "if":
        return "(if %s %s %s)" % (render_c(e[1]), render(e[2]), render(e[3]))
    if t == "let":
        return "(let* ((%s %s)) %s)" % (e[1], render(e[2]), render(e[3]))
    if t == "call":
        s = "(%s %s)" % (e[1], " ".join(render(a) for a in e[2]))
        return "(ifix (ec-call %s))" % s if e[3] else s
    if t == "mvlet":
        return "(mv-let (%s %s) (%s %s) %s)" % (e[3], e[4], e[1], " ".join(render(a) for a in e[2]),
                                                render(e[5]))
    if t == "df":
        return ("(floor (* 1024 (from-df (df+ (to-df (/ %s 3)) (to-df (/ %s 7))))) 1)"
                % (render(e[1]), render(e[2])))
    if t == "site":
        return render(e[2])
    if t == "dead":
        return "(if %s %s %s)" % (render_c(e[1]), render(e[2]), render(e[3]))
    if t == "wrap":
        return render_wrap(e)
    if t == "rec":   # self call inside recursive bodies
        return "(%s %s)" % (e[1], " ".join(render(a) for a in e[2]))
    raise ValueError(t)


def render_c(c):
    if c[0] == "evenp":
        return "(evenp %s)" % render(c[1])
    return "(%s %s %s)" % (c[1], render(c[2]), render(c[3]))


def render_wrap(e):
    kind, x, junk = e[1], render(e[2]), render(e[3]) if e[3] is not None else "0"
    if kind == "mbe":
        return "(mbe :logic %s :exec %s)" % (x, x)
    if kind == "mbe+":   # commuted (+ a b): guard verification must prove :logic = :exec
        a, b = render(e[2][2][0]), render(e[2][2][1])
        return "(mbe :logic (+ %s %s) :exec (+ %s %s))" % (a, b, b, a)
    if kind == "the":
        return "(the integer %s)" % x
    if kind == "flet":
        return "(flet ((w4g (u) (declare (type integer u)) (+ u 7))) (- (w4g %s) 7))" % x
    if kind == "prog2$":
        return "(prog2$ %s %s)" % (junk, x)
    if kind == "return-last":
        return "(return-last 'progn %s %s)" % (junk, x)
    if kind == "mv":
        return "(mv-let (w4p w4q) (mv %s %s) (declare (ignore w4q)) w4p)" % (x, junk)
    if kind == "lambda$":
        return ("(ifix (apply$ (lambda$ (u) (declare (xargs :guard (integerp u))) (* u 1)) (list %s)))"
                % x)
    if kind == "ec-call":
        return "(ec-call (w4id-%s %s))" % (e[4], x)
    raise ValueError(kind)


class Exec:
    def __init__(self, fns, prof=None):
        self.fns = fns
        self.prof = prof
        self.dead_hits = {}

    def ev(self, e, env):
        t = e[0]
        if t == "v":
            return env[e[1]]
        if t == "k":
            return e[1]
        if t == "op":
            return OPS[e[1]][2](*[self.ev(a, env) for a in e[2]])
        if t == "if":
            return self.ev(e[2], env) if self.evc(e[1], env) else self.ev(e[3], env)
        if t == "let":
            env2 = dict(env)
            env2[e[1]] = self.ev(e[2], env)
            return self.ev(e[3], env2)
        if t in ("call", "rec"):
            return self.call(e[1], [self.ev(a, env) for a in e[2]])
        if t == "mvlet":
            p, q = self.call(e[1], [self.ev(a, env) for a in e[2]])
            env2 = dict(env)
            env2[e[3]], env2[e[4]] = p, q
            return self.ev(e[5], env2)
        if t == "df":
            a, b = self.ev(e[1], env), self.ev(e[2], env)
            s = to_df(Fraction(a, 3)) + to_df(Fraction(b, 7))
            return (Fraction(s) * 1024) // 1
        if t == "site":
            if self.prof is not None:
                self.prof.setdefault(e[1], []).append(dict(env))
            return self.ev(e[2], env)
        if t == "dead":
            if self.evc(e[1], env):
                self.dead_hits[id(e)] = True
                return self.ev(e[2], env)
            return self.ev(e[3], env)
        if t == "wrap":
            if e[3] is not None:
                self.ev(e[3], env)
            return self.ev(e[2], env)
        raise ValueError(t)

    def evc(self, c, env):
        if c[0] == "evenp":
            return self.ev(c[1], env) % 2 == 0
        return CMPS[c[1]](self.ev(c[2], env), self.ev(c[3], env))

    def call(self, name, args):
        f = self.fns[name]
        env = dict(zip(f["params"], args))
        if f["kind"] == "loop":
            n, k = args
            return sum(self.ev(f["lbody"], {"i": i, "k": k}) for i in range(0, min(nfix(n), 20) + 1))
        if f["kind"] in ("rec", "mut"):
            if env["n"] == 0:
                return self.ev(f["base"], env)
            return self.ev(f["step"], env)
        if f["kind"] == "mvh":
            return (self.ev(f["b1"], env), self.ev(f["b2"], env))
        return self.ev(f["body"], env)


def mk_guard(f):
    conj, decls = [], []
    for p, ty in zip(f["params"], f["ptypes"]):
        if ty == "nat":
            conj.append("(natp %s)" % p)
        elif ty == "sb64":
            conj.append("(signed-byte-p 64 %s)" % p)
            decls.append("(type (signed-byte 64) %s)" % p)
        else:
            conj.append("(integerp %s)" % p)
            if random.random() < 0.5:
                decls.append("(type integer %s)" % p)
    return conj, decls


def render_defun(f, vg=True):
    conj, decls = f["guard"], f["decls"]
    xa = [":guard (and %s)" % " ".join(conj)] if conj else []
    if f["kind"] in ("rec", "mut"):
        xa.append(":measure (nfix n)")
    xa.append(":verify-guards %s" % ("t" if vg and f["kind"] != "loop" else "nil"))
    if f["kind"] in ("rec", "mut"):
        body = "(if (zp n) %s %s)" % (render(f["base"]), render(f["step"]))
    elif f["kind"] == "loop":
        body = ("(loop$ for i of-type integer from 0 to (min (nfix n) 20) sum %s)"
                % render(f["lbody"]))
    elif f["kind"] == "mvh":
        body = "(mv %s %s)" % (render(f["b1"]), render(f["b2"]))
    else:
        body = render(f["body"])
    d = "(declare %s(xargs %s))" % ("".join(x + " " for x in decls), " ".join(xa))
    return "(defun %s (%s) %s %s)" % (f["name"], " ".join(f["params"]), d, body)


def gen_group(rng, gid):
    """One GVBC program: helpers + a main function.  Returns dict."""
    g = Gen(rng, gid)
    pre = "g%d-" % gid
    fns, order, helpers = {}, [], []

    def add(f):
        f["guard"], f["decls"] = mk_guard(f)
        fns[f["name"]] = f
        order.append([f["name"]])

    # mv helper
    if rng.random() < 0.6:
        f = {"name": pre + "mvh", "kind": "mvh", "params": ["a", "b"],
             "ptypes": ["int", "int"]}
        f["b1"] = g.expr(2, ["a", "b"], [])
        f["b2"] = g.expr(2, ["a", "b"], [])
        add(f)
        helpers.append({"name": f["name"], "arity": 2, "mv": True})
    # loop$ helper (:ideal, called through ec-call: loop$ guard verification needs
    # projects/apply lemmas that are not available -- see report)
    if rng.random() < 0.5:
        f = {"name": pre + "lp", "kind": "loop", "params": ["n", "k"], "ptypes": ["int", "int"]}
        lg = Gen(rng, gid)
        f["lbody"] = lg.expr(2, ["i", "k"], [])
        # loop$ body: strip sites/df/calls (must be tame & closed except k)
        f["lbody"] = strip_nontame(f["lbody"])
        add(f)
        helpers.append({"name": f["name"], "arity": 2, "mv": False, "ecall": True})
    # recursive helper
    if rng.random() < 0.7:
        name = pre + "rec"
        ty = rng.choice(["int", "sb64"])
        f = {"name": name, "kind": "rec", "params": ["n", "a", "b"], "ptypes": ["nat", "int", ty]}
        f["base"] = g.expr(2, ["a", "b"], helpers)
        a2 = g.expr(1, ["a", "b", "n"], [])
        b2 = ("op", "sb64clamp", [g.expr(1, ["a", "b", "n"], [])]) if ty == "sb64" else \
            g.expr(1, ["a", "b", "n"], [])
        rcall = ("rec", name, [("op", "-", [("v", "n"), ("k", 1)]), a2, b2])
        f["step"] = ("let", "r", rcall, ("op", "sb64wrap", [g.expr(2, ["r", "a", "b", "n"], helpers)])
                     if rng.random() < 0.5 else g.expr(2, ["r", "a", "b", "n"], helpers))
        f["n1"] = True
        add(f)
        helpers.append({"name": name, "arity": 3, "mv": False, "natfirst": True})
    # mutual recursion pair
    if rng.random() < 0.4:
        e, o = pre + "ev", pre + "od"
        fe = {"name": e, "kind": "mut", "params": ["n", "a"], "ptypes": ["nat", "int"]}
        fo = {"name": o, "kind": "mut", "params": ["n", "a"], "ptypes": ["nat", "int"]}
        for f, other in ((fe, o), (fo, e)):
            f["base"] = g.expr(2, ["a"], [])
            f["step"] = ("let", "r", ("rec", other, [("op", "-", [("v", "n"), ("k", 1)]),
                                                     g.expr(1, ["a", "n"], [])]),
                         g.expr(1, ["r", "a", "n"], []))
            f["guard"], f["decls"] = mk_guard(f)
            fns[f["name"]] = f
        order.append([e, o])
        helpers.append({"name": e, "arity": 2, "mv": False, "natfirst": True})
    # main
    ptypes = [rng.choice(["int", "int", "sb64"]) for _ in range(3)]
    f = {"name": pre + "main", "kind": "plain", "params": ["x", "y", "z"], "ptypes": ptypes}
    f["body"] = g.expr(4, ["x", "y", "z"], [h for h in helpers])
    add(f)
    return {"gid": gid, "fns": fns, "order": order, "main": f["name"], "gen": g}


def strip_nontame(e):
    t = e[0]
    if t in ("v", "k"):
        return e
    if t == "op":
        if e[1] in ("pow2",):
            return ("k", 3)
        return ("op", e[1], [strip_nontame(a) for a in e[2]])
    if t == "if":
        c = e[1]
        c2 = ("evenp", strip_nontame(c[1])) if c[0] == "evenp" else \
            ("cmp", c[1], strip_nontame(c[2]), strip_nontame(c[3]))
        return ("if", c2, strip_nontame(e[2]), strip_nontame(e[3]))
    if t == "let":
        return strip_nontame(e[3]) if False else ("op", "+", [strip_nontame(e[2]), ("k", 0)])
    if t == "site":
        return strip_nontame(e[2])
    return ("v", "i")


def fix_nat_args(e, fns):
    """Calls to helpers whose first formal is (natp n): clamp to a small recursion depth."""
    if not isinstance(e, tuple):
        return
    if e[0] == "op" and e[1] in CLAMPS:
        return
    if e[0] in ("call", "mvlet") and fns[e[1]]["ptypes"][0] == "nat":
        e[2][0] = ("op", "natclamp", [e[2][0]])            # (nfix (mod x 7)) -- natp
    if e[0] in ("call", "mvlet") and len(fns[e[1]]["ptypes"]) > 2 and fns[e[1]]["ptypes"][2] == "sb64":
        e[2][2] = ("op", "sb64clamp", [e[2][2]])
    for x in e[1:]:
        if isinstance(x, tuple):
            fix_nat_args(x, fns)
        elif isinstance(x, list):
            for y in x:
                fix_nat_args(y, fns)


def fix_all(group):
    for f in group["fns"].values():
        for key in ("body", "base", "step", "b1", "b2"):
            if key in f:
                fix_nat_args(f[key], group["fns"])
                if f["ptypes"] and "sb64" in f["ptypes"]:
                    pass


def gen_inputs(rng, f, n=6):
    out = []
    for _ in range(n):
        row = []
        for ty in f["ptypes"]:
            v = rng.choice(BOUNDARY) if rng.random() < 0.6 else rng.randint(-1000, 1000)
            if ty == "sb64":
                v = max(SB64[0], min(SB64[1], v))
            row.append(v)
        out.append(row)
    return out


def emi_variants(rng, group, inputs, nvar):
    """Profile 'site' nodes on concrete inputs, then derive EMI variants of main."""
    main = group["fns"][group["main"]]
    prof = {}
    ex = Exec(group["fns"], prof)
    for row in inputs:
        try:
            ex.call(main["name"], row)
        except (OverflowError, MemoryError, ValueError):
            return None, {}
    variants = []
    sites = sorted(prof)
    stats = {"sites": len(sites), "live_sites": sum(1 for s in prof if prof[s])}
    for vi in range(nvar):
        body = main["body"]
        kinds = []

        def mutate(e, depth=0):
            if not isinstance(e, tuple):
                return e
            t = e[0]
            if t == "site":
                envs = prof.get(e[1], [])
                inner = mutate(e[2], depth + 1)
                choice = rng.random()
                if envs and choice < 0.5:
                    cond = dead_cond(rng, envs, group)
                    if cond is not None:
                        junk = group["gen"].expr(2, list(envs[0].keys()), [])
                        kinds.append("dead")
                        return ("dead", cond, junk, wrap_any(rng, inner, list(envs[0].keys()),
                                                              group, kinds))
                if not envs:
                    kinds.append("never-reached")
                return wrap_any(rng, inner, list(envs[0].keys()) if envs else [], group, kinds)
            if t == "op" and e[1] in CLAMPS:
                return e
            if t in ("op",):
                new = ("op", e[1], [mutate(a, depth + 1) for a in e[2]])
                if rng.random() < 0.12:
                    return wrap_any(rng, new, [], group, kinds)
                return new
            if t == "if":
                return ("if", mutc(e[1]), mutate(e[2], depth + 1), mutate(e[3], depth + 1))
            if t == "let":
                return ("let", e[1], mutate(e[2]), mutate(e[3]))
            if t in ("call", "rec"):
                return (t, e[1], [mutate(a) for a in e[2]]) + tuple(e[3:])
            if t == "mvlet":
                return ("mvlet", e[1], [mutate(a) for a in e[2]], e[3], e[4], mutate(e[5]))
            if t == "df":
                return ("df", mutate(e[1]), mutate(e[2]))
            return e

        def mutc(c):
            if c[0] == "evenp":
                return ("evenp", mutate(c[1]))
            return ("cmp", c[1], mutate(c[2]), mutate(c[3]))

        nb = mutate(body)
        variants.append((nb, kinds))
    return variants, stats


def dead_cond(rng, envs, group):
    """A condition that is FALSE in every profiled environment at this program point."""
    ex = Exec(group["fns"])
    for _ in range(8):
        vars_ = list(envs[0].keys())
        x = group["gen"].expr(1, vars_, [])
        try:
            vals = [ex.ev(x, en) for en in envs]
        except Exception:
            continue
        if rng.random() < 0.5:
            k = max(vals) + rng.choice([1, 2, 1000, 2**62])
            return ("cmp", "<", ("k", k), x)          # (< k x) never true
        cands = [c for c in [0, 1, -1, 7, 2**62, 2**63 - 1, -2**63, 12345] if c not in vals]
        if cands:
            return ("cmp", "equal", x, ("k", rng.choice(cands)))
    return None


def wrap_any(rng, e, vars_, group, kinds):
    kind = rng.choice(["mbe", "the", "flet", "prog2$", "return-last", "mv", "lambda$",
                       "ec-call", "mbe+"])
    if kind == "mbe+" and not (e[0] == "op" and e[1] == "+"):
        kind = "mbe"
    junk = group["gen"].expr(1, vars_, []) if kind in ("prog2$", "return-last", "mv") else None
    kinds.append(kind)
    return ("wrap", kind, e, junk, group["gid"])


def build_pipeline_a(rng, ncases):
    groups = []
    for gid in range(ncases):
        for _attempt in range(20):
            grp = gen_group(rng, gid)
            fix_all(grp)
            main = grp["fns"][grp["main"]]
            inputs = gen_inputs(rng, main)
            ex = Exec(grp["fns"])
            try:
                exp = [ex.call(main["name"], row) for row in inputs]
            except (OverflowError, MemoryError, ValueError, ZeroDivisionError):
                continue
            if any(abs(v) > 2**4096 for v in exp):
                continue
            variants, stats = emi_variants(rng, grp, inputs, 3)
            if variants is None:
                continue
            vexp = []
            ok = True
            for vb, _k in variants:
                fns2 = dict(grp["fns"])
                fns2["__v"] = dict(main, name="__v", body=vb)
                ex2 = Exec(fns2)
                try:
                    vexp.append([ex2.call("__v", row) for row in inputs])
                except Exception:
                    ok = False
                    break
            if not ok:
                continue
            grp.update(inputs=inputs, expected=exp, variants=variants, vexpected=vexp, stats=stats)
            groups.append(grp)
            break
    return groups


def group_events(grp):
    evs = []
    for names in grp["order"]:
        fs = [grp["fns"][n] for n in names]
        if len(fs) == 1:
            evs.append(render_defun(fs[0]))
        else:
            evs.append("(mutual-recursion %s)" % " ".join(render_defun(f) for f in fs))
    main = grp["fns"][grp["main"]]
    for i, (vb, _k) in enumerate(grp["variants"]):
        v = dict(main, name="%s-emi%d" % (main["name"], i), body=vb)
        evs.append(render_defun(v))
    gid = grp["gid"]
    pre = ["(defun w4id-%d (x) (declare (xargs :guard (integerp x))) x)" % gid]
    return "(progn %s)" % "\n  ".join(pre + evs)


def fn_names(grp):
    main = grp["main"]
    return [main] + ["%s-emi%d" % (main, i) for i in range(len(grp["variants"]))]


def query_forms(grp, modes):
    out = []
    names = fn_names(grp)
    exps = [grp["expected"]] + grp["vexpected"]
    for mode in modes:
        out.append("(set-guard-checking %s)" % mode)
        for vi, (nm, ex) in enumerate(zip(names, exps)):
            for ii, (row, e) in enumerate(zip(grp["inputs"], ex)):
                call = "(%s %s)" % (nm, " ".join(str(a) for a in row))
                out.append('(cw "@V %d %d %d %s ~x0~%%" (let ((v %s)) (if (equal v %d) :ok '
                           '(list :bad (if (integerp v) (mod v 1000000007) v)))))'
                           % (grp["gid"], vi, ii, mode, call, e))
    return out


PRELUDE = """(in-package "ACL2")
(set-ignore-ok t)
(set-irrelevant-formals-ok t)
"""
QUIET = "(set-inhibit-output-lst '(prove proof-tree event summary history observation))\n"
TT_CHECK = ('(cw "@TT ~x0 ~x1 ~x2~%" (global-val \'ttags-seen (w state)) '
            '(global-val \'skip-proofs-seen (w state)) (global-val \'redef-seen (w state)))\n')


def parse_v(out):
    res = {}
    for m in re.finditer(r"@V (\d+) (\d+) (\d+) (\S+) (.*)", out):
        res[(int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4).upper())] = m.group(5).strip()
    return res


def run_pipeline_a(rt, groups, tmp, log):
    d = tempfile.mkdtemp(prefix="a-%s-" % rt, dir=tmp)
    anomalies = []
    modes = [":all", "t", "nil", ":none"]
    s = [PRELUDE, QUIET]
    for grp in groups:
        s.append(group_events(grp) + "\n")
        s.append('(cw "@ADM %d ~x0~%%" (len (remove-equal :common-lisp-compliant (list %s))))\n' % (
            grp["gid"], " ".join("(getpropc '%s 'symbol-class nil (w state))" % n for n in fn_names(grp))))
    for grp in groups:
        s.extend(q + "\n" for q in query_forms(grp, modes))
    s.append(TT_CHECK)
    rc, out = run_acl2(rt, "".join(s), d, 900)
    admitted = {}
    for m in re.finditer(r"@ADM (\d+) (\d+)", out):
        admitted[int(m.group(1))] = int(m.group(2))
    adm_ok = [g for g in groups if admitted.get(g["gid"]) == 0]
    res = parse_v(out)
    nq = nok = 0
    for g in adm_ok:
        for vi in range(1 + len(g["variants"])):
            for ii in range(len(g["inputs"])):
                for mode in modes:
                    nq += 1
                    r = res.get((g["gid"], vi, ii, mode.upper()))
                    if r == ":OK":
                        nok += 1
                    else:
                        anomalies.append("%s A session gid=%d var=%d inp=%d mode=%s got=%s" %
                                         (rt, g["gid"], vi, ii, mode, r))
    for m in CRASH_RE.finditer(out):
        anomalies.append("%s A session crash-pattern: %s" % (rt, out[max(0, m.start() - 200):m.end() + 200]))
    tt = re.search(r"@TT (.*)", out)
    if not tt or tt.group(1).strip() != "NIL NIL NIL":
        anomalies.append("%s A ttags/skip-proofs/redef not NIL: %s" % (rt, tt and tt.group(1)))
    # certify-book + include-book route over admitted groups
    book = [PRELUDE] + [group_events(g) + "\n" for g in adm_ok]
    with open(os.path.join(d, "emi.lisp"), "w") as fh:
        fh.write("".join(book))
    rc2, out2 = run_acl2(rt, QUIET + '(certify-book "emi" 0 t)\n', d, 900)
    certified = os.path.exists(os.path.join(d, "emi.cert"))
    nbq = nbok = 0
    if adm_ok and not certified:
        anomalies.append("%s A certify-book failed (rc=%d): %s" % (rt, rc2, out2[-1500:]))
    if certified:
        q = [PRELUDE, QUIET, '(include-book "emi")\n']
        for g in adm_ok:
            q.extend(x + "\n" for x in query_forms(g, ["t", ":none"]))
        q.append(TT_CHECK)
        rc3, out3 = run_acl2(rt, "".join(q), d, 900)
        if re.search(r"Compiled file|compiled file .* not found|load the compiled", out3, re.I):
            anomalies.append("%s A include-book fell back to source" % rt)
        res3 = parse_v(out3)
        for g in adm_ok:
            for vi in range(1 + len(g["variants"])):
                for ii in range(len(g["inputs"])):
                    for mode in ["t", ":none"]:
                        nbq += 1
                        r = res3.get((g["gid"], vi, ii, mode.upper()))
                        if r == ":OK":
                            nbok += 1
                        else:
                            anomalies.append("%s A book gid=%d var=%d inp=%d mode=%s got=%s" %
                                             (rt, g["gid"], vi, ii, mode, r))
        for m in CRASH_RE.finditer(out3):
            anomalies.append("%s A book crash-pattern: %s" % (rt, out3[max(0, m.start() - 200):m.end() + 200]))
    # admission failure diagnostics
    fails = [g["gid"] for g in groups if g not in adm_ok]
    log.append("[%s] A: groups=%d admitted+guard-verified=%d (%.1f%%) session-queries=%d ok=%d "
               "book-certified=%s book-queries=%d ok=%d rc=%d" %
               (rt, len(groups), len(adm_ok), 100.0 * len(adm_ok) / max(1, len(groups)), nq, nok,
                certified, nbq, nbok, rc))
    if fails:
        log.append("[%s] A: not admitted gids=%s non-compliant-counts=%s" % (
            rt, fails[:12], [admitted.get(x) for x in fails[:12]]))
        if os.environ.get("W4_DEBUG"):
            for m in list(re.finditer(r"ACL2 Error[^\n]*\n(.{0,600})", out, re.S))[:3]:
                log.append(m.group(0))
    return anomalies, {"groups": len(groups), "admitted": len(adm_ok), "q": nq + nbq, "ok": nok + nbok}


# ======================================================================================
# Pipeline B: non-ground dual interpretation
# ======================================================================================
class Sym(str):
    pass


class Cons(tuple):
    pass


GRID1 = list(range(-3, 13)) + [Fraction(1, 2), Fraction(-5, 2), None, Sym("A"), Cons((1, 2))]
GRID2 = [(a, b) for a in list(range(-2, 11)) + [None, Fraction(1, 2)] for b in range(-2, 11)]


def p_nfix(v):
    return v if isinstance(v, int) and not isinstance(v, bool) and v >= 0 else 0


def p_ifix(v):
    return v if isinstance(v, int) and not isinstance(v, bool) else 0


def p_num(v):
    return v if isinstance(v, (int, Fraction)) and not isinstance(v, bool) else 0


def p_zp(v):
    return p_nfix(v) == 0


# models: name -> (ACL2 body over x, python)
MODELS = {
    "zero": ("0", lambda x: 0),
    "seven": ("7", lambda x: 7),
    "nfix": ("(nfix x)", p_nfix),
    "min5": ("(min (nfix x) 5)", lambda x: min(p_nfix(x), 5)),
    "dbl": ("(* 2 (nfix x))", lambda x: 2 * p_nfix(x)),
    "sgn": ("(if (zp x) 0 1)", lambda x: 0 if p_zp(x) else 1),
    "mod3": ("(mod (nfix x) 3)", lambda x: p_nfix(x) % 3),
    "half": ("(floor (nfix x) 2)", lambda x: p_nfix(x) // 2),
    "succ": ("(+ 1 (nfix x))", lambda x: 1 + p_nfix(x)),
    "negn": ("(- (nfix x))", lambda x: -p_nfix(x)),
    "ifix": ("(ifix x)", p_ifix),
    "sq": ("(* (ifix x) (ifix x))", lambda x: p_ifix(x) ** 2),
    "evz": ("(* 2 (floor (nfix x) 2))", lambda x: 2 * (p_nfix(x) // 2)),
    "cap10": ("(if (< (nfix x) 10) (nfix x) 10)", lambda x: min(p_nfix(x), 10)),
    "pred": ("(if (zp x) 0 (1- x))", lambda x: 0 if p_zp(x) else x - 1),
    "absi": ("(abs (ifix x))", lambda x: abs(p_ifix(x))),
}


def acl2_le(a, b):
    return p_num(a) <= p_num(b)


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


# properties: name -> (hyps(list of ACL2 strs), concl ACL2 str, vars, python predicate(f) over grid)
def _prop(hyps, concl, vars_, py):
    return {"hyps": hyps, "concl": concl, "vars": vars_, "py": py}


PROPS = {
    "nat": _prop([], "(natp (F x))", ["x"], lambda f, x: is_int(f(x)) and f(x) >= 0),
    "int": _prop([], "(integerp (F x))", ["x"], lambda f, x: is_int(f(x))),
    "le5": _prop([], "(<= (F x) 5)", ["x"], lambda f, x: acl2_le(f(x), 5)),
    "f0": _prop([], "(equal (F 0) 0)", [], lambda f: f(0) == 0),
    "idem": _prop([], "(equal (F (F x)) (F x))", ["x"], lambda f, x: f(f(x)) == f(x)),
    "nfixinv": _prop([], "(equal (F (nfix x)) (F x))", ["x"], lambda f, x: f(p_nfix(x)) == f(x)),
    "even": _prop([], "(integerp (* 1/2 (F x)))", ["x"],
                  lambda f, x: is_int(f(x)) and f(x) % 2 == 0),
    "pos": _prop([], "(< 0 (F x))", ["x"], lambda f, x: p_num(f(x)) > 0),
    "leid": _prop(["(natp x)"], "(<= (F x) x)", ["x"],
                  lambda f, x: not (is_int(x) and x >= 0) or acl2_le(f(x), x)),
    "geid": _prop(["(natp x)"], "(<= x (F x))", ["x"],
                  lambda f, x: not (is_int(x) and x >= 0) or acl2_le(x, f(x))),
    "step": _prop(["(natp x)"], "(<= (F x) (F (+ 1 x)))", ["x"],
                  lambda f, x: not (is_int(x) and x >= 0) or acl2_le(f(x), f(x + 1))),
    "lip": _prop(["(natp x)"], "(<= (F (+ 1 x)) (+ 1 (F x)))", ["x"],
                 lambda f, x: not (is_int(x) and x >= 0) or acl2_le(f(x + 1), p_num(f(x)) + 1)),
    "mono": _prop(["(natp x)", "(natp y)", "(<= x y)"], "(<= (F x) (F y))", ["x", "y"],
                  lambda f, x, y: not (is_int(x) and is_int(y) and 0 <= x <= y) or acl2_le(f(x), f(y))),
    "inj": _prop(["(natp x)", "(natp y)", "(equal (F x) (F y))"], "(equal x y)", ["x", "y"],
                 lambda f, x, y: not (is_int(x) and is_int(y) and x >= 0 and y >= 0 and f(x) == f(y))
                 or x == y),
    "subadd": _prop(["(natp x)", "(natp y)"], "(<= (F (+ x y)) (+ (F x) (F y)))", ["x", "y"],
                    lambda f, x, y: not (is_int(x) and is_int(y) and x >= 0 and y >= 0)
                    or acl2_le(f(x + y), p_num(f(x)) + p_num(f(y)))),
}


def holds(prop, f):
    p = PROPS[prop]
    try:
        if not p["vars"]:
            return (True, None) if p["py"](f) else (False, ())
        if len(p["vars"]) == 1:
            for x in GRID1:
                if not p["py"](f, x):
                    return False, (x,)
            return True, None
        for x, y in GRID2:
            if not p["py"](f, x, y):
                return False, (x, y)
        return True, None
    except TypeError:
        return False, None


def lit(v):
    if v is None:
        return "nil"
    if isinstance(v, Sym):
        return "'a"
    if isinstance(v, Cons):
        return "'(1 . 2)"
    if isinstance(v, Fraction):
        return "%d/%d" % (v.numerator, v.denominator) if v.denominator != 1 else str(v.numerator)
    return str(v)


def formula(prop, fname, wrap=None):
    p = PROPS[prop]
    concl = p["concl"].replace("F", fname)
    hyps = [h.replace("(F ", "(%s " % fname) for h in p["hyps"]]
    if wrap:
        hyps = ["(%s %s)" % (wrap, h) for h in hyps]
    if not hyps:
        return concl
    return "(implies %s %s)" % (hyps[0] if len(hyps) == 1 else "(and %s)" % " ".join(hyps), concl)


def rule_class(prop, rng):
    c = PROPS[prop]["concl"]
    if prop == "inj":
        return rng.choice(["nil", ":forward-chaining"]) if False else "nil"
    opts = [":rewrite", "nil"]
    if c.startswith("(<=") or c.startswith("(<"):
        opts.append(":linear")
    if prop in ("nat", "int"):
        opts.append(":type-prescription")
    return rng.choice(opts)


def gen_theory(rng, tid):
    models = list(MODELS)
    for _ in range(400):
        mt, mf = rng.sample(models, 2)
        ft, ff = MODELS[mt][1], MODELS[mf][1]
        both = [p for p in PROPS if holds(p, ft)[0] and holds(p, ff)[0]]
        sep = [p for p in PROPS if holds(p, ft)[0] and not holds(p, ff)[0] and holds(p, ff)[1] is not None]
        if not sep or not both:
            continue
        phi = rng.choice(sep)
        k = rng.randint(1, min(3, len(both)))
        cons = rng.sample(both, k)
        wit = holds(phi, ff)[1]
        return {"tid": tid, "mt": mt, "mf": mf, "cons": cons, "phi": phi, "wit": wit,
                "wrap": rng.choice([None, None, "force", "case-split"]),
                "rcs": [rule_class(c, rng) for c in cons],
                "cong": "nfixinv" in cons and rng.random() < 0.7,
                "sk_constrain": rng.choice(["t", "nil"]),
                "ch_strengthen": rng.choice(["t", "nil"])}
    return None


def theory_script(th):
    t = th["tid"]
    f, mf = "uf%d" % t, "mf%d" % t
    lines = []
    exports = []
    for i, (c, rc) in enumerate(zip(th["cons"], th["rcs"])):
        if c == "nfixinv" and th["cong"]:
            continue
        exports.append("(defthm c%d-%d %s :rule-classes %s)" % (t, i, formula(c, f, th["wrap"]), rc))
    if th["cong"]:
        lines.append("(defun neqv%d (a b) (equal (nfix a) (nfix b)))" % t)
        lines.append("(defequiv neqv%d)" % t)
        exports.append("(defcong neqv%d equal (%s x) 1)" % (t, f))
    lines.append("(encapsulate (((%s *) => *)) (local (defun %s (x) %s)) %s)" % (
        f, f, MODELS[th["mt"]][0], " ".join(exports)))
    lines.append('(cw "@ENC %d ~x0~%%" (not (eq (getpropc \'%s \'formals :none (w state)) :none)))'
                 % (t, f))
    lines.append("(defun %s (x) %s)" % (mf, MODELS[th["mf"]][0]))
    for i, c in enumerate(th["cons"]):
        lines.append("(with-prover-time-limit 6 (defthm mc%d-%d %s :rule-classes nil))" % (t, i, formula(c, mf)))
    lines.append('(cw "@MF %d ~x0~%%" (list %s))' % (t, " ".join(
        "(not (eq (getpropc 'mc%d-%d 'theorem :none (w state)) :none))" % (t, i)
        for i in range(len(th["cons"])))))
    # positive control: a constraint restated, must prove
    ctlp = [c for c in th["cons"] if not (c == "nfixinv" and th["cong"])]
    th["ctlp"] = ctlp[0] if ctlp else None
    lines.append("(with-prover-time-limit 6 (defthm ctl%d %s :rule-classes nil))" % (
        t, formula(ctlp[0], f) if ctlp else "(implies (neqv%d a b) (equal (%s a) (%s b)))" % (t, f, f)))
    lines.append('(cw "@CTL %d ~x0~%%" (not (eq (getpropc \'ctl%d \'theorem :none (w state)) :none)))' % (t, t))
    # ground refutation of phi under M_false
    p = PROPS[th["phi"]]
    gphi = formula(th["phi"], mf)
    binds = " ".join("(%s %s)" % (v, lit(w)) for v, w in zip(p["vars"], th["wit"] or ()))
    gnd = "(let (%s) %s)" % (binds, gphi) if binds else gphi
    lines.append('(cw "@GW %d ~x0~%%" %s)' % (t, gnd))
    # --- attack variants on phi (all expected to FAIL) ---
    phi = formula(th["phi"], f)
    vs = p["vars"]
    lines.append("(with-prover-time-limit 8 (defthm phi%d-v0 %s :rule-classes nil :otf-flg t))" % (t, phi))
    lines.append("(with-prover-time-limit 8 (defthm phi%d-v1 %s :rule-classes nil :otf-flg t "
                 ":hints ((\"Goal\" :do-not '(generalize fertilize) :expand ((%s x))))))" % (t, phi, f)
                 if vs else "")
    if vs:
        lines.append("(defun-sk sk%d-all () (forall (%s) %s) :constrain %s)" % (
            t, " ".join(vs), phi, th["sk_constrain"]))
        lines.append("(with-prover-time-limit 8 (defthm phi%d-v2 (sk%d-all) :rule-classes nil :otf-flg t))" % (t, t))
        lines.append("(defun-sk sk%d-bad () (exists (%s) (not %s)) :strengthen %s)" % (
            t, " ".join(vs), phi, th["ch_strengthen"]))
        lines.append("(with-prover-time-limit 8 (defthm phi%d-v3 (not (sk%d-bad)) :rule-classes nil :otf-flg t))"
                     % (t, t))
        lines.append("(defchoose ch%d (%s) () (not %s) :strengthen %s)" % (
            t, " ".join(vs), phi, th["ch_strengthen"]))
        chbody = ("(let ((x (ch%d))) %s)" % (t, phi)) if len(vs) == 1 else \
            ("(mv-let (x y) (ch%d) %s)" % (t, phi))
        lines.append("(with-prover-time-limit 8 (defthm phi%d-v4 %s :rule-classes nil :otf-flg t))" % (t, chbody))
    # FI smuggle probe: functional instance of a constraint onto M_false, then phi about M_false
    # FI-smuggle probe: a GROUND-FALSE statement about M_false, with a functional-instance hint
    lines.append("(with-prover-time-limit 8 (defthm phi%d-v5 %s :rule-classes nil :otf-flg t :hints ((\"Goal\" "
                 ":use ((:functional-instance ctl%d (%s %s)))))))" % (t, formula(th["phi"], mf), t, f, mf))
    names = ["phi%d-v%d" % (t, i) for i in range(6)]
    lines.append('(cw "@PHI %d ~x0~%%" (list %s))' % (t, " ".join(
        "(not (eq (getpropc '%s 'theorem :none (w state)) :none))" % n for n in names)))
    # automatic nil derivation if any variant proved
    inst = " ".join("(%s %s)" % (v, lit(w)) for v, w in zip(vs, th["wit"] or ()))
    use_v = {"v2": "sk%d-all-necc" % t, "v3": "sk%d-bad-suff" % t, "v4": "ch%d" % t}
    plain_hint = " ".join(
        "(if (not (eq (getpropc 'phi%d-%s 'theorem :none (w state)) :none)) '(phi%d-%s %s) nil)"
        % (t, k, t, k, v) for k, v in use_v.items())
    lines.append("(make-event (if (not (eq (getpropc 'phi%d-v0 'theorem :none (w state)) :none)) "
                 "'(defthm phi%d-plain %s :rule-classes nil :hints ((\"Goal\" :use phi%d-v0))) "
                 "(let ((u (append %s))) (if u (list 'defthm 'phi%d-plain '%s :rule-classes nil :hints "
                 "(list (list \"Goal\" :use u))) '(value-triple :no-phi)))))" % (
                     t, t, phi, t, plain_hint, t, phi))
    lines.append("(make-event (if (not (eq (getpropc 'phi%d-plain 'theorem :none (w state)) :none)) "
                 "'(defthm nil-proved-%d nil :rule-classes nil :hints ((\"Goal\" :use (%s)))) "
                 "'(value-triple :no-nil)))" % (
                     t, t, ("(:instance (:functional-instance phi%d-plain (%s %s)) %s)" % (t, f, mf, inst))
                     if inst else "(:functional-instance phi%d-plain (%s %s))" % (t, f, mf)))
    lines.append('(cw "@NIL %d ~x0~%%" (not (eq (getpropc \'nil-proved-%d \'theorem :none (w state)) :none)))'
                 % (t, t))
    return "\n".join(x for x in lines if x) + "\n"


def run_pipeline_b(rt, theories, tmp, log, batch=6):
    d = tempfile.mkdtemp(prefix="b-%s-" % rt, dir=tmp)
    anomalies = []
    stats = {"theories": 0, "enc": 0, "mf_valid": 0, "ctl": 0, "gw": 0, "attempts": 0, "qed": 0, "nil": 0}
    for i in range(0, len(theories), batch):
        chunk = theories[i:i + batch]
        s = PRELUDE + QUIET + "".join(theory_script(th) for th in chunk) + TT_CHECK
        rc, out = run_acl2(rt, s, d, 120 * len(chunk) + 60)
        for th in chunk:
            t = th["tid"]
            stats["theories"] += 1
            enc = re.search(r"@ENC %d (\S+)" % t, out)
            if enc and enc.group(1) == "T":
                stats["enc"] += 1
            mfv = re.search(r"@MF %d \((.*)\)" % t, out)
            if mfv and "NIL" not in mfv.group(1).split():
                stats["mf_valid"] += 1
            ctl = re.search(r"@CTL %d (\S+)" % t, out)
            if ctl and ctl.group(1) == "T":
                stats["ctl"] += 1
            elif enc and enc.group(1) == "T":
                log.append("[%s] B tid=%d positive control did not prove (%s)" % (rt, t, th["cons"][0]))
            gw = re.search(r"@GW %d (\S+)" % t, out)
            if gw and gw.group(1) == "NIL":
                stats["gw"] += 1
            elif gw:
                anomalies.append("%s B tid=%d ground witness of phi on M_false evaluated %s (model bug?)"
                                 % (rt, t, gw.group(1)))
            ph = re.search(r"@PHI %d \((.*)\)" % t, out)
            if ph:
                vals = ph.group(1).split()
                stats["attempts"] += len(vals)
                if "T" in vals:
                    stats["qed"] += 1
                    mfok = mfv and "NIL" not in mfv.group(1).split()
                    anomalies.append("%s B tid=%d phi variant PROVED %s (phi=%s Mt=%s Mf=%s cons=%s "
                                     "Mf-model-valid=%s)" % (rt, t, vals, th["phi"], th["mt"], th["mf"],
                                                              th["cons"], bool(mfok)))
            nl = re.search(r"@NIL %d (\S+)" % t, out)
            if nl and nl.group(1) == "T":
                stats["nil"] += 1
                anomalies.append("%s B tid=%d *** nil-proved-%d Q.E.D. ***" % (rt, t, t))
        for m in CRASH_RE.finditer(out):
            anomalies.append("%s B crash-pattern: %s" % (rt, out[max(0, m.start() - 300):m.end() + 300]))
        tt = re.search(r"@TT (.*)", out)
        if not tt or tt.group(1).strip() != "NIL NIL NIL":
            anomalies.append("%s B ttags/skip-proofs/redef not NIL: %s (rc=%d)" % (rt, tt and tt.group(1), rc))
    log.append("[%s] B: %s" % (rt, " ".join("%s=%d" % kv for kv in stats.items())))
    return anomalies, stats


# ======================================================================================
def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--cases", type=int, default=20)
    ap.add_argument("--mode", choices=["all", "emi", "nonground"], default="all")
    ap.add_argument("--runtime", choices=["both", "sbcl", "ccl"], default="both")
    ap.add_argument("--keep", action="store_true", help="keep the scratch dir (debug)")
    a = ap.parse_args()
    rng = random.Random(a.seed)
    random.seed(a.seed)
    rts = ["sbcl", "ccl"] if a.runtime == "both" else [a.runtime]
    tmp = tempfile.mkdtemp(prefix="w4-astra-acl2-", dir="/tmp")
    t0 = time.time()
    log, anomalies = [], []
    try:
        groups = build_pipeline_a(rng, a.cases) if a.mode in ("all", "emi") else []
        theories = []
        if a.mode in ("all", "nonground"):
            for t in range(a.cases):
                th = gen_theory(rng, t)
                if th:
                    theories.append(th)
        if groups:
            kinds = {}
            for g in groups:
                for _vb, ks in g["variants"]:
                    for k in ks:
                        kinds[k] = kinds.get(k, 0) + 1
            log.append("A: generated groups=%d EMI-mutation-kinds=%s sites(total/live)=%d/%d" % (
                len(groups), dict(sorted(kinds.items())), sum(g["stats"]["sites"] for g in groups),
                sum(g["stats"]["live_sites"] for g in groups)))
        jobs = []
        with ThreadPoolExecutor(max_workers=4) as pool:
            for rt in rts:
                if groups:
                    jobs.append(pool.submit(run_pipeline_a, rt, groups, tmp, log))
                if theories:
                    jobs.append(pool.submit(run_pipeline_b, rt, theories, tmp, log))
            for j in jobs:
                an, _st = j.result()
                anomalies.extend(an)
    finally:
        if a.keep:
            print("scratch kept:", tmp)
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    print("== fuzz_acl2_emi_non_ground seed=%d cases=%d mode=%s runtimes=%s (%.0fs)" % (
        a.seed, a.cases, a.mode, ",".join(rts), time.time() - t0))
    for line in log:
        print(line)
    print("anomalies: %d" % len(anomalies))
    for x in anomalies[:60]:
        print("  !", x[:1500])
    return 1 if anomalies else 0


if __name__ == "__main__":
    sys.exit(main())
