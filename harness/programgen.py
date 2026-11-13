#!/usr/bin/env python3
"""Typed whole-program generation for compositional differential testing.

A program is a set of ACL2 defuns with declared parameter types, produced by
typed top-down synthesis so that:

  * every guard-satisfying input has an exact Python-oracle value,
  * termination is structural (list driver) or arithmetical (nat driver),
  * return types hold by construction, so standalone ``ftype`` declarations
    are true -- mirroring how ACL2 proclaims the types of verified guards.

Programs are *composed*: chain/linear/tree/mutual structures call across
function boundaries, with driver arguments decreasing so recursion is real,
and with constants chosen to cross fixnum/bignum seams.

The state space is enumerated over the product of small axes
(structure x type-mix x guard-mode x op-flavor), so each generated corpus is
a covering sweep of program shapes, not a random pepper.

Entry points:
  axes()                    -> the axis definitions
  enumerate_programs(...)   -> deterministic corpus (list of Program)
  render_acl2(program)      -> ACL2 event text (defuns + verify-guards)
  render_cl(program, inline)-> standalone Common Lisp text
  term_battery(program)     -> call terms with oracle expectations
"""

from dataclasses import dataclass
from fractions import Fraction
import hashlib
import random

from forms_acl2 import (
    AuditError, ComplexRational, ListValue, NIL, Symbol, String, T, ZERO,
    render as render_value,
)


# ---------------------------------------------------------------------------
# types
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class TInt:
    lo: object = None
    hi: object = None


@dataclass(frozen=True)
class TRat:
    pass


@dataclass(frozen=True)
class TList:
    elem: str = "int"  # int | rat | sym


@dataclass(frozen=True)
class TSym:
    pass


@dataclass(frozen=True)
class TStr:
    pass


@dataclass(frozen=True)
class TChar:
    pass


WIDE = 10 ** 18
DRIVER_HI = 10 ** 6


# ---------------------------------------------------------------------------
# value grids (boundary-biased, deterministic)
# ---------------------------------------------------------------------------

INT_GRID = (
    0, 1, -1, 2, 3, -4,
    (1 << 29) - 1, -(1 << 29), 1 << 30, -(1 << 30),
    (1 << 59) - 1, 1 << 59, -(1 << 59), -(1 << 60), 1 << 61, -(1 << 61),
    (1 << 63) - 1, -(1 << 63), 1 << 64, -(1 << 64), 1000001, 12345,
)

RAT_GRID = (
    Fraction(1, 2), Fraction(-1, 2), Fraction(2, 3), Fraction(-5, 2),
    Fraction(1, 3), Fraction(-1, 7), Fraction(9, 4), Fraction(-9, 4),
    Fraction(1, 1024), Fraction(-(1 << 40), 3), Fraction(1 << 40, 7),
    Fraction(0, 1), Fraction(7, 1), Fraction(-13, 1),
)

SYM_GRID = (NIL, T, Symbol("A"), Symbol("B"))

STR_GRID = ("", "a", "hello world!!", "x" * 33, 'q"\\z')

CHAR_GRID = ("a", "A", "0", " ", "~", "\n")

LIST_GRID = {
    "int": ((), (0,), (1, 2, 3), (-1, 0, 1), tuple(range(8)), (1 << 60, -(1 << 60)),
            tuple(range(33)), (5,)),
    "rat": ((), (Fraction(1, 2),), (Fraction(1, 3), Fraction(-2, 3), Fraction(7, 1)),
            (Fraction(1, 1024), Fraction(-(1 << 40), 3)), tuple(range(5))),
    "sym": ((NIL,), (T, Symbol("A")), (NIL, T, Symbol("A"), Symbol("B")), ()),
}


def grid_values(typ, rng, count):
    """Deterministic boundary-biased sample of guard-satisfying values."""
    if isinstance(typ, TInt):
        pool = [Fraction(v) for v in INT_GRID]
        if typ.lo is not None:
            pool = [v for v in pool if typ.lo <= v <= (typ.hi if typ.hi is not None else WIDE)]
        if not pool:
            pool = [v for v in (0, 1, 2, 3) if _fits_int(typ, v)]
    elif isinstance(typ, TRat):
        pool = list(RAT_GRID)
    elif isinstance(typ, TSym):
        pool = list(SYM_GRID)
    elif isinstance(typ, TStr):
        pool = [String(s) for s in STR_GRID]
    elif isinstance(typ, TChar):
        pool = [CharVal(c) for c in CHAR_GRID]
    elif isinstance(typ, TList):
        def _conv(item):
            if typ.elem in ("int", "rat") and isinstance(item, int):
                return Fraction(item)
            return item
        pool = [tuple(_conv(i) for i in items) for items in LIST_GRID[typ.elem]]
    else:
        raise TypeError(f"no grid for {typ!r}")
    ordered = list(pool)
    rng.shuffle(ordered)
    return ordered[:count]


def violating_values(typ, rng, count):
    """Values that violate the guard for ``typ`` (type-wrong, out-of-range)."""
    if isinstance(typ, TInt):
        pool = [Symbol("A"), "text", NIL, Fraction(1, 2), -10 ** 30, 10 ** 30]
        if typ.lo is not None and typ.lo > -(10 ** 30):
            pool = pool[2:6]
    elif isinstance(typ, TRat):
        pool = [Symbol("A"), NIL, "text", ComplexRational(1, 2)]
    elif isinstance(typ, TSym):
        pool = [Fraction(1, 2), "text", NIL and 0, 0]
    elif isinstance(typ, TStr):
        pool = [Symbol("A"), 3, NIL, Fraction(1, 2)]
    elif isinstance(typ, TChar):
        pool = [CharVal("x"), 97, NIL, Symbol("A")]
    elif isinstance(typ, TList):
        pool = [Symbol("A"), 5, "text", NIL and Fraction(1, 2)]
    else:
        raise TypeError(f"no violating grid for {typ!r}")
    pool = [v for v in pool if not _fits(typ, v)]
    return pool[:count]


def _fits(typ, value):
    if isinstance(typ, TInt):
        return _fits_int(typ, value)
    if isinstance(typ, TRat):
        return isinstance(value, Fraction)
    if isinstance(typ, TSym):
        return isinstance(value, Symbol) or value in (NIL, T)
    if isinstance(typ, TStr):
        return isinstance(value, String)
    if isinstance(typ, TChar):
        return isinstance(value, CharVal)
    if isinstance(typ, TList):
        return isinstance(value, tuple)
    return False


def _fits_int(typ, value):
    ok = isinstance(value, int) and not isinstance(value, bool)
    if ok and typ.lo is not None:
        ok = typ.lo <= value
    if ok and typ.hi is not None:
        ok = value <= typ.hi
    return ok


class CharVal:
    """A Common Lisp character (shared by the ACL2 and CL universes)."""

    __slots__ = ("ch",)

    def __init__(self, ch):
        self.ch = ch

    def __eq__(self, other):
        return isinstance(other, CharVal) and self.ch == other.ch

    def __hash__(self):
        return hash(("CharVal", self.ch))

    def __repr__(self):
        return f"CharVal({self.ch!r})"


CHAR_NAMES = {" ": "Space", "\n": "Newline", "\t": "Tab"}


