#!/usr/bin/env python3
import re
from fractions import Fraction


class RationalError(ValueError):
    pass


_EXACT = re.compile(r"^[+-]?\d+(?:/\d+)?$")


def _is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def as_rational(value):
    if isinstance(value, Fraction):
        return value
    if _is_int(value):
        return Fraction(value)
    if isinstance(value, str) and _EXACT.fullmatch(value):
        try:
            return Fraction(value)
        except (ValueError, ZeroDivisionError) as exc:
            raise RationalError(f"invalid exact rational: {value!r}") from exc
    raise RationalError(f"expected an exact rational, got {value!r}")


def format_rational(value):
    value = as_rational(value)
    if value.denominator == 1:
        return str(value.numerator)
    return f"{value.numerator}/{value.denominator}"


def _primary(values):
    return values[0] if values else "NIL"


def _eval_primary(term, env):
    return _primary(eval_term(term, env))


def _eval_primaries(terms, env):
    return [_eval_primary(term, env) for term in terms]


def _arity(op, args, minimum, maximum=None):
    if maximum is None:
        maximum = minimum
    if not minimum <= len(args) <= maximum:
        expected = str(minimum) if minimum == maximum else f"{minimum} to {maximum}"
        raise RationalError(f"{op} expects {expected} argument(s), got {len(args)}")


def _false(value):
    return value == "NIL"


def _require_rational(value, operation):
    try:
        return as_rational(value)
    except RationalError as exc:
        raise RationalError(f"{operation}: {exc}") from exc


def _require_integer(value, operation):
    value = _require_rational(value, operation)
    if value.denominator != 1:
        raise RationalError(f"{operation} requires an integer, got {format_rational(value)}")
    return value.numerator


def _nonzero(value, operation):
    value = _require_rational(value, operation)
    if not value:
        raise RationalError(f"{operation}: division by zero")
    return value


