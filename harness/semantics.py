#!/usr/bin/env python3


class AuditError(ValueError):
    pass


def _is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def _require_int(value, operation):
    if not _is_int(value):
        raise AuditError(f"{operation} requires an integer, got {value!r}")
    return value


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
        if minimum == maximum:
            expected = str(minimum)
        else:
            expected = f"{minimum} to {maximum}"
        raise AuditError(f"{op} expects {expected} argument(s), got {len(args)}")


def _false(value):
    return value == "NIL" or value == []


def _proper_list(value, operation, nil_ok=True):
    if isinstance(value, list):
        return value
    if nil_ok and value == "NIL":
        return []
    raise AuditError(f"{operation} requires a proper list, got {value!r}")


def _division(op, number, divisor):
    _require_int(number, op)
    _require_int(divisor, op)
    if divisor == 0:
        raise AuditError(f"{op}: division by zero")
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
    return [quotient, number - quotient * divisor]


def eval_term(term, env):
    if _is_int(term):
        return [term]
    if term in ("T", "NIL"):
        return [term]
    if not isinstance(term, tuple) or not term or not isinstance(term[0], str):
        raise AuditError(f"invalid term: {term!r}")

    op = term[0]
    args = term[1:]

    if op == "var":
        _arity(op, args, 1)
        name = args[0]
        if not isinstance(name, str) or not name:
            raise AuditError(f"invalid variable name: {name!r}")
        if name not in env:
            raise AuditError(f"unbound variable: {name}")
        return [env[name]]

    if op == "if":
        _arity(op, args, 3)
        test = _eval_primary(args[0], env)
        return eval_term(args[2] if _false(test) else args[1], env)

    if op == "let":
        _arity(op, args, 3)
        name = args[0]
        if not isinstance(name, str) or not name:
            raise AuditError(f"let requires a variable name, got {name!r}")
        value = _eval_primary(args[1], env)
        inner = dict(env)
        inner[name] = value
        return eval_term(args[2], inner)

    if op == "values":
        return _eval_primaries(args, env)

    if op == "mv-list":
        _arity(op, args, 1)
        return [list(eval_term(args[0], env))]

    if op == "nth-value":
        _arity(op, args, 2)
        index = _require_int(_eval_primary(args[0], env), op)
        if index < 0:
            raise AuditError("nth-value index must be non-negative")
        values = eval_term(args[1], env)
        return [values[index] if index < len(values) else "NIL"]

    if op in ("truncate", "floor", "round", "ceiling"):
        _arity(op, args, 1, 2)
        values = _eval_primaries(args, env)
        number = _require_int(values[0], op)
        divisor = _require_int(values[1], op) if len(values) == 2 else 1
        return _division(op, number, divisor)

    if op == "ash":
        _arity(op, args, 2)
        value, count = _eval_primaries(args, env)
        _require_int(value, op)
        _require_int(count, op)
        return [value << count if count >= 0 else value >> -count]

    if op in ("add", "sub", "logand", "logior", "logxor"):
        if op == "sub" and not args:
            raise AuditError("sub expects at least 1 argument, got 0")
        values = _eval_primaries(args, env)
        for value in values:
            _require_int(value, op)
        if op == "add":
            result = sum(values)
        elif op == "sub":
            result = -values[0] if len(values) == 1 else values[0]
            for value in values[1:]:
                result -= value
        elif op == "logand":
            result = -1
            for value in values:
                result &= value
        elif op == "logior":
            result = 0
            for value in values:
                result |= value
        else:
            result = 0
            for value in values:
                result ^= value
        return [result]

    if op in ("neg", "lognot", "integer-length"):
        _arity(op, args, 1)
        value = _require_int(_eval_primary(args[0], env), op)
        if op == "neg":
            return [-value]
        if op == "lognot":
            return [~value]
        return [(value if value >= 0 else -value - 1).bit_length()]

    if op == "mask-signed":
        _arity(op, args, 2)
        width, value = _eval_primaries(args, env)
        _require_int(width, op)
        _require_int(value, op)
        if width < 0:
            raise AuditError("mask-signed width must be non-negative")
        if width == 0:
            return [0]
        modulus = 1 << width
        value &= modulus - 1
        return [value - modulus if value & (1 << (width - 1)) else value]

    if op == "expt":
        _arity(op, args, 2)
        base, exponent = _eval_primaries(args, env)
        _require_int(base, op)
        _require_int(exponent, op)
        if exponent < 0:
            if base == 1:
                return [1]
            if base == -1:
                return [1 if exponent % 2 == 0 else -1]
            raise AuditError("expt with a negative exponent would produce a non-integer")
        return [pow(base, exponent)]

    if op == "lt":
        if len(args) < 2:
            raise AuditError(f"lt expects at least 2 arguments, got {len(args)}")
        values = _eval_primaries(args, env)
        for value in values:
            _require_int(value, op)
        return ["T" if all(a < b for a, b in zip(values, values[1:])) else "NIL"]

    if op == "eq":
        _arity(op, args, 2)
        left, right = _eval_primaries(args, env)
        return ["T" if left == right else "NIL"]

    if op == "length":
        _arity(op, args, 1)
        value = _eval_primary(args[0], env)
        return [len(_proper_list(value, op))]

    if op == "cons":
        _arity(op, args, 2)
        head, tail = _eval_primaries(args, env)
        return [[head] + _proper_list(tail, op)]

    if op in ("car", "cdr"):
        _arity(op, args, 1)
        original = _eval_primary(args[0], env)
        value = _proper_list(original, op)
        if not value:
            return ["NIL"]
        return [value[0] if op == "car" else value[1:]]

    if op == "append":
        lists = [_proper_list(value, op) for value in _eval_primaries(args, env)]
        result = []
        for value in lists:
            result.extend(value)
        return [result]

    if op == "elt":
        _arity(op, args, 2)
        sequence, index = _eval_primaries(args, env)
        sequence = _proper_list(sequence, op)
        _require_int(index, op)
        if not 0 <= index < len(sequence):
            raise AuditError(f"elt index {index} outside list of length {len(sequence)}")
        return [sequence[index]]

    raise AuditError(f"unknown operator: {op!r}")