def render_char(value):
    name = CHAR_NAMES.get(value.ch)
    if name:
        return f"#\\{name}"
    if value.ch.isalnum() and value.ch.isascii():
        return f"#\\{value.ch}"
    return f"#\\{chr(ord(value.ch))}"


def render_const(value):
    """Render a universe value as an ACL2/CL reader form."""
    if isinstance(value, CharVal):
        return render_char(value)
    if isinstance(value, tuple):
        if not value:
            return "NIL"
        return "'(" + " ".join(render_const(item) for item in value) + ")"
    if isinstance(value, int) and not isinstance(value, bool):
        value = Fraction(value)
    text = render_value(value)
    if isinstance(value, Symbol) and value not in (NIL, T):
        return "'" + text
    return text


# ---------------------------------------------------------------------------
# AST
# ---------------------------------------------------------------------------
# ('var', name)            uppercase on render
# ('const', value)
# ('if', test, then, else)
# ('let', ((name, ast), ...), body)
# ('prim', op, (ast, ...))
# ('call', fn-index, (ast, ...))


# ---------------------------------------------------------------------------
# operator tables
# ---------------------------------------------------------------------------

# name -> (arity, acl2-name, cl-name, arg-kind, result-kind)
# kind: 'int' | 'num' | 'list-elem-aware' handled by productions, not here.
BINARY_INT_OPS = ("+", "-", "*", "min", "max")
DIV_OPS = ("floor", "mod", "truncate", "rem")
BIT_OPS = ("logand", "logior", "logxor", "ash")

ACL2_NAMES = {
    "+": "+", "-": "-", "*": "*", "min": "MIN", "max": "MAX",
    "floor": "FLOOR", "mod": "MOD", "truncate": "TRUNCATE", "rem": "REM",
    "/": "/", "expt": "EXPT",
    "logand": "LOGAND", "logior": "LOGIOR", "logxor": "LOGXOR",
    "lognot": "LOGNOT", "ash": "ASH", "logbitp": "LOGBITP",
    "integer-length": "INTEGER-LENGTH",
    "<": "<", "<=": "<=", ">": ">", ">=": ">=", "=": "=",
    "zp": "ZP", "natp": "NATP", "integerp": "INTEGERP", "rationalp": "RATIONALP",
    "acl2-numberp": "ACL2-NUMBERP", "evenp": "EVENP", "oddp": "ODDP",
    "consp": "CONSP", "atom": "ATOM", "true-listp": "TRUE-LISTP",
    "stringp": "STRINGP", "symbolp": "SYMBOLP", "characterp": "CHARACTERP",
    "booleanp": "BOOLEANP", "endp": "ENDP",
    "cons": "CONS", "car": "CAR", "cdr": "CDR", "cddr": "CDDR",
    "len": "LEN", "nth": "NTH", "binary-append": "BINARY-APPEND",
    "equal": "EQUAL", "char-code": "CHAR-CODE", "code-char": "CODE-CHAR",
}
CL_NAMES = dict(ACL2_NAMES)
CL_NAMES.update({
    "len": "LENGTH", "acl2-numberp": "NUMBERP", "natp": "PROG-NATP",
    "zp": "PROG-ZP", "true-listp": "PROG-TRUE-LISTP", "binary-append": "APPEND",
    "nth": "PROG-NTH",
})

CL_HELPERS = """(defun prog-natp (x) (and (integerp x) (not (minusp x))))
(defun prog-zp (x) (if (integerp x) (eql x 0) t))
(defun prog-true-listp (x)
  (or (null x) (and (consp x) (prog-true-listp (cdr x)))))
(defun prog-nth (k x)
  (if (or (not (integerp k)) (minusp k) (not (prog-true-listp x)))
      nil
      (if (atom x) nil (if (eql k 0) (car x) (prog-nth (- k 1) (cdr x)))))
"""

ACL2_GUARD_NAMES = {
    "+": None, "-": None, "*": None, "min": "acl2-numberp", "max": "acl2-numberp",
    "floor": "div-real", "mod": "div-real", "truncate": "div-real", "rem": "div-real",
    "/": "div-nz", "expt": "expt",
    "logand": "integerp", "logior": "integerp", "logxor": "integerp",
    "lognot": "integerp", "ash": "integerp", "logbitp": "logbitp",
    "integer-length": "integerp",
    "<": "real", "<=": "real", ">": "real", ">=": "real", "=": "number",
    "zp": None, "natp": None, "integerp": None, "rationalp": None,
    "acl2-numberp": None, "evenp": "integerp", "oddp": "integerp",
    "consp": None, "atom": None, "true-listp": None,
    "stringp": None, "symbolp": None, "characterp": None, "booleanp": None,
    "endp": "true-listp",
    "cons": None, "car": None, "cdr": None, "cddr": None,
    "len": None, "nth": "nth", "binary-append": "true-listp-first",
    "equal": None, "char-code": "characterp", "code-char": "code-char",
}


def guard_conjunct(op, arg_vars):
    """Guard text fragment proving this primitive's guard from var guards."""
    kind = ACL2_GUARD_NAMES[op]
    if kind is None:
        return None
    if kind == "integerp":
        return " ".join(f"(INTEGERP {v})" for v in arg_vars)
    if kind == "real":
        return "(AND " + " ".join(f"(RATIONALP {v})" for v in arg_vars) + ")"
    if kind == "number":
        return "(AND " + " ".join(f"(ACL2-NUMBERP {v})" for v in arg_vars) + ")"
    if kind == "acl2-numberp":
        return " ".join(f"(ACL2-NUMBERP {v})" for v in arg_vars)
    if kind == "div-real":
        return f"(NOT (ZP {arg_vars[-1]}))"
    if kind == "div-nz":
        return f"(NOT (= {arg_vars[-1]} 0))"
    if kind == "expt":
        return f"(AND (ACL2-NUMBERP {arg_vars[0]}) (INTEGERP {arg_vars[1]}) (<= 0 {arg_vars[1]}))"
    if kind == "logbitp":
        return f"(INTEGERP {arg_vars[1]})"
    if kind == "nth":
        return f"(AND (NATP {arg_vars[0]}) (TRUE-LISTP {arg_vars[1]}))"
    if kind == "true-listp":
        return f"(TRUE-LISTP {arg_vars[0]})"
    if kind == "true-listp-first":
        return f"(TRUE-LISTP {arg_vars[0]})"
    if kind == "characterp":
        return f"(CHARACTERP {arg_vars[0]})"
    if kind == "code-char":
        return f"(AND (INTEGERP {arg_vars[0]}) (<= 0 {arg_vars[0]}) (< {arg_vars[0]} 256))"
    raise ValueError(f"unknown guard kind {kind!r} for {op!r}")


# ---------------------------------------------------------------------------
# program model
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Fn:
    index: int
    params: tuple           # ((NAME, type), ...)
    ret: object
    body: tuple
    driver: object          # param name or None
    guards: bool


@dataclass(frozen=True)
class Program:
    prog_id: str
    axes: dict
    fns: tuple              # Fn in call order (leaf first)


# ---------------------------------------------------------------------------
# synthesis
# ---------------------------------------------------------------------------

STRUCTURES = ("chain2", "chain3", "linear", "tree", "mutual2")
TYPES = ("int", "rat", "list-int", "sym", "str", "char", "mix-int-rat", "mix-int-list")
GUARD_MODES = ("verified", "unguarded")
FLAVORS = ("arith", "divmod", "bit", "list", "pred", "mixed")