def _division(op, number, divisor):
    number = _require_rational(number, op)
    divisor = _nonzero(divisor, op)
    if op == "floor":
        quotient = number // divisor
    elif op == "ceiling":
        quotient = -((-number) // divisor)
    elif op == "truncate":
        quotient = abs(number) // abs(divisor)
        if (number < 0) != (divisor < 0):
            quotient = -quotient
    else:
        quotient = number // divisor
        remainder = number - quotient * divisor
        comparison = 2 * abs(remainder) - abs(divisor)
        if comparison > 0 or (comparison == 0 and quotient % 2 != 0):
            quotient += 1
    return [Fraction(quotient), number - quotient * divisor]


def _numbers(op, values):
    return [_require_rational(value, op) for value in values]


def eval_term(term, env):
    if _is_int(term) or isinstance(term, Fraction):
        return [as_rational(term)]
    if isinstance(term, str):
        if term in ("T", "NIL"):
            return [term]
        if _EXACT.fullmatch(term):
            return [as_rational(term)]
    if not isinstance(term, tuple) or not term or not isinstance(term[0], str):
        raise RationalError(f"invalid term: {term!r}")

    op = term[0]
    args = term[1:]
    if op == "var":
        _arity(op, args, 1)
        name = args[0]
        if not isinstance(name, str) or not name or name not in env:
            raise RationalError(f"unbound or invalid variable: {name!r}")
        return [as_rational(env[name])]
    if op == "if":
        _arity(op, args, 3)
        return eval_term(args[1] if not _false(_eval_primary(args[0], env)) else args[2], env)
    if op == "let":
        _arity(op, args, 3)
        name = args[0]
        if not isinstance(name, str) or not name:
            raise RationalError(f"let requires a variable name, got {name!r}")
        inner = dict(env)
        inner[name] = _eval_primary(args[1], env)
        return eval_term(args[2], inner)
    if op == "values":
        return _eval_primaries(args, env)
    if op == "mv-list":
        _arity(op, args, 1)
        return [list(eval_term(args[0], env))]
    if op == "nth-value":
        _arity(op, args, 2)
        index = _require_integer(_eval_primary(args[0], env), op)
        if index < 0:
            raise RationalError("nth-value index must be non-negative")
        values = eval_term(args[1], env)
        return [values[index] if index < len(values) else "NIL"]

    if op in ("floor", "ceiling", "truncate", "round"):
        _arity(op, args, 1, 2)
        values = _eval_primaries(args, env)
        return _division(op, values[0], values[1] if len(values) == 2 else 1)
    if op in ("mod", "rem"):
        _arity(op, args, 2)
        number, divisor = _eval_primaries(args, env)
        division = "floor" if op == "mod" else "truncate"
        return [_division(division, number, divisor)[1]]
    if op in ("numerator", "denominator"):
        _arity(op, args, 1)
        value = _require_rational(_eval_primary(args[0], env), op)
        return [Fraction(value.numerator if op == "numerator" else value.denominator)]
    if op in ("signum", "abs"):
        _arity(op, args, 1)
        value = _require_rational(_eval_primary(args[0], env), op)
        if op == "signum":
            return [Fraction((value > 0) - (value < 0))]
        return [abs(value)]
    if op == "expt":
        _arity(op, args, 2)
        base, exponent = _eval_primaries(args, env)
        base = _require_rational(base, op)
        exponent = _require_integer(exponent, op)
        if exponent < 0:
            _nonzero(base, op)
        try:
            return [base ** exponent]
        except ZeroDivisionError as exc:
            raise RationalError("expt: division by zero") from exc

    if op in ("+", "-", "*", "/"):
        if op in ("-", "/"):
            _arity(op, args, 1, len(args))
        values = _numbers(op, _eval_primaries(args, env))
        if op == "+":
            result = Fraction(0)
            for value in values:
                result += value
            return [result]
        if op == "*":
            result = Fraction(1)
            for value in values:
                result *= value
            return [result]
        if op == "-":
            if len(values) == 1:
                return [-values[0]]
            result = values[0]
            for value in values[1:]:
                result -= value
            return [result]
        if len(values) == 1:
            return [Fraction(1) / _nonzero(values[0], op)]
        result = values[0]
        for value in values[1:]:
            result /= _nonzero(value, op)
        return [result]

    if op in ("=", "/=", "<", ">", "<=", ">="):
        _arity(op, args, 1, len(args))
        values = _numbers(op, _eval_primaries(args, env))
        if op == "=":
            answer = all(value == values[0] for value in values[1:])
        elif op == "/=":
            answer = all(left != right for index, left in enumerate(values)
                         for right in values[index + 1:])
        elif op == "<":
            answer = all(left < right for left, right in zip(values, values[1:]))
        elif op == ">":
            answer = all(left > right for left, right in zip(values, values[1:]))
        elif op == "<=":
            answer = all(left <= right for left, right in zip(values, values[1:]))
        else:
            answer = all(left >= right for left, right in zip(values, values[1:]))
        return ["T" if answer else "NIL"]
    if op in ("max", "min"):
        _arity(op, args, 1, len(args))
        values = _numbers(op, _eval_primaries(args, env))
        return [(max if op == "max" else min)(values)]

    raise RationalError(f"unknown operator: {op!r}")


def _render_list(values):
    if not values:
        return "NIL"
    rendered = []
    for value in values:
        if isinstance(value, list):
            rendered.append(_render_list(value))
        elif isinstance(value, str) and value in ("T", "NIL", ":ERROR"):
            rendered.append(value)
        else:
            rendered.append(format_rational(value))
    return "(" + " ".join(rendered) + ")"


def render_results(values):
    return _render_list(values)


def render_value(value):
    if isinstance(value, list):
        return "'" + _render_list(value)
    if value in ("T", "NIL", ":ERROR"):
        return value
    return format_rational(value)


def _render_symbol(name):
    if not isinstance(name, str) or not name:
        raise RationalError(f"invalid symbol: {name!r}")
    if all(character.isalnum() or character in "+-*/<>=!?._%&$:" for character in name):
        return name
    return "|" + name.replace("\\", "\\\\").replace("|", "\\|") + "|"


def render_term(term):
    if _is_int(term) or isinstance(term, Fraction):
        return format_rational(term)
    if isinstance(term, str):
        if term in ("T", "NIL") or _EXACT.fullmatch(term):
            return format_rational(term) if _EXACT.fullmatch(term) else term
    if not isinstance(term, tuple) or not term or not isinstance(term[0], str):
        raise RationalError(f"invalid term: {term!r}")

    op = term[0]
    args = term[1:]
    if op == "var":
        _arity(op, args, 1)
        return _render_symbol(args[0])
    if op == "let":
        _arity(op, args, 3)
        return f"(let (({_render_symbol(args[0])} {render_term(args[1])})) {render_term(args[2])})"
    if op == "if":
        _arity(op, args, 3)
    elif op in ("values", "+", "*", "=", "/=", "<", ">", "<=", ">=", "max", "min"):
        if op != "values":
            _arity(op, args, 1, len(args))
    elif op in ("-", "/"):
        _arity(op, args, 1, len(args))
    elif op in ("floor", "ceiling", "truncate", "round"):
        _arity(op, args, 1, 2)
    elif op in ("mod", "rem", "expt"):
        _arity(op, args, 2)
    elif op in ("numerator", "denominator", "signum", "abs", "mv-list"):
        _arity(op, args, 1)
    elif op == "nth-value":
        _arity(op, args, 2)
    else:
        raise RationalError(f"unknown operator: {op!r}")
    rendered = "multiple-value-list" if op == "mv-list" else op
    return "(" + " ".join([rendered] + [render_term(arg) for arg in args]) + ")"


class _ValueParser:
    def __init__(self, text):
        self.text = text
        self.position = 0

    def _space(self):
        while self.position < len(self.text) and self.text[self.position].isspace():
            self.position += 1

    def parse(self):
        self._space()
        if self.position >= len(self.text):
            raise RationalError("cannot parse an empty value")
        char = self.text[self.position]
        if char == "'":
            self.position += 1
            return self.parse()
        if char == "(":
            self.position += 1
            result = []
            while True:
                self._space()
                if self.position >= len(self.text):
                    raise RationalError("unterminated list value")
                if self.text[self.position] == ")":
                    self.position += 1
                    return result
                result.append(self.parse())
        if char == ")":
            raise RationalError("unexpected ')' in value")
        start = self.position
        while (self.position < len(self.text) and
               not self.text[self.position].isspace() and
               self.text[self.position] not in "()'"):
            self.position += 1
        token = self.text[start:self.position]
        upper = token.upper()
        if upper in ("T", "NIL", ":ERROR"):
            return upper
        if _EXACT.fullmatch(token):
            return as_rational(token)
        raise RationalError(f"unsupported printed value: {token!r}")


def parse_value(text):
    if not isinstance(text, str):
        raise RationalError("printed value must be a string")
    parser = _ValueParser(text)
    value = parser.parse()
    parser._space()
    if parser.position != len(text):
        raise RationalError(f"unexpected text after value at position {parser.position}")
    return value


def tuple_tree(value):
    return tuple(tuple_tree(item) for item in value) if isinstance(value, list) else value


def encode_tree(value):
    if isinstance(value, tuple):
        return [encode_tree(item) for item in value]
    if isinstance(value, Fraction):
        return format_rational(value)
    return value


def decode_args(args):
    return {name: as_rational(value) for name, value in args.items()}


if __name__ == "__main__":
    assert eval_term(("floor", "-7/2", 2), {}) == [Fraction(-2), Fraction(1, 2)]
    assert eval_term(("ceiling", "-7/2", 2), {}) == [Fraction(-1), Fraction(-3, 2)]
    assert eval_term(("truncate", "-7/2"), {}) == [Fraction(-3), Fraction(-1, 2)]
    assert eval_term(("round", "-7/2"), {}) == [Fraction(-4), Fraction(1, 2)]
    assert eval_term(("round", "5/2"), {}) == [Fraction(2), Fraction(1, 2)]
    assert eval_term(("round", "7/2"), {}) == [Fraction(4), Fraction(-1, 2)]
    assert eval_term(("mod", "-7/2", 2), {}) == [Fraction(1, 2)]
    assert eval_term(("rem", "-7/2", 2), {}) == [Fraction(-3, 2)]
    assert eval_term(("expt", "-2/3", -3), {}) == [Fraction(-27, 8)]
    assert eval_term(("/=", 1, 2, 1), {}) == ["NIL"]
    assert eval_term(("mv-list", ("values", "2/3", -1)), {}) == [[Fraction(2, 3), Fraction(-1)]]
    try:
        eval_term(("/", 0), {})
    except RationalError:
        pass
    else:
        raise AssertionError("unguarded zero divisor was accepted")
    sample = [Fraction(-2, 3), [Fraction(4), "NIL"], "T"]
    assert parse_value(render_value(sample)) == sample
    print("rational semantics self-check passed")
