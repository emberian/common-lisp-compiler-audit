#!/usr/bin/env python3
"""ACL2-specific forms and an independent, exact semantic model."""

from dataclasses import dataclass
from fractions import Fraction


class AuditError(ValueError):
    pass


class NonExecError(AuditError):
    pass


@dataclass(frozen=True)
class Symbol:
    name: str


@dataclass(frozen=True)
class String:
    value: str


@dataclass(frozen=True)
class ComplexRational:
    real: Fraction
    imag: Fraction


@dataclass(frozen=True)
class ListValue:
    items: tuple
    tail: object


NIL = Symbol("NIL")
T = Symbol("T")
ZERO = Fraction(0)
ONE = Fraction(1)


def N(value):
    if isinstance(value, (Fraction, ComplexRational)):
        return value
    if isinstance(value, int) and not isinstance(value, bool):
        return Fraction(value)
    raise TypeError(f"not an exact ACL2 number: {value!r}")


def C(real, imag):
    return ComplexRational(N(real), N(imag))


def L(*items, tail=NIL):
    items = tuple(items)
    if not items and tail == NIL:
        return NIL
    return ListValue(items, tail)


def S(value):
    return String(value)


def q(value):
    return ("quote", value)


def ec_call(form):
    return ("with-guard-checking", NIL, ("ec-call", form))


def without_guards(form):
    return ("with-guard-checking", NIL, form)


def _integer(value):
    return isinstance(value, Fraction) and value.denominator == 1


def _real(value):
    return isinstance(value, Fraction)


def _number(value):
    return isinstance(value, (Fraction, ComplexRational))


def _fix(value):
    return value if _number(value) else ZERO


def _nfix(value):
    return value if _integer(value) and value >= 0 else ZERO


def _ifix(value):
    return value if _integer(value) else ZERO


def _parts(value):
    value = _fix(value)
    if isinstance(value, ComplexRational):
        return value.real, value.imag
    return value, ZERO


def _mul(left, right):
    if not isinstance(left, ComplexRational) and not isinstance(right, ComplexRational):
        return left * right
    a, b = _parts(left)
    c, d = _parts(right)
    return C(a * c - b * d, a * d + b * c)


def _add(left, right):
    if not isinstance(left, ComplexRational) and not isinstance(right, ComplexRational):
        return left + right
    a, b = _parts(left)
    c, d = _parts(right)
    return C(a + c, b + d)


def _negate(value):
    if isinstance(value, ComplexRational):
        return C(-value.real, -value.imag)
    return -value


def _reciprocal(value):
    if isinstance(value, ComplexRational):
        denominator = value.real * value.real + value.imag * value.imag
        if denominator == 0:
            raise AuditError("zero complex reciprocal")
        return C(value.real / denominator, -value.imag / denominator)
    if value == 0:
        raise AuditError("zero reciprocal")
    return 1 / value


def _power(base, exponent):
    exponent = int(exponent)
    if exponent == 0:
        return ONE
    if exponent < 0:
        if base == 0:
            return ZERO
        return _power(_reciprocal(base), -exponent)
    result = ONE
    factor = base
    count = exponent
    while count:
        if count & 1:
            result = _mul(result, factor)
        factor = _mul(factor, factor)
        count >>= 1
    return result


def _false(value):
    return value == NIL