class Synth:
    def __init__(self, rng, structure, type_mix, guards, flavor):
        self.rng = rng
        self.structure = structure
        self.type_mix = type_mix
        self.guards = guards == "verified"
        self.flavor = flavor
        self.allowed = self._flavor_ops()
        self._params_cache = None

    def _flavor_ops(self):
        all_ops = set(BINARY_INT_OPS) | set(DIV_OPS) | set(BIT_OPS) | {
            "/", "expt", "logbitp", "integer-length", "lognot",
            "<", "<=", ">", ">=", "=", "zp", "natp", "integerp", "rationalp",
            "acl2-numberp", "evenp", "oddp", "consp", "atom", "true-listp",
            "stringp", "symbolp", "characterp", "booleanp", "endp",
            "cons", "car", "cdr", "cddr", "len", "nth", "binary-append",
            "equal", "char-code", "code-char",
        }
        if self.flavor == "arith":
            return set(BINARY_INT_OPS) | {"expt"}
        if self.flavor == "divmod":
            return set(DIV_OPS) | {"/", "evenp", "oddp"}
        if self.flavor == "bit":
            return set(BIT_OPS) | {"lognot", "logbitp", "integer-length", "evenp", "oddp"}
        if self.flavor == "list":
            return {"cons", "car", "cdr", "cddr", "len", "nth", "binary-append",
                    "endp", "consp", "atom", "true-listp"}
        if self.flavor == "pred":
            return {"<", "<=", ">", ">=", "=", "zp", "natp", "integerp",
                    "rationalp", "acl2-numberp", "evenp", "oddp", "consp",
                    "atom", "true-listp", "stringp", "symbolp", "characterp",
                    "booleanp", "equal", "logbitp", "endp", "char-code", "code-char"}
        return all_ops

    # -- signature planning -------------------------------------------------

    def signatures(self):
        """Return (params_by_fn, ret) for the planned function layout."""
        count = {"chain2": 2, "chain3": 3, "linear": 2, "tree": 2, "mutual2": 2}[self.structure]
        params = self._params()
        return [(params(f_i) for _ in (0,)) for f_i in range(count)], None

    def _params(self):
        if getattr(self, "_params_cache", None) is not None:
            return self._params_cache
        mix = self.type_mix
        if mix == "int":
            return (("X", TInt()), ("N", TInt(0, DRIVER_HI)))
        if mix == "rat":
            return (("X", TRat()), ("N", TInt(0, DRIVER_HI)))
        if mix == "list-int":
            return (("X", TList("int")), ("N", TInt(0, 64)))
        if mix == "sym":
            return (("X", TSym()), ("N", TInt(0, DRIVER_HI)))
        if mix == "str":
            return (("X", TStr()), ("N", TInt(0, DRIVER_HI)))
        if mix == "char":
            return (("X", TChar()), ("N", TInt(0, DRIVER_HI)))
        if mix == "mix-int-rat":
            return (("X", TRat()), ("N", TInt(0, DRIVER_HI)))
        if mix == "mix-int-list":
            return (("X", TList("int")), ("N", TInt(0, 64)))
        raise ValueError(mix)

    def planned_params(self, _fn_index):
        return self._params()

    def ret_type(self):
        mix = self.type_mix
        if mix in ("int",):
            return TInt()
        if mix in ("rat", "mix-int-rat"):
            return TInt()
        if mix in ("list-int", "mix-int-list"):
            return TInt()
        if mix == "sym":
            return TSym()
        if mix == "str":
            return TStr()
        if mix == "char":
            return TChar()
        raise ValueError(mix)


def _driver_param(params, structure):
    """Pick the decreasing parameter: list param when present, else N."""
    for name, typ in params:
        if isinstance(typ, TList):
            return name, "list"
    for name, typ in params:
        if isinstance(typ, TInt) and typ.lo == 0:
            return name, "nat"
    return None, None


def make_program(prog_id, rng, structure, type_mix, guards, flavor):
    synth = Synth(rng, structure, type_mix, guards, flavor)
    params_t = synth._params()
    ret = synth.ret_type()
    count = {"chain2": 2, "chain3": 3, "linear": 2, "tree": 2, "mutual2": 2}[structure]
    driver, driver_kind = _driver_param(params_t, structure)

    fns = []
    for i in range(count):
        params = tuple((name, typ) for name, typ in params_t)
        fns.append((i, params))

    bodies = {}
    for i, params in reversed(fns):  # leaf first (highest index first)
        env = {name: typ for name, typ in params}
        is_mutual = structure == "mutual2"
        partner = 1 - i if is_mutual else None
        lower = [j for j in range(count) if j < i]
        self_ok = structure in ("linear", "tree") and i == count - 1
        if driver is not None and (
            (structure in ("linear", "tree") and i == count - 1)
            or is_mutual
        ):
            # recursion is the defining feature of this cell: force the
            # guarded recursive shape for the recursive function(s)
            body = _recursive_call_shape(
                synth, ret, env, 3, 6, lower, partner, driver,
                driver_kind, count, "self" if self_ok else partner,
            )
        else:
            body = synth_body(
                synth, ret, env, depth=3, budget=6, lower=lower,
                partner=partner, driver=driver, driver_kind=driver_kind,
                fn_count=count, self_ok=self_ok,
            )
        bodies[i] = Fn(i, params, ret, body, driver, synth.guards)

    fns_out = tuple(bodies[i] for i in range(count))
    return Program(prog_id, {
        "structure": structure, "types": type_mix, "guards": guards,
        "flavor": flavor, "driver": driver_kind or "none",
    }, fns_out)