def _render_symbol(name):
    if not isinstance(name, str) or not name:
        raise AuditError(f"invalid symbol name: {name!r}")
    if all(c.isalnum() or c in "+-*/<>=!?._%&$:" for c in name):
        return name
    return "|" + name.replace("\\", "\\\\").replace("|", "\\|") + "|"


def render_value(value):
    if _is_int(value):
        return str(value)
    if value in ("T", "NIL"):
        return value
    if isinstance(value, list):
        return "'" + _render_list(value)
    raise AuditError(f"cannot render value: {value!r}")


def render_results(values):
    return _render_list(values)


def _render_list(value):
    items = []
    for item in value:
        if isinstance(item, list):
            items.append(_render_list(item))
        else:
            if not _is_int(item) and item not in ("T", "NIL"):
                raise AuditError(f"cannot render list element: {item!r}")
            items.append(str(item))
    return "(" + " ".join(items) + ")"


def render_term(term):
    if _is_int(term) or term in ("T", "NIL"):
        return render_value(term)
    if not isinstance(term, tuple) or not term or not isinstance(term[0], str):
        raise AuditError(f"invalid term: {term!r}")

    op = term[0]
    args = term[1:]
    if op == "var":
        _arity(op, args, 1)
        return _render_symbol(args[0])
    if op == "let":
        _arity(op, args, 3)
        name = _render_symbol(args[0])
        return f"(let (({name} {render_term(args[1])})) {render_term(args[2])})"

    names = {
        "add": "+",
        "sub": "-",
        "neg": "-",
        "lt": "<",
        "mv-list": "multiple-value-list",
    }
    rendered = names.get(op, op)
    if op in ("if", "ash", "mask-signed", "expt", "cons", "elt", "nth-value"):
        _arity(op, args, 2 if op in ("ash", "mask-signed", "expt", "cons", "elt", "nth-value") else 3)
    elif op in ("neg", "lognot", "integer-length", "length", "car", "cdr", "mv-list"):
        _arity(op, args, 1)
    elif op in ("truncate", "floor", "round", "ceiling"):
        _arity(op, args, 1, 2)
    elif op == "sub":
        if not args:
            raise AuditError("sub expects at least 1 argument, got 0")
    elif op == "lt":
        if len(args) < 2:
            raise AuditError(f"lt expects at least 2 arguments, got {len(args)}")
    elif op == "eq":
        _arity(op, args, 2)
    elif op not in ("add", "logand", "logior", "logxor", "append", "values"):
        raise AuditError(f"unknown operator: {op!r}")
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
            raise AuditError("cannot parse an empty value")
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
                    raise AuditError("unterminated list value")
                if self.text[self.position] == ")":
                    self.position += 1
                    return result
                result.append(self.parse())
        if char == ")":
            raise AuditError("unexpected ')' in value")
        start = self.position
        while self.position < len(self.text) and not self.text[self.position].isspace() and self.text[self.position] not in "()'":
            self.position += 1
        token = self.text[start:self.position]
        upper = token.upper()
        if upper in ("T", "NIL"):
            return upper
        try:
            if token and token.lstrip("+-").isdigit() and token not in ("+", "-"):
                return int(token)
        except ValueError:
            pass
        raise AuditError(f"unsupported printed value: {token!r}")


def parse_value(text):
    if not isinstance(text, str):
        raise AuditError("printed value must be a string")
    parser = _ValueParser(text)
    value = parser.parse()
    parser._space()
    if parser.position != len(text):
        raise AuditError(f"unexpected text after value at position {parser.position}")
    return value


if __name__ == "__main__":
    assert eval_term(("mask-signed", 8, 255), {}) == [-1]
    assert eval_term(("mask-signed", 8, 128), {}) == [-128]
    assert eval_term(("ash", -3, -1), {}) == [-2]
    assert eval_term(("ash", 3, 4), {}) == [48]
    assert eval_term(("truncate", -7), {}) == [-7, 0]
    assert eval_term(("mv-list", ("values", 1, 2, 3)), {}) == [[1, 2, 3]]
    assert eval_term(("nth-value", 1, ("floor", 7, 2)), {}) == [1]
    sample = [1, [2, "NIL"], "T"]
    assert parse_value(render_value(sample)) == sample
    print("semantics self-check passed")