def eval_term(term, mode="logic"):
    if mode not in ("logic", "direct", "exec"):
        raise ValueError(f"unknown evaluation mode {mode!r}")
    if _number(term) or isinstance(term, String) or term in (NIL, T):
        return term
    if isinstance(term, Symbol):
        raise AuditError(f"unbound symbol {term.name}")
    if not isinstance(term, tuple) or not term:
        raise AuditError(f"cannot evaluate {term!r}")

    op = term[0]
    args = term[1:]
    if op == "quote":
        return args[0]
    if op == "if":
        test, yes, no = args
        return eval_term(no if _false(eval_term(test, mode)) else yes, mode)
    if op == "ec-call":
        return eval_term(args[0], mode)
    if op == "with-guard-checking":
        return eval_term(args[1], mode)
    if op == "mbe":
        choices = dict(zip(args[0::2], args[1::2]))
        return eval_term(choices[":EXEC" if mode == "exec" else ":LOGIC"], mode)
    if op == "non-exec":
        if mode in ("direct", "exec"):
            raise NonExecError("non-exec reached during execution")
        return eval_term(args[0], mode)
    if op == "return-last":
        eval_term(args[1], mode)
        return eval_term(args[2], mode)
    if op == "prog2$":
        eval_term(args[0], mode)
        return eval_term(args[1], mode)

    values = [eval_term(arg, mode) for arg in args]
    if op in ("zp", "zip"):
        value = values[0]
        if not _integer(value):
            answer = True
        elif op == "zp":
            answer = value <= 0
        else:
            answer = value == 0
        return T if answer else NIL
    if op == "nfix":
        return _nfix(values[0])
    if op == "ifix":
        return _ifix(values[0])
    if op == "fix":
        return _fix(values[0])
    if op in ("=", "/="):
        left, right = values
        if _number(left) and _number(right):
            answer = _parts(left) == _parts(right)
        elif _number(left) or _number(right):
            answer = False
        else:
            answer = left == right
        if op == "/=":
            answer = not answer
        return T if answer else NIL
    if op == "car":
        value = values[0]
        return value.items[0] if isinstance(value, ListValue) else NIL
    if op == "cdr":
        value = values[0]
        if not isinstance(value, ListValue):
            return NIL
        if len(value.items) == 1:
            return value.tail
        return L(*value.items[1:], tail=value.tail)
    if op == "len":
        value = values[0]
        if isinstance(value, ListValue):
            return N(len(value.items))
        return ZERO
    if op in ("mod", "rem"):
        left, right = values
        if not _real(left) or not _real(right):
            raise AuditError(f"{op} model expects reals")
        if right == 0:
            return left
        quotient = left / right
        if op == "mod":
            quotient = N(quotient.numerator // quotient.denominator)
        else:
            quotient = N(abs(quotient.numerator) // abs(quotient.denominator))
            if (left < 0) != (right < 0):
                quotient = -quotient
        return left - right * quotient
    if op == "nonnegative-integer-quotient":
        left, right = _nfix(values[0]), _nfix(values[1])
        if right == 0:
            return ZERO
        return N(int(left) // int(right))
    if op == "expt":
        base, exponent = values
        if not _number(base) or not _integer(exponent):
            raise AuditError("expt model expects a number and an integer")
        return _power(base, exponent)
    if op in ("loghead", "logtail"):
        width, value = int(_nfix(values[0])), int(_ifix(values[1]))
        modulus = 1 << width
        return N(value % modulus if op == "loghead" else value // modulus)
    if op == "<":
        left, right = _parts(values[0]), _parts(values[1])
        return T if left < right else NIL
    if op in ("+", "-", "*"):
        if not all(_number(value) for value in values):
            raise AuditError(f"{op} model expects numbers")
        if op == "+":
            result = ZERO
            for value in values:
                result = _add(result, value)
            return result
        if op == "*":
            result = ONE
            for value in values:
                result = _mul(result, value)
            return result
        if len(values) == 1:
            return _negate(values[0])
        result = values[0]
        for value in values[1:]:
            result = _add(result, _negate(value))
        return result
    raise AuditError(f"unsupported operator {op!r}")


def render(term):
    if isinstance(term, tuple):
        if term[0] == "quote":
            value = term[1]
            if value == NIL:
                return "NIL"
            return "'" + render(value)
        return "(" + " ".join(render(item) for item in term) + ")"
    if isinstance(term, str):
        return term
    if isinstance(term, Fraction):
        if term.denominator == 1:
            return str(term.numerator)
        return f"{term.numerator}/{term.denominator}"
    if isinstance(term, ComplexRational):
        return f"#C({render(term.real)} {render(term.imag)})"
    if isinstance(term, Symbol):
        return term.name
    if isinstance(term, String):
        escaped = term.value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    if isinstance(term, ListValue):
        contents = [render(item) for item in term.items]
        if term.tail != NIL:
            contents.extend((".", render(term.tail)))
        return "(" + " ".join(contents) + ")"
    raise TypeError(f"cannot render {term!r}")


def expected_results(form):
    logical = render(eval_term(form, "logic"))
    try:
        direct = render(eval_term(form, "direct"))
    except NonExecError:
        direct = ":ERROR"
    try:
        compiled = render(eval_term(form, "exec"))
    except NonExecError:
        compiled = ":ERROR"
    return logical, direct, compiled


LOCAL_BITOPS = """(defun loghead (n i)
  (declare (xargs :guard (and (natp n) (integerp i))))
  (mod (ifix i) (expt 2 (nfix n))))

(defun logtail (n i)
  (declare (xargs :guard (and (natp n) (integerp i))))
  (ifix (floor (ifix i) (expt 2 (nfix n)))))

(verify-guards loghead)
(verify-guards logtail)
"""


def make_corpus():
    tests = []

    def add(family, form, host=None):
        logical, direct, compiled = expected_results(form)
        tests.append({
            "id": f"{family}-{len(tests):04d}",
            "family": family,
            "ast": form,
            "form": render(form),
            "logical": logical,
            "expected_direct": direct,
            "expected_compiled": compiled,
            "host_form": render(host) if host is not None else None,
        })

    fix_values = (
        N(-2), N(0), N(3), N(-1) / 2, N(2) / 3,
        C(1, 2), NIL, Symbol("A"), S("text"),
    )
    for op in ("zp", "zip"):
        for value in fix_values:
            form = (op, q(value))
            guarded = _integer(value) and (op == "zip" or value >= 0)
            add(op, form if guarded else ec_call(form))
    for op in ("nfix", "ifix", "fix"):
        for value in fix_values:
            add(op, (op, q(value)))

    equality_pairs = (
        (N(1), N(1)), (N(1) / 2, N(2) / 4), (N(-2), N(2)),
        (C(1, 2), C(1, 2)), (C(1, 2), C(1, 3)),
        (C(1, 2), N(1)), (Symbol("A"), Symbol("A")),
        (Symbol("A"), N(0)), (NIL, N(1)), (S("x"), N(0)),
    )
    for op in ("=", "/="):
        for left, right in equality_pairs:
            form = (op, q(left), q(right))
            guarded = _number(left) and _number(right)
            host = form if guarded or op == "=" else None
            add(op, form if guarded else ec_call(form), host=host)

    sequence_values = (
        NIL, L(N(1), N(2), N(3)), L(N(1), N(2), tail=N(3)),
        N(7), Symbol("A"), S("atom"),
    )
    for op in ("car", "cdr"):
        for value in sequence_values:
            form = (op, q(value))
            guarded = value == NIL or isinstance(value, ListValue)
            add(op, form if guarded else ec_call(form), host=form)

    len_values = (
        NIL, L(N(1)), L(N(1), N(2), N(3)),
        L(N(1), tail=N(2)), L(N(1), N(2), tail=N(3)),
        N(9), Symbol("A"), S(""), S("abc"), S('a"b\\c'),
    )
    for value in len_values:
        form = ("len", q(value))
        add("len", form, host=("length", q(value)))

    division_values = (N(-7), N(-5) / 2, N(0), N(5) / 2, N(7))
    divisors = (N(-3), N(-2) / 3, N(2) / 3, N(3), N(0))
    for op in ("mod", "rem"):
        for left in division_values:
            for right in divisors:
                form = (op, q(left), q(right))
                add(op, form if right != 0 else ec_call(form), host=form)

    quotient_cases = (
        (0, 1), (1, 2), (7, 3), (8, 3), ((1 << 70) + 9, 7),
        (7, 0), (-7, 2), (7, -2), (N(1) / 2, 2),
    )
    for left, right in quotient_cases:
        left, right = N(left), N(right)
        form = ("nonnegative-integer-quotient", q(left), q(right))
        guarded = _integer(left) and left >= 0 and _integer(right) and right > 0
        add("nonnegative-integer-quotient", form if guarded else ec_call(form))

    exponent_cases = (
        (-2, -3), (-2, 3), (-1, -4), (-1, 5),
        (N(-1) / 2, -2), (N(-1) / 2, 3),
        (0, 0), (0, 3), (0, -1), (N(1) / 2, -3),
        (2, 0), (2, 10), (C(1, 1), 2), (C(1, 1), -2),
        (C(N(1) / 2, N(-1) / 3), 3), (C(2, -1), -1),
    )
    for base, exponent in exponent_cases:
        base, exponent = N(base), N(exponent)
        form = ("expt", q(base), q(exponent))
        guarded = not (base == 0 and exponent < 0)
        add("expt", form if guarded else ec_call(form), host=form)

    bit_values = (N(-65), N(-64), N(-17), N(-1), N(0), N(1), N(17), N(63), N(64))
    widths = (N(0), N(1), N(3), N(6), N(7), N(64))
    for op in ("loghead", "logtail"):
        for width in widths:
            for value in bit_values:
                form = (op, q(width), q(value))
                host_op = "mod" if op == "loghead" else "floor"
                host = (host_op, q(value), ("expt", q(N(2)), q(width)))
                add(op, form, host=host)
        for width, value in ((N(-1), N(17)), (N(1) / 2, N(17)), (N(2), Symbol("A"))):
            form = (op, q(width), q(value))
            add(op, ec_call(form))

    order_values = (
        N(-1), N(0), N(1) / 2, N(2), C(-1, 1), C(0, -1),
        C(0, 1), C(N(1) / 2, -2), C(N(1) / 2, -1),
        C(N(1) / 2, 0), C(N(1) / 2, 1), C(2, -100),
    )
    order_pairs = []
    for index, left in enumerate(order_values):
        order_pairs.append((left, order_values[(index + 1) % len(order_values)]))
    order_pairs.extend(((C(1, 2), C(1, 3)), (C(1, 3), C(1, 2)),
                        (C(1, 2), N(2)), (N(1), N(2)), (N(2), N(2))))
    for left, right in order_pairs:
        form = ("<", q(left), q(right))
        guarded = _real(left) and _real(right)
        add("lexicographic-<", form if guarded else ec_call(form), host=form)

    add("return-last", ("return-last", q(Symbol("PROGN")), ("nfix", q(N(-3))), ("len", q(S("abcd")))))
    add("return-last", ("return-last", q(Symbol("PROGN")), ("zip", q(N(0))),
                        ("mbe", ":LOGIC", ("ifix", q(N(9))), ":EXEC", ("nfix", q(N(9))))))
    add("prog2$", ("prog2$", ("zp", q(N(0))), ("loghead", q(N(4)), q(N(-1)))))
    add("prog2$", ("return-last", q(Symbol("PROGN")), ("nfix", q(N(2))),
                   ("prog2$", ("ifix", q(N(1) / 2)), ("len", q(L(N(1), tail=N(2)))))))
    add("mbe", ("mbe", ":LOGIC", ("+", q(N(1)), q(N(2))),
                ":EXEC", ("-", q(N(6)), q(N(3)))))
    add("mbe", ("mbe", ":EXEC", ("logtail", q(N(3)), q(N(64))),
                ":LOGIC", ("nonnegative-integer-quotient", q(N(64)), q(N(8)))))
    add("mbe", ("if", ("zp", q(N(0))),
                ("mbe", ":LOGIC", ("fix", q(Symbol("A"))), ":EXEC", ("ifix", q(Symbol("A")))),
                q(N(99))))

    add("non-exec", ("non-exec", ("expt", q(N(2)), q(N(8)))))
    add("non-exec", ("if", ("zp", q(N(0))), ("nfix", q(N(3))),
                     ("non-exec", ("len", q(S("unreachable"))))))
    add("non-exec", ("if", ("zp", q(N(1))), q(N(0)),
                     ("non-exec", ("+", q(N(20)), q(N(22))))))
    return tests