def synth_body(synth, ret, env, depth, budget, lower, partner, driver,
               driver_kind, fn_count, self_ok=False):
    """Typed top-down expression synthesis (deterministic given rng)."""
    rng = synth.rng
    choices = []
    var_options = [n for n, t in env.items() if _assignable(t, ret)]
    if var_options:
        choices.append(("var", 2))
    choices.append(("const", 1))
    if depth > 0 and budget > 1:
        choices.append(("if", 3))
        prim = _prim_production(synth, ret, env)
        if prim is not None:
            choices.append(("prim", 6))
        if var_options and depth > 0:
            choices.append(("let", 2))
        if lower:
            choices.append(("call-lower", 4))
        if partner is not None and driver is not None:
            choices.append(("call-partner", 5))
        if self_ok and driver is not None:
            choices.append(("recurse", 6))
    if not choices or all(w == 0 for _, w in choices):
        choices = [("const", 1)]
    total = sum(w for _, w in choices)
    pick = rng.randrange(total)
    acc = 0
    chosen = choices[-1][0]
    for name, w in choices:
        acc += w
        if pick < acc:
            chosen = name
            break

    if chosen == "var":
        return ("var", rng.choice(var_options))
    if chosen == "const":
        return ("const", default_const(ret, rng))
    if chosen == "if":
        test = synth_test(synth, env)
        then = synth_body(synth, ret, env, depth - 1, budget - 1, lower,
                          partner, driver, driver_kind, fn_count, self_ok)
        other = synth_body(synth, ret, env, depth - 1, budget - 1, lower,
                           partner, driver, driver_kind, fn_count, self_ok)
        return ("if", test, then, other)
    if chosen == "prim":
        return _prim_production(synth, ret, env)(depth, budget, lower, partner,
                                                 driver, driver_kind, fn_count)
    if chosen == "let":
        name = fresh_name(env, rng)
        val_type = rng.choice([TInt(0, 64), TRat(), TInt(-64, 64)])
        val = synth_body(synth, val_type, env, depth - 1, budget - 2, lower,
                         partner, driver, driver_kind, fn_count, self_ok)
        inner = dict(env)
        inner[name] = val_type
        body = synth_body(synth, ret, inner, depth - 1, budget - 1, lower,
                          partner, driver, driver_kind, fn_count, self_ok)
        return ("let", ((name, val),), body)
    if chosen == "call-lower":
        callee = rng.choice(lower)
        callee_params = synth.planned_params(callee)
        args = []
        for _, typ in callee_params:
            candidates = [n for n, t in env.items() if _assignable(t, typ)]
            # call arguments are always plain variables: vars carry the
            # parameter guards, keeping the callee's guard conjecture
            # provable by the type reasoning ACL2 runs automatically
            args.append(("var", rng.choice(candidates) if candidates
                         else default_const(typ, rng)))
        return ("call", callee, tuple(args))
    if chosen == "call-partner":
        return _recursive_call_shape(
            synth, ret, env, depth, budget, lower, partner, driver,
            driver_kind, fn_count, callee=partner)
    if chosen == "recurse":
        return _recursive_call_shape(
            synth, ret, env, depth, budget, lower, partner, driver,
            driver_kind, fn_count, callee="self")
    return ("const", default_const(ret, rng))


def _decrement(synth, name, kind):
    """The structurally-smaller driver argument for a recursive call."""
    if kind == "list":
        if _recursion_shape(synth) == "tree":
            return ("prim", "cddr", (("var", name),))
        return ("prim", "cdr", (("var", name),))
    if _recursion_shape(synth) == "tree":
        return ("prim", "floor", (("var", name), ("const", Fraction(2))))
    return ("prim", "-", (("var", name), ("const", Fraction(1))))


def _recursive_call_shape(synth, ret, env, depth, budget, lower, partner,
                          driver, driver_kind, fn_count, callee):
    """(IF <driver-empty> base (combine <call with smaller driver> more...)).

    The base case makes termination structural; the combining operation
    keeps the recursive result flowing through real arithmetic.
    """
    rng = synth.rng
    args = []
    for name, typ in env.items():
        if name == driver:
            args.append(_decrement(synth, name, driver_kind))
        else:
            args.append(("var", name))
    call = ("call", callee, tuple(args))
    base = ("const", default_const(ret, rng))
    if driver_kind == "list":
        test = ("prim", "endp", (("var", driver),))
    else:
        test = ("prim", "zp", (("var", driver),))
    if isinstance(ret, TInt):
        combiners = [o for o in ("+", "-", "*", "min", "max", "logand",
                                 "logior", "logxor", "ash", "expt")
                     if o in synth.allowed]
        if not combiners:
            return ("if", test, base, call)
        op = rng.choice(combiners)
        if op == "ash":
            other = ("const", Fraction(rng.choice((-8, -3, 1, 2, 3))))
        elif op == "expt":
            other = ("const", Fraction(rng.choice((0, 1, 2, 3))))
        else:
            other = ("var", rng.choice(
                [n for n, t in env.items() if isinstance(t, (TInt, TRat))]
                or [driver])) if op != "expt" else None
        return ("if", test, base, ("prim", op, (call, other)))
    if isinstance(ret, TRat):
        combiners = [o for o in ("+", "-", "*") if o in synth.allowed]
        if not combiners:
            return ("if", test, base, call)
        op = rng.choice(combiners)
        other = ("var", rng.choice(
            [n for n, t in env.items() if isinstance(t, (TRat, TInt))] or [driver]))
        return ("if", test, base, ("prim", op, (call, other)))
    if isinstance(ret, TList):
        if "cons" in synth.allowed:
            if ret.elem == "int":
                pool = [n for n, t in env.items() if isinstance(t, TInt)]
            elif ret.elem == "rat":
                pool = [n for n, t in env.items() if isinstance(t, (TRat, TInt))]
            else:
                pool = [n for n, t in env.items() if isinstance(t, TSym)]
            head = ("var", rng.choice(pool)) if pool else default_const(ret, rng)
            if not pool:
                head = ("prim", "car", (("var", driver),)) if driver_kind == "list" \
                    else ("const", Fraction(0))
            return ("if", test, base, ("prim", "cons", (head, call)))
        if "binary-append" in synth.allowed:
            return ("if", test, base,
                    ("prim", "binary-append", (call, ("const", ()))))
        return ("if", test, base, call)
    # symbols/strings/chars: just return the recursive result
    return ("if", test, base, call)


def _partner_ok(synth):
    return (True,)


def _recursion_ok(synth, ret):
    return synth.structure in ("linear", "tree", "mutual2")


def _recursion_shape(synth):
    return synth.structure if synth.structure in ("linear", "tree") else "linear"


def _assignable(from_type, to_type):
    if isinstance(to_type, TInt):
        return isinstance(from_type, TInt)
    if isinstance(to_type, TRat):
        return isinstance(from_type, (TRat, TInt))
    if isinstance(to_type, TList):
        return isinstance(from_type, TList) and from_type.elem == to_type.elem
    return type(from_type) is type(to_type)


def default_const(ret, rng):
    if isinstance(ret, TInt):
        return Fraction(rng.choice((0, 1, 2, 3, 7, -1, -5)))
    if isinstance(ret, TRat):
        return rng.choice(RAT_GRID)
    if isinstance(ret, TSym):
        return rng.choice(SYM_GRID)
    if isinstance(ret, TStr):
        return String(rng.choice(STR_GRID))
    if isinstance(ret, TChar):
        return CharVal(rng.choice(CHAR_GRID))
    if isinstance(ret, TList):
        items = rng.choice(LIST_GRID[ret.elem])
        return tuple(items)
    raise TypeError(f"no const for {ret!r}")


def fresh_name(env, rng):
    stem = rng.choice("KMPQZ")
    i = 0
    while f"{stem}{i}" in env:
        i += 1
    return f"{stem}{i}"


def synth_test(synth, env, depth=1):
    """A boolean-valued expression drawn from available predicate material."""
    rng = synth.rng
    preds = []
    numeric = [n for n, t in env.items() if isinstance(t, (TInt, TRat))]
    lists = [n for n, t in env.items() if isinstance(t, TList)]
    syms = [n for n, t in env.items() if isinstance(t, TSym)]
    strs = [n for n, t in env.items() if isinstance(t, TStr)]
    chars = [n for n, t in env.items() if isinstance(t, TChar)]
    if len(numeric) >= 2:
        op = rng.choice(("<", ">", "<=", ">=", "="))
        left, right = rng.sample(numeric, 2)
        preds.append(("prim", op, (("var", left), ("var", right))))
    if numeric:
        v = rng.choice(numeric)
        preds.append(("prim", rng.choice(("zp", "natp", "evenp", "oddp", "integerp")),
                      (("var", v),)))
    if lists:
        v = rng.choice(lists)
        preds.append(("prim", rng.choice(("consp", "endp", "atom", "true-listp")),
                      (("var", v),)))
    if syms:
        v = rng.choice(syms)
        preds.append(("prim", "equal",
                      (("var", v), ("const", rng.choice(SYM_GRID)))))
    if strs:
        v = rng.choice(strs)
        preds.append(("prim", "stringp", (("var", v),)))
    if chars:
        v = rng.choice(chars)
        preds.append(("prim", "characterp", (("var", v),)))
    if not preds:
        return ("const", T)
    return rng.choice(preds)


def _prim_production(synth, ret, env):
    """Build a compound production returning ``ret`` from available vars.

    Every option is built so the primitive's guard is provable from the
    function's parameter guard: divisors and shift/exponent counts are
    constants, and dangerous ops are wrapped in guard-establishing IFs.
    Every rng.choice is over a list checked nonempty at the call site.
    """
    rng = synth.rng
    ints = [n for n, t in env.items() if isinstance(t, TInt)]
    rats = [n for n, t in env.items() if isinstance(t, (TRat, TInt))]
    lists = [n for n, t in env.items() if isinstance(t, TList)]
    syms = [n for n, t in env.items() if isinstance(t, TSym)]
    strs = [n for n, t in env.items() if isinstance(t, TStr)]
    chars = [n for n, t in env.items() if isinstance(t, TChar)]
    numeric = ints + rats
    allowed = synth.allowed

    SMALL_DIVISORS = (Fraction(2), Fraction(3), Fraction(-4), Fraction(7))
    SHIFT_COUNTS = (-8, -3, -1, 1, 2, 3, 5, 8)
    EXPONENTS = (0, 1, 2, 3, 5, 8)

    def production():
        if isinstance(ret, TInt):
            options = []
            bin = [o for o in BINARY_INT_OPS if o in allowed]
            if len(ints) >= 2 and bin:
                options.append(("prim", rng.choice(bin),
                                (("var", rng.choice(ints)),
                                 ("var", rng.choice(ints)))))
            if len(numeric) >= 2 and {"min", "max"} & allowed:
                options.append(("prim", rng.choice(("min", "max")),
                                (("var", rng.choice(numeric)),
                                 ("var", rng.choice(numeric)))))
            div = [o for o in DIV_OPS if o in allowed]
            if numeric and div:
                op = rng.choice(div)
                node = ("prim", op,
                        (("var", rng.choice(numeric)),
                         ("const", rng.choice(SMALL_DIVISORS))))
                if op in ("floor", "truncate"):
                    # CL floor/truncate are multiple-valued; arithmetic
                    # context keeps program functions single-valued
                    node = ("prim", "+", (node, ("const", Fraction(1))))
                options.append(node)
            if ints and "ash" in allowed:
                options.append(("prim", "ash",
                                (("var", rng.choice(ints)),
                                 ("const", Fraction(rng.choice(SHIFT_COUNTS))))))
            if ints and "lognot" in allowed:
                options.append(("prim", "lognot", (("var", rng.choice(ints)),)))
            bits = [o for o in ("logand", "logior", "logxor") if o in allowed]
            if len(ints) >= 2 and bits:
                options.append(("prim", rng.choice(bits),
                                (("var", rng.choice(ints)),
                                 ("var", rng.choice(ints)))))
            if ints and "integer-length" in allowed:
                options.append(("prim", "integer-length",
                                (("var", rng.choice(ints)),)))
            if ints and "expt" in allowed:
                options.append(("prim", "expt",
                                (("var", rng.choice(ints)),
                                 ("const", Fraction(rng.choice(EXPONENTS))))))
            if lists and "len" in allowed:
                options.append(("prim", "len", (("var", rng.choice(lists)),)))
            if lists and ints and "nth" in allowed:
                lst = rng.choice(lists)
                k = rng.choice(ints)
                # (and (integerp k) (<= 0 k) (< k (len l))) as nested IFs
                guard_test = (
                    "if",
                    ("prim", "integerp", (("var", k),)),
                    ("if",
                     ("prim", "<=", (("const", Fraction(0)), ("var", k))),
                     ("prim", "<", (("var", k),
                                    ("prim", "len", (("var", lst),)))),
                     ("const", NIL)),
                    ("const", NIL),
                )
                options.append((
                    "if",
                    guard_test,
                    ("prim", "nth", (("var", k), ("var", lst))),
                    ("const", Fraction(0)),
                ))
            if chars and "char-code" in allowed:
                options.append(("prim", "char-code",
                                (("var", rng.choice(chars)),)))
            if len(rats) >= 2 and synth.type_mix in ("mix-int-rat", "rat"):
                # narrowing seam: rational values forced through integer ops
                ops2 = [o for o in ("floor", "truncate", "mod")
                        if o in allowed]
                if ops2:
                    a, b = rng.sample(rats, 2)
                    op = rng.choice(ops2)
                    node = ("prim", op,
                            (("prim", "+",
                              (("var", a), ("var", b))),
                             ("const", Fraction(2))))
                    if op in ("floor", "truncate"):
                        node = ("prim", "+", (node, ("const", Fraction(1))))
                    options.append(node)
            if not options:
                return None
            return rng.choice(options)
        if isinstance(ret, TRat):
            options = []
            arith = [o for o in ("+", "-", "*") if o in allowed]
            if len(rats) >= 2 and arith:
                options.append(("prim", rng.choice(arith),
                                (("var", rng.choice(rats)),
                                 ("var", rng.choice(rats)))))
            if len(rats) >= 2 and {"min", "max"} & allowed:
                options.append(("prim", rng.choice(("min", "max")),
                                (("var", rng.choice(rats)),
                                 ("var", rng.choice(rats)))))
            if rats and "/" in allowed:
                options.append(("prim", "/",
                                (("var", rng.choice(rats)),
                                 ("const", rng.choice(SMALL_DIVISORS)))))
            if not options:
                return None
            return rng.choice(options)
        if isinstance(ret, TList):
            options = []
            if lists:
                lst = rng.choice(lists)
                if ret.elem == "int" and ints and "cons" in allowed:
                    options.append(("prim", "cons",
                                    (("var", rng.choice(ints)), ("var", lst))))
                if ret.elem == "sym" and syms and "cons" in allowed:
                    options.append(("prim", "cons",
                                    (("var", rng.choice(syms)), ("var", lst))))
                if ret.elem == "rat" and rats and "cons" in allowed:
                    options.append(("prim", "cons",
                                    (("var", rng.choice(rats)), ("var", lst))))
                if len(lists) >= 2 and "binary-append" in allowed:
                    options.append(("prim", "binary-append",
                                    (("var", rng.choice(lists)),
                                     ("var", rng.choice(lists)))))
                if "cdr" in allowed:
                    options.append(("prim", "cdr", (("var", lst),)))
                if "cddr" in allowed:
                    options.append(("prim", "cddr", (("var", lst),)))
                if ret.elem == "int" and ints and "cons" in allowed:
                    # interleave: fresh head cell appended before the list
                    head = ("prim", "cons",
                            (("var", rng.choice(ints)), ("const", ())))
                    options.append(("prim", "binary-append",
                                    (head, ("var", lst))))
            if not options:
                return None
            return rng.choice(options)
        if isinstance(ret, TSym):
            options = []
            if syms:
                options.append(("var", rng.choice(syms)))
            if numeric:
                preds = [o for o in ("evenp", "zp", "natp") if o in allowed]
                if preds or True:  # these predicates are total (nil guard)
                    options.append(("if",
                                    ("prim", rng.choice(("evenp", "zp", "natp")),
                                     (("var", rng.choice(numeric)),)),
                                    ("const", Symbol("A")),
                                    ("const", Symbol("B"))))
            if not options:
                return None
            return rng.choice(options)
        if isinstance(ret, TStr):
            options = []
            if strs:
                options.append(("var", rng.choice(strs)))
            if numeric:
                options.append(("if",
                                ("prim", "evenp",
                                 (("var", rng.choice(numeric)),)),
                                ("const", String("even")),
                                ("const", String("odd"))))
            if not options:
                return None
            return rng.choice(options)
        if isinstance(ret, TChar):
            options = []
            if chars:
                options.append(("var", rng.choice(chars)))
            if chars and "code-char" in allowed:
                c = rng.choice(chars)
                options.append(("prim", "code-char",
                                (("prim", "mod",
                                  (("prim", "+",
                                    (("prim", "char-code", (("var", c),)),
                                     ("const", Fraction(1)))),
                                   ("const", Fraction(256)))),)))
            if not options:
                return None
            return rng.choice(options)
        return None

    def wrapped(depth, budget, lower, partner, driver, driver_kind, fn_count):
        prod = production()
        if prod is None:
            return ("const", default_const(ret, synth.rng))
        return prod

    return wrapped


def _is_bounded_positive(typ):
    return isinstance(typ, TInt) and typ.lo is not None and typ.lo >= 1


# ---------------------------------------------------------------------------
# oracle
# ---------------------------------------------------------------------------

def _v_int(value):
    if isinstance(value, Fraction) and value.denominator == 1:
        return int(value)
    raise AuditError(f"not an integer: {value!r}")


def _v_num(value):
    if isinstance(value, Fraction):
        return value
    raise AuditError(f"not a number: {value!r}")


def _v_bool(value):
    return value != NIL


def _bool(value):
    return T if value else NIL


def _v_list(value):
    if isinstance(value, tuple):
        return value
    raise AuditError(f"not a proper list: {value!r}")


MAX_ORACLE_DEPTH = 20000


def eval_program(program, fn_index, args, _depth=0):
    """Exact oracle evaluation of program function at ``args`` (tuple)."""
    if _depth > MAX_ORACLE_DEPTH:
        raise AuditError("oracle recursion limit exceeded")
    fn = program.fns[fn_index]
    env = {name: value for (name, _), value in zip(fn.params, args)}
    return _eval(program, fn.body, env, _depth, fn_index)


def _eval(program, ast, env, depth, fn_index):
    op = ast[0]
    if op == "var":
        return env[ast[1]]
    if op == "const":
        return ast[1]
    if op == "if":
        test = _eval(program, ast[1], env, depth, fn_index)
        branch = ast[2] if test != NIL else ast[3]
        return _eval(program, branch, env, depth, fn_index)
    if op == "let":
        inner = dict(env)
        for name, val_ast in ast[1]:
            inner[name] = _eval(program, val_ast, env, depth, fn_index)
        return _eval(program, ast[2], inner, depth, fn_index)
    if op == "call":
        callee = ast[1]
        if callee == "self":
            callee = fn_index
        args = tuple(_eval(program, a, env, depth, fn_index) for a in ast[2])
        return eval_program(program, callee, args, depth + 1)
    if op == "prim":
        return _eval_prim(program, ast[1], ast[2], env, depth, fn_index)
    raise AuditError(f"cannot evaluate {op!r}")


def _eval_prim(program, op, arg_asts, env, depth, fn_index=0):
    if op == "cons":
        head = _eval(program, arg_asts[0], env, depth, fn_index)
        tail = _eval(program, arg_asts[1], env, depth, fn_index)
        return (head,) + tuple(tail)
    if op in ("car", "cdr", "cddr"):
        value = _eval(program, arg_asts[0], env, depth, fn_index)
        value = _v_list(value)
        if op == "car":
            return value[0] if value else NIL
        if op == "cdr":
            return value[1:] if value else ()
        return value[2:] if len(value) >= 2 else ()
    if op == "len":
        return Fraction(len(_v_list(_eval(program, arg_asts[0], env, depth, fn_index))))
    if op == "nth":
        k = _v_int(_eval(program, arg_asts[0], env, depth, fn_index))
        lst = _v_list(_eval(program, arg_asts[1], env, depth, fn_index))
        return lst[k] if 0 <= k < len(lst) else NIL
    if op == "binary-append":
        left = _v_list(_eval(program, arg_asts[0], env, depth, fn_index))
        right = _v_list(_eval(program, arg_asts[1], env, depth, fn_index))
        return tuple(left) + tuple(right)
    if op == "endp":
        return _bool(not _v_list(_eval(program, arg_asts[0], env, depth, fn_index)))
    if op == "true-listp":
        value = _eval(program, arg_asts[0], env, depth, fn_index)
        return _bool(isinstance(value, tuple))
    if op == "consp":
        value = _eval(program, arg_asts[0], env, depth, fn_index)
        return _bool(isinstance(value, tuple))
    if op == "atom":
        value = _eval(program, arg_asts[0], env, depth, fn_index)
        return _bool(not isinstance(value, tuple))
    if op == "equal":
        left = _eval(program, arg_asts[0], env, depth, fn_index)
        right = _eval(program, arg_asts[1], env, depth, fn_index)
        return _bool(_structural_eq(left, right))
    if op == "char-code":
        value = _eval(program, arg_asts[0], env, depth, fn_index)
        if not isinstance(value, CharVal):
            raise AuditError("char-code expects a character")
        return Fraction(ord(value.ch))
    if op == "code-char":
        code = _v_int(_eval(program, arg_asts[0], env, depth, fn_index))
        if 0 <= code < 256:
            return CharVal(chr(code))
        return NIL
    if op in ("zp", "natp", "integerp", "rationalp", "acl2-numberp", "evenp",
              "oddp", "stringp", "symbolp", "characterp", "booleanp"):
        value = _eval(program, arg_asts[0], env, depth, fn_index)
        return _bool(_type_pred(op, value))
    if op in ("<", "<=", ">", ">=", "="):
        values = [_v_num(_eval(program, a, env, depth, fn_index)) for a in arg_asts]
        if op == "<":
            return _bool(values[0] < values[1])
        if op == "<=":
            return _bool(values[0] <= values[1])
        if op == ">":
            return _bool(values[0] > values[1])
        if op == ">=":
            return _bool(values[0] >= values[1])
        return _bool(values[0] == values[1])
    values = [_eval(program, a, env, depth, fn_index) for a in arg_asts]
    if op in ("+", "-", "*", "min", "max"):
        nums = [_v_num(v) for v in values]
        if op == "+":
            return nums[0] + nums[1]
        if op == "-":
            return -nums[0] if len(nums) == 1 else nums[0] - nums[1]
        if op == "*":
            return nums[0] * nums[1]
        if op == "min":
            return min(nums)
        return max(nums)
    if op in ("floor", "mod", "truncate", "rem", "/"):
        x, y = _v_num(values[0]), _v_num(values[1])
        if op == "/":
            if y == 0:
                return ZERO  # ACL2 logic: (/ x 0) = 0
            return x / y
        if y == 0:
            if op == "mod":
                return x
            if op == "rem":
                return x
            return ZERO  # floor/truncate of /0: ACL2 gives 0? -- guarded, unreachable
        if op == "floor":
            return Fraction(_floor_div(x, y))
        if op == "truncate":
            return Fraction(_trunc_div(x, y))
        if op == "mod":
            q = _floor_div(x, y)
            return x - y * q
        q = _trunc_div(x, y)
        return x - y * q
    if op == "expt":
        base = _v_num(values[0])
        exp = _v_int(values[1])
        if exp < 0:
            raise AuditError("negative expt exponent")
        result = Fraction(1)
        factor, count = base, exp
        while count:
            if count & 1:
                result *= factor
            factor *= factor
            count >>= 1
        return result
    if op == "ash":
        i = _v_int(values[0])
        k = _v_int(values[1])
        if k >= 0:
            return Fraction(i << k)
        return Fraction(i >> (-k))  # arithmetic shift == floor division
    if op == "lognot":
        return Fraction(~_v_int(values[0]))
    if op in ("logand", "logior", "logxor"):
        a, b = _v_int(values[0]), _v_int(values[1])
        if op == "logand":
            return Fraction(a & b)
        if op == "logior":
            return Fraction(a | b)
        return Fraction(a ^ b)
    if op == "logbitp":
        k = _v_int(values[0])
        n = _v_int(values[1])
        if k < 0:
            raise AuditError("negative logbitp index")
        return _bool((n >> k) & 1 == 1)
    if op == "integer-length":
        return Fraction(_v_int(values[0]).bit_length() if False else _int_length(_v_int(values[0])))
    raise AuditError(f"oracle lacks {op!r}")


def _int_length(i):
    if i == 0:
        return 0
    if i > 0:
        return i.bit_length()
    return (-i - 1).bit_length()


def _floor_div(x, y):
    q = x / y
    return Fraction(q.numerator // q.denominator)


def _trunc_div(x, y):
    q = x / y
    n = abs(q.numerator) // q.denominator
    if (x < 0) != (y < 0):
        n = -n
    return Fraction(n)


def _structural_eq(left, right):
    if isinstance(left, CharVal) or isinstance(right, CharVal):
        return left == right
    if isinstance(left, tuple) and isinstance(right, tuple):
        return (len(left) == len(right)
                and all(_structural_eq(a, b) for a, b in zip(left, right)))
    if isinstance(left, (tuple, list)) or isinstance(right, (tuple, list)):
        return False
    return left == right


def _type_pred(op, value):
    if op == "zp":
        return (not isinstance(value, Fraction) or value.denominator != 1
                or value < 0 or value == 0)
    if op == "natp":
        return isinstance(value, Fraction) and value.denominator == 1 and value >= 0
    if op == "integerp":
        return isinstance(value, Fraction) and value.denominator == 1
    if op == "rationalp":
        return isinstance(value, Fraction)
    if op == "acl2-numberp":
        return isinstance(value, Fraction)
    if op == "evenp":
        return isinstance(value, Fraction) and value.denominator == 1 and value % 2 == 0
    if op == "oddp":
        return isinstance(value, Fraction) and value.denominator == 1 and value % 2 != 0
    if op == "stringp":
        return isinstance(value, String)
    if op == "symbolp":
        return isinstance(value, Symbol) or value in (NIL, T)
    if op == "characterp":
        return isinstance(value, CharVal)
    if op == "booleanp":
        return value in (NIL, T)
    raise AuditError(f"unknown pred {op!r}")


# ---------------------------------------------------------------------------
# rendering
# ---------------------------------------------------------------------------

def guard_expr(params, fn, program):
    """ACL2 :guard conjunction for a function's formals."""
    parts = []
    for name, typ in params:
        if isinstance(typ, TInt):
            parts.append(f"(INTEGERP {name})")
            if typ.lo is not None:
                parts.append(f"(<= {typ.lo} {name})")
            if typ.hi is not None:
                parts.append(f"(<= {name} {typ.hi})")
        elif isinstance(typ, TRat):
            parts.append(f"(RATIONALP {name})")
        elif isinstance(typ, TList):
            parts.append(f"(TRUE-LISTP {name})")
        elif isinstance(typ, TSym):
            parts.append(f"(SYMBOLP {name})")
        elif isinstance(typ, TStr):
            parts.append(f"(STRINGP {name})")
        elif isinstance(typ, TChar):
            parts.append(f"(CHARACTERP {name})")
    if not parts:
        return "T"
    if len(parts) == 1:
        return parts[0]
    return "(AND " + " ".join(parts) + ")"


def render_ast(ast, cl=False, fn_index=None, prefix=""):
    op = ast[0]
    if op == "var":
        return ast[1].upper()
    if op == "const":
        return render_const(ast[1])
    if op == "if":
        return f"(IF {render_ast(ast[1], cl, fn_index, prefix)} {render_ast(ast[2], cl, fn_index, prefix)} {render_ast(ast[3], cl, fn_index, prefix)})"
    if op == "let":
        bindings = " ".join(f"({n.upper()} {render_ast(v, cl, fn_index, prefix)})" for n, v in ast[1])
        return f"(LET ({bindings}) {render_ast(ast[2], cl, fn_index, prefix)})"
    if op == "call":
        callee = ast[1]
        if callee == "self":
            if fn_index is None:
                raise ValueError("self-reference rendered outside a function")
            name = prefix + program_fn_name(fn_index)
        else:
            name = prefix + program_fn_name(callee)
        args = " ".join(render_ast(a, cl, fn_index, prefix) for a in ast[2])
        return f"({name} {args})"
    if op == "prim":
        sub = " ".join(render_ast(a, cl, fn_index, prefix) for a in ast[2])
        name = CL_NAMES[ast[1]] if cl else ACL2_NAMES[ast[1]]
        return f"({name} {sub})".rstrip()
    raise ValueError(f"cannot render {op!r}")


def program_fn_name(index):
    return f"PROG-F{index}"


def render_acl2(program, prefix=""):
    """ACL2 event text: defuns (+ verify-guards when planned)."""
    def one_defun(fn):
        name = prefix + program_fn_name(fn.index)
        params = " ".join(p for p, _ in fn.params) or ""
        body = render_ast(fn.body, fn_index=fn.index, prefix=prefix)
        if fn.guards:
            guard = guard_expr(fn.params, fn, program)
            return (f"(DEFUN {name} ({params})\n"
                    f"  (DECLARE (XARGS :GUARD {guard} :VERIFY-GUARDS NIL))\n"
                    f"  {body})")
        return f"(DEFUN {name} ({params})\n  {body})"

    defuns = [one_defun(fn) for fn in program.fns]
    text = []
    if program.axes["structure"] == "mutual2":
        text.append("(MUTUAL-RECURSION\n  " + "\n  ".join(defuns) + ")\n")
    else:
        text.extend(d + "\n" for d in defuns)
    if program.axes["guards"] == "verified":
        for fn in program.fns:
            text.append(f"(VERIFY-GUARDS {prefix}{program_fn_name(fn.index)})\n")
    return "\n".join(text)


def program_fn_names(program, prefix=""):
    return [prefix + program_fn_name(fn.index) for fn in program.fns]


CL_TYPE_NAMES = {
    TInt: lambda t: f"(INTEGER {t.lo if t.lo is not None else '*'} {t.hi if t.hi is not None else '*'})"
    if (t.lo is not None or t.hi is not None) else "INTEGER",
    TRat: lambda t: "RATIONAL",
    TList: lambda t: "LIST",
    TSym: lambda t: "SYMBOL",
    TStr: lambda t: "STRING",
    TChar: lambda t: "CHARACTER",
}


def cl_type_name(typ):
    return CL_TYPE_NAMES[type(typ)](typ)


def cl_ftype(fn):
    arg_types = " ".join(cl_type_name(t) for _, t in fn.params)
    return f"(FUNCTION ({arg_types or 'T'}) {cl_type_name(fn.ret)})"


def render_cl(program, prefix="", inline=False):
    """Standalone Common Lisp: defuns (optionally inline) + ftype declaims."""
    lines = []
    decls = []
    for fn in program.fns:
        name = prefix + program_fn_name(fn.index)
        decls.append(f"(DECLAIM (FTYPE {cl_ftype(fn)} {name}))")
    lines.extend(decls)
    if inline:
        names = " ".join(prefix + program_fn_name(fn.index) for fn in program.fns)
        lines.append(f"(DECLAIM (INLINE {names}))")
    for fn in program.fns:
        name = prefix + program_fn_name(fn.index)
        params = " ".join(p for p, _ in fn.params) or ""
        decl = []
        for p, t in fn.params:
            decl.append(f"(TYPE {cl_type_name(t)} {p})")
        body = render_ast(fn.body, cl=True, fn_index=fn.index, prefix=prefix)
        lines.append(
            f"(DEFUN {name} ({params})\n"
            f"  (DECLARE {' '.join(decl)})\n"
            f"  {body})\n"
        )
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# call-term battery
# ---------------------------------------------------------------------------

def _contains_call(ast, targets):
    if not isinstance(ast, tuple):
        return False
    if (len(ast) == 3 and ast[0] == "call"
            and not isinstance(ast[1], tuple)):
        return ast[1] in targets
    return any(_contains_call(x, targets) for x in ast)


def is_recursive(program):
    """True when any function body calls itself or its mutual partner."""
    for fn in program.fns:
        if _contains_call(fn.body, ("self", fn.index)):
            return True
        if program.axes["structure"] == "mutual2" and _contains_call(
                fn.body, (1 - fn.index,)):
            return True
    return False


SMALL_NAT_GRID = (Fraction(0), Fraction(1), Fraction(2), Fraction(3),
                  Fraction(5), Fraction(8))


def term_battery(program, rng, ok_per_fn=4, violating_per_fn=1):
    """Call terms with oracle expectations: {id, fn, args, class, oracle}.

    Recursive programs get small driver arguments so evaluation depth is
    bounded; non-recursive programs keep the full boundary grid.
    """
    recursive = is_recursive(program)
    driver_name = None
    if recursive:
        for name, typ in program.fns[0].params:
            if isinstance(typ, TList) or (isinstance(typ, TInt) and typ.lo == 0):
                driver_name = name
                break

    def grid_for(name, typ, count):
        if recursive and name == driver_name:
            if isinstance(typ, TList):
                pool = [tuple(Fraction(i) for i in items)
                        for items in LIST_GRID[typ.elem] if len(items) <= 8]
                return pool[:count]
            return list(SMALL_NAT_GRID)[:count]
        return grid_values(typ, rng, count)

    terms = []
    for fn in program.fns:
        grids = [grid_for(name, typ, ok_per_fn + 2)
                 for name, typ in fn.params]
        seen = set()
        made = 0
        for combo in zip(*grids):
            if combo in seen:
                continue
            seen.add(combo)
            try:
                value = eval_program(program, fn.index, combo)
                oracle = render_value_universe(value)
            except AuditError:
                continue
            terms.append({
                "fn": fn.index, "args": combo, "class": "ok", "oracle": oracle,
            })
            made += 1
            if made >= ok_per_fn:
                break
        for v in violating_values(fn.params[0][1], rng, violating_per_fn):
            combo = (v,) + tuple(grid_for(name, typ, 1)[0]
                                 for name, typ in fn.params[1:])
            try:
                value = eval_program(program, fn.index, combo)
                oracle = render_value_universe(value)
            except AuditError:
                oracle = None
            terms.append({
                "fn": fn.index, "args": combo, "class": "violating",
                "oracle": oracle,
            })
    for i, term in enumerate(terms):
        term["id"] = f"{program.prog_id}-f{term['fn']}-{i:02d}"
    return terms


def render_value_universe(value):
    if isinstance(value, tuple):
        if not value:
            return "NIL"
        return "(" + " ".join(render_value_universe(v) for v in value) + ")"
    if isinstance(value, CharVal):
        return render_char(value)
    if isinstance(value, int) and not isinstance(value, bool):
        # violating arguments can flow plain ints through variable bodies
        return render_value(Fraction(value))
    text = render_value(value)
    return text


def args_bindings(args, params):
    return [(name, value) for (name, _), value in zip(params, args)]


# ---------------------------------------------------------------------------
# corpus enumeration
# ---------------------------------------------------------------------------

def enumerate_programs(seed=0, limit=None, structures=STRUCTURES, types=TYPES,
                       guards=GUARD_MODES, flavors=FLAVORS):
    """Deterministic sweep over the axis product, one program per cell."""
    programs = []
    for structure in structures:
        for type_mix in types:
            for guard_mode in guards:
                for flavor in flavors:
                    digest = hashlib.sha256(
                        f"{seed}|{structure}|{type_mix}|{guard_mode}|{flavor}"
                        .encode()
                    ).digest()
                    rng = random.Random(int.from_bytes(digest[:8], "big"))
                    pid = f"{structure}-{type_mix}-{guard_mode}-{flavor}"
                    programs.append(
                        make_program(pid, rng, structure, type_mix, guard_mode, flavor)
                    )
    if limit is not None:
        programs = programs[:limit]
    return programs


def coverage_table(programs):
    from collections import Counter
    table = {}
    for axis in ("structure", "types", "guards", "flavor", "driver"):
        table[axis] = dict(Counter(p.axes[axis] for p in programs))
    return table


# ---------------------------------------------------------------------------
# self-check
# ---------------------------------------------------------------------------

def _self_check():
    rng = random.Random(9)
    programs = enumerate_programs(seed=0, limit=40)
    assert len(programs) == 40
    for program in programs:
        battery = term_battery(program, random.Random(1), ok_per_fn=3,
                               violating_per_fn=0)
        assert battery, f"empty battery for {program.prog_id}"
        for term in battery:
            value = eval_program(program, term["fn"], term["args"])
            assert render_value_universe(value) == term["oracle"]
    # structural spot-render
    shown = set()
    for program in programs:
        s = program.axes["structure"]
        if s not in shown:
            shown.add(s)
            print(f"=== {program.prog_id}")
            print(render_acl2(program))
    print("coverage:", coverage_table(programs))
    print("self-check ok")


if __name__ == "__main__":
    _self_check()
