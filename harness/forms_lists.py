#!/usr/bin/env python3
import random


NIL = None
T = "T"
DECLARATIONS = "(declare (ignore x count))"
OPERATIONS = (
    "cons", "car", "cdr", "list", "list*", "append", "len", "length",
    "nth", "nthcdr", "butlast", "take", "update-nth", "member", "assoc",
    "remove", "position", "reverse", "true-listp", "consp", "atom", "endp",
    "equal", "eql", "eq",
)


class AuditError(ValueError):
    pass


def cons_value(head, tail):
    return ("pair", head, tail)


def list_value(*items, tail=NIL):
    result = tail
    for item in reversed(items):
        result = cons_value(item, result)
    return result


def _is_int(value):
    return type(value) is int


def _is_pair(value):
    return (
        isinstance(value, tuple)
        and len(value) == 3
        and value[0] == "pair"
    )


def _validate_value(value):
    if value is NIL or value == T or _is_int(value):
        return value
    if _is_pair(value):
        _validate_value(value[1])
        _validate_value(value[2])
        return value
    raise AuditError(f"invalid Lisp value: {value!r}")


def _proper_items(value, operation):
    result = []
    while _is_pair(value):
        result.append(value[1])
        value = value[2]
    if value is not NIL:
        raise AuditError(f"{operation} requires a proper list")
    return result


def _true_listp(value):
    while _is_pair(value):
        value = value[2]
    return value is NIL


def _arity(operation, args, minimum, maximum=None):
    if maximum is None:
        maximum = minimum
    if not minimum <= len(args) <= maximum:
        if minimum == maximum:
            expected = str(minimum)
        else:
            expected = f"{minimum} to {maximum}"
        raise AuditError(
            f"{operation} expects {expected} argument(s), got {len(args)}"
        )


def _index(value, operation):
    if not _is_int(value) or value < 0:
        raise AuditError(f"{operation} requires a nonnegative integer index")
    return value


def _boolean(value):
    return T if value else NIL


def _equal(left, right):
    if _is_pair(left) or _is_pair(right):
        return (
            _is_pair(left)
            and _is_pair(right)
            and _equal(left[1], right[1])
            and _equal(left[2], right[2])
        )
    return left == right


def _eql(left, right):
    if _is_pair(left) or _is_pair(right):
        return left is right
    return left == right


def _eq(left, right):
    if _is_int(left) or _is_int(right):
        raise AuditError("eq on numbers is not portable")
    if _is_pair(left) or _is_pair(right):
        return left is right
    return left == right


def eval_form(term, env=None):
    if env is None:
        env = {}
    if term is NIL or term == T or _is_int(term):
        return term
    if not isinstance(term, tuple) or not term or not isinstance(term[0], str):
        raise AuditError(f"invalid form: {term!r}")
    operation = term[0]
    args = term[1:]

    if operation == "quote":
        _arity(operation, args, 1)
        return _validate_value(args[0])
    if operation == "var":
        _arity(operation, args, 1)
        name = args[0]
        if not isinstance(name, str) or name not in env:
            raise AuditError(f"unbound variable: {name!r}")
        return env[name]
    if operation == "let":
        _arity(operation, args, 3)
        name, bound, body = args
        if not isinstance(name, str) or not name:
            raise AuditError("let requires a variable name")
        inner = dict(env)
        inner[name] = eval_form(bound, env)
        return eval_form(body, inner)
    if operation == "if":
        _arity(operation, args, 3)
        test = eval_form(args[0], env)
        return eval_form(args[2] if test is NIL else args[1], env)

    values = [eval_form(arg, env) for arg in args]
    if operation == "cons":
        _arity(operation, values, 2)
        return cons_value(values[0], values[1])
    if operation in ("car", "cdr"):
        _arity(operation, values, 1)
        value = values[0]
        if not _is_pair(value):
            return NIL
        return value[1] if operation == "car" else value[2]
    if operation == "list":
        return list_value(*values)
    if operation == "list*":
        _arity(operation, values, 1, len(values) + 1)
        if len(values) == 1:
            return values[0]
        return list_value(*values[:-1], tail=values[-1])
    if operation == "append":
        if not values:
            return NIL
        result = values[-1]
        for value in reversed(values[:-1]):
            result = list_value(*_proper_items(value, operation), tail=result)
        return result
    if operation == "len":
        _arity(operation, values, 1)
        value = values[0]
        result = 0
        while _is_pair(value):
            result += 1
            value = value[2]
        return result
    if operation == "length":
        _arity(operation, values, 1)
        return len(_proper_items(values[0], operation))
    if operation == "nth":
        _arity(operation, values, 2)
        index = _index(values[0], operation)
        value = values[1]
        while index and _is_pair(value):
            value = value[2]
            index -= 1
        return value[1] if _is_pair(value) else NIL
    if operation == "nthcdr":
        _arity(operation, values, 2)
        index = _index(values[0], operation)
        value = values[1]
        while index:
            value = value[2] if _is_pair(value) else NIL
            index -= 1
        return value
    if operation == "butlast":
        _arity(operation, values, 2)
        items = _proper_items(values[0], operation)
        count = _index(values[1], operation)
        if count >= len(items):
            return NIL
        return list_value(*items[:len(items) - count])
    if operation == "take":
        _arity(operation, values, 2)
        count = _index(values[0], operation)
        value = values[1]
        if count == 0:
            return NIL
        head = value[1] if _is_pair(value) else NIL
        tail = value[2] if _is_pair(value) else NIL
        return cons_value(head, eval_form(("take", count - 1, ("quote", tail))))
    if operation == "update-nth":
        _arity(operation, values, 3)
        index = _index(values[0], operation)
        new_value = values[1]
        value = values[2]
        head = value[1] if _is_pair(value) else NIL
        tail = value[2] if _is_pair(value) else NIL
        if index == 0:
            return cons_value(new_value, tail)
        updated = eval_form(("update-nth", index - 1, ("quote", new_value), ("quote", tail)))
        return cons_value(head, updated)
    if operation == "member":
        _arity(operation, values, 2)
        item = values[0]
        value = values[1]
        _proper_items(value, operation)
        while _is_pair(value):
            if _equal(item, value[1]):
                return value
            value = value[2]
        return NIL
    if operation == "assoc":
        _arity(operation, values, 2)
        key = values[0]
        entries = _proper_items(values[1], operation)
        if any(not _is_pair(entry) for entry in entries):
            raise AuditError("assoc requires an association list")
        for entry in entries:
            if _equal(key, entry[1]):
                return entry
        return NIL
    if operation == "remove":
        _arity(operation, values, 2)
        item = values[0]
        items = _proper_items(values[1], operation)
        return list_value(*(value for value in items if not _equal(item, value)))
    if operation == "position":
        _arity(operation, values, 2)
        item = values[0]
        items = _proper_items(values[1], operation)
        for index, value in enumerate(items):
            if _equal(item, value):
                return index
        return NIL
    if operation == "reverse":
        _arity(operation, values, 1)
        return list_value(*reversed(_proper_items(values[0], operation)))
    if operation == "true-listp":
        _arity(operation, values, 1)
        return _boolean(_true_listp(values[0]))
    if operation == "consp":
        _arity(operation, values, 1)
        return _boolean(_is_pair(values[0]))
    if operation in ("atom", "endp"):
        _arity(operation, values, 1)
        return _boolean(not _is_pair(values[0]))
    if operation in ("equal", "eql", "eq"):
        _arity(operation, values, 2)
        comparison = {"equal": _equal, "eql": _eql, "eq": _eq}[operation]
        return _boolean(comparison(values[0], values[1]))
    raise AuditError(f"unknown operator: {operation!r}")


def _render_value(value, quoted=False):
    if value is NIL:
        return "NIL"
    if value == T:
        return "T"
    if _is_int(value):
        return str(value)
    if not _is_pair(value):
        raise AuditError(f"cannot render value: {value!r}")
    prefix = "'" if quoted else ""
    items = []
    while _is_pair(value):
        items.append(_render_value(value[1]))
        value = value[2]
    if value is NIL:
        return prefix + "(" + " ".join(items) + ")"
    return prefix + "(" + " ".join(items) + " . " + _render_value(value) + ")"


def render_value(value):
    return _render_value(value, quoted=_is_pair(value))


def render_result(value):
    return "(" + _render_value(value) + ")"


_LOCAL_HELPERS = """
  (audit-car (x) (if (consp x) (car x) nil))
  (audit-cdr (x) (if (consp x) (cdr x) nil))
  (audit-len (x) (if (consp x) (1+ (audit-len (cdr x))) 0))
  (audit-true-listp (x) (if (consp x) (audit-true-listp (cdr x)) (null x)))
  (audit-nth (n x)
    (if (consp x)
        (if (zerop n) (car x) (audit-nth (1- n) (cdr x)))
        nil))
  (audit-nthcdr (n x)
    (if (zerop n) x (audit-nthcdr (1- n) (audit-cdr x))))
  (audit-take (n x)
    (if (zerop n)
        nil
        (cons (audit-car x) (audit-take (1- n) (audit-cdr x)))))
  (audit-update-nth (n value x)
    (if (zerop n)
        (cons value (audit-cdr x))
        (cons (audit-car x)
              (audit-update-nth (1- n) value (audit-cdr x)))))
"""


def _render_expr(term):
    if term is NIL or term == T or _is_int(term):
        return _render_value(term)
    if not isinstance(term, tuple) or not term or not isinstance(term[0], str):
        raise AuditError(f"invalid form: {term!r}")
    operation = term[0]
    args = term[1:]
    if operation == "quote":
        _arity(operation, args, 1)
        return render_value(args[0])
    if operation == "var":
        _arity(operation, args, 1)
        return args[0]
    if operation == "let":
        _arity(operation, args, 3)
        name, bound, body = args
        return f"(let (({name} {_render_expr(bound)})) {_render_expr(body)})"
    if operation == "if":
        _arity(operation, args, 3)
        return "(if " + " ".join(_render_expr(arg) for arg in args) + ")"

    names = {
        "car": "audit-car",
        "cdr": "audit-cdr",
        "len": "audit-len",
        "nth": "audit-nth",
        "nthcdr": "audit-nthcdr",
        "take": "audit-take",
        "update-nth": "audit-update-nth",
        "true-listp": "audit-true-listp",
        "endp": "atom",
    }
    rendered = names.get(operation, operation)
    if operation in ("member", "assoc", "remove", "position"):
        _arity(operation, args, 2)
        return (
            f"({rendered} {_render_expr(args[0])} {_render_expr(args[1])}"
            " :test #'equal)"
        )
    return "(" + " ".join([rendered] + [_render_expr(arg) for arg in args]) + ")"


def render_form(term):
    body = "(progn (setq *print-right-margin* 1000000) " + _render_expr(term) + ")"
    return "(labels (" + _LOCAL_HELPERS + ")\n  " + body + ")"


def make_test(family, index, form):
    expected = render_result(eval_form(form))
    return {
        "id": f"{family}-{index}",
        "family": family,
        "form": render_form(form),
        "ast": form,
        "args": {"x": 0, "count": 0},
        "declarations": DECLARATIONS,
        "expected": expected,
    }


def quoted(value):
    return ("quote", value)


def sample_values():
    return (
        NIL,
        T,
        0,
        -1,
        7,
        list_value(),
        list_value(1),
        list_value(1, 2, 3),
        list_value(NIL, T, 0),
        list_value(list_value(1, 2), list_value(1, 2)),
        list_value(1, tail=2),
        list_value(1, 2, tail=T),
        cons_value(list_value(1), 2),
    )


def sample_proper_lists():
    return (
        NIL,
        list_value(1),
        list_value(1, 2, 1),
        list_value(NIL, T, 0),
        list_value(list_value(1, 2), 3, list_value(1, 2)),
    )


def sample_alists():
    return (
        NIL,
        list_value(cons_value(1, 2), cons_value(0, T)),
        list_value(cons_value(list_value(1), 2), cons_value(1, 3)),
        list_value(cons_value(NIL, list_value(1, tail=2)), cons_value(T, 0)),
    )


def directed_forms():
    forms = []
    for value in sample_values():
        literal = quoted(value)
        for operation in ("car", "cdr", "len", "true-listp", "consp", "atom", "endp"):
            forms.append((operation, literal))
        for index in (0, 1, 2, 5):
            forms.append(("nth", index, literal))
            forms.append(("nthcdr", index, literal))
            forms.append(("take", index, literal))
            forms.append(("update-nth", index, 9, literal))
    for value in sample_proper_lists():
        literal = quoted(value)
        forms.append(("length", literal))
        forms.append(("reverse", literal))
        for count in (0, 1, 2, 5):
            forms.append(("butlast", literal, count))
        for item in (1, NIL, list_value(1, 2), 99):
            forms.append(("member", quoted(item), literal))
            forms.append(("remove", quoted(item), literal))
            forms.append(("position", quoted(item), literal))
    for alist in sample_alists():
        for key in (1, 0, NIL, list_value(1), 99):
            forms.append(("assoc", quoted(key), quoted(alist)))
    forms.extend((
        ("list",),
        ("list", 1),
        ("list", 1, NIL, quoted(list_value(2, tail=3))),
        ("list*", 7),
        ("list*", 1, 2),
        ("list*", 1, NIL, quoted(list_value(2, tail=3))),
        ("append",),
        ("append", quoted(list_value(1, 2))),
        ("append", quoted(list_value(1)), quoted(list_value(2, 3))),
        ("append", quoted(list_value(1)), quoted(list_value(2)), 3),
        ("cons", quoted(list_value(1)), quoted(list_value(2, tail=3))),
        ("equal", quoted(list_value(1, list_value(2))), quoted(list_value(1, list_value(2)))),
        ("equal", quoted(list_value(1)), quoted(list_value(1, tail=2))),
        ("eql", 7, 7),
        ("eql", 7, 8),
        ("eql", NIL, NIL),
        ("eq", NIL, NIL),
        ("eq", T, NIL),
        ("let", "shared", ("list", 1, 2), ("eq", ("var", "shared"), ("var", "shared"))),
        ("let", "shared", ("list", 1, 2), ("eql", ("var", "shared"), ("var", "shared"))),
        ("let", "shared", ("list", 1, 2), ("equal", ("var", "shared"), ("list", 1, 2))),
        ("let", "shared", ("list", 1, 2), ("eq", ("var", "shared"), ("list", 1, 2))),
        ("if", ("true-listp", quoted(list_value(1, tail=2))), ("len", quoted(list_value(1, tail=2))), ("length", quoted(list_value(1, 2)))),
    ))
    return forms


def _random_value(rng, depth, proper=False):
    atoms = (NIL, T, -2, -1, 0, 1, 2, 7)
    if depth <= 0 or rng.randrange(4) == 0:
        return NIL if proper and rng.randrange(2) else rng.choice(atoms)
    items = [_random_value(rng, depth - 1) for _ in range(rng.randrange(4))]
    tail = NIL if proper else rng.choice(atoms + (list_value(9),))
    return list_value(*items, tail=tail)


def _random_proper_value(rng, depth):
    items = [_random_value(rng, max(0, depth - 1))
             for _ in range(rng.randrange(4))]
    return list_value(*items)


def _random_proper_expr(rng, depth):
    if depth <= 0:
        return quoted(_random_proper_value(rng, 0))
    choice = rng.randrange(8)
    if choice == 0:
        return ("list", *(_random_any_expr(rng, depth - 1) for _ in range(rng.randrange(4))))
    if choice == 1:
        count = rng.randrange(3)
        return ("list",) if count == 0 else (
            "append",
            *(_random_proper_expr(rng, depth - 1) for _ in range(count)),
            _random_proper_expr(rng, depth - 1),
        )
    if choice == 2:
        return ("reverse", _random_proper_expr(rng, depth - 1))
    if choice == 3:
        return ("remove", _random_any_expr(rng, depth - 1), _random_proper_expr(rng, depth - 1))
    if choice == 4:
        return ("take", rng.randrange(5), _random_proper_expr(rng, depth - 1))
    if choice == 5:
        return (
            "update-nth", rng.randrange(5), _random_any_expr(rng, depth - 1),
            _random_proper_expr(rng, depth - 1),
        )
    if choice == 6:
        return ("nthcdr", rng.randrange(4), _random_proper_expr(rng, depth - 1))
    return quoted(_random_proper_value(rng, depth))


def _random_any_expr(rng, depth):
    if depth <= 0:
        return quoted(_random_value(rng, 0))
    choice = rng.randrange(10)
    if choice == 0:
        return ("cons", _random_any_expr(rng, depth - 1), _random_any_expr(rng, depth - 1))
    if choice == 1:
        return ("list", *(_random_any_expr(rng, depth - 1) for _ in range(rng.randrange(4))))
    if choice == 2:
        return ("list*", *(_random_any_expr(rng, depth - 1) for _ in range(1 + rng.randrange(3))))
    if choice == 3:
        return ("car", _random_any_expr(rng, depth - 1))
    if choice == 4:
        return ("cdr", _random_any_expr(rng, depth - 1))
    if choice == 5:
        return ("nth", rng.randrange(5), _random_any_expr(rng, depth - 1))
    if choice == 6:
        return ("nthcdr", rng.randrange(4), _random_any_expr(rng, depth - 1))
    if choice == 7:
        return ("take", rng.randrange(4), _random_any_expr(rng, depth - 1))
    if choice == 8:
        return _random_proper_expr(rng, depth - 1)
    return quoted(_random_value(rng, depth))


def _random_index(rng, depth):
    if depth and rng.randrange(4) == 0:
        return ("len", _random_any_expr(rng, depth - 1))
    return rng.randrange(6)


def generated_forms(seed=0, count=400, max_depth=3):
    rng = random.Random(seed)
    forms = []
    for index in range(count):
        operation = OPERATIONS[index % len(OPERATIONS)]
        depth = 1 + rng.randrange(max_depth)
        if operation == "cons":
            form = (operation, _random_any_expr(rng, depth), _random_any_expr(rng, depth))
        elif operation in ("car", "cdr", "len", "true-listp", "consp", "atom", "endp"):
            form = (operation, _random_any_expr(rng, depth))
        elif operation == "list":
            form = (operation, *(_random_any_expr(rng, depth) for _ in range(rng.randrange(4))))
        elif operation == "list*":
            form = (operation, *(_random_any_expr(rng, depth) for _ in range(1 + rng.randrange(3))))
        elif operation == "append":
            count_args = rng.randrange(3)
            if count_args == 0:
                form = (operation,)
            else:
                form = (
                    operation,
                    *(_random_proper_expr(rng, depth) for _ in range(count_args - 1)),
                    _random_any_expr(rng, depth),
                )
        elif operation == "length":
            form = (operation, _random_proper_expr(rng, depth))
        elif operation in ("nth", "nthcdr"):
            form = (operation, _random_index(rng, depth), _random_any_expr(rng, depth))
        elif operation == "butlast":
            form = (operation, _random_proper_expr(rng, depth), _random_index(rng, depth))
        elif operation == "take":
            form = (operation, _random_index(rng, depth), _random_any_expr(rng, depth))
        elif operation == "update-nth":
            form = (
                operation, _random_index(rng, depth), _random_any_expr(rng, depth),
                _random_any_expr(rng, depth),
            )
        elif operation in ("member", "remove", "position"):
            form = (operation, _random_any_expr(rng, depth), _random_proper_expr(rng, depth))
        elif operation == "assoc":
            entries = [
                ("cons", _random_any_expr(rng, depth - 1), _random_any_expr(rng, depth - 1))
                for _ in range(rng.randrange(4))
            ]
            form = (operation, _random_any_expr(rng, depth), ("list", *entries))
        elif operation == "reverse":
            form = (operation, _random_proper_expr(rng, depth))
        elif operation == "equal":
            form = (operation, _random_any_expr(rng, depth), _random_any_expr(rng, depth))
        elif operation == "eql":
            if rng.randrange(2):
                left = rng.choice((NIL, T, -2, -1, 0, 1, 2, 7))
                right = left if rng.randrange(2) else rng.choice((NIL, T, -1, 0, 1, 7))
                form = (operation, left, right)
            else:
                right = (("var", "shared") if rng.randrange(2)
                         else ("list", _random_any_expr(rng, depth)))
                form = ("let", "shared", ("list", _random_any_expr(rng, depth)),
                        ("eql", ("var", "shared"), right))
        else:
            if rng.randrange(2):
                form = ("let", "shared", ("list", _random_any_expr(rng, depth)),
                        ("eq", ("var", "shared"), ("var", "shared")))
            else:
                form = (operation, rng.choice((NIL, T)), rng.choice((NIL, T)))
        forms.append(form)
    return forms


def make_corpus(seed=0, count=400, max_depth=3):
    directed = [make_test("lists-directed", index, form)
                for index, form in enumerate(directed_forms())]
    generated = [make_test("lists-generated", index, form)
                 for index, form in enumerate(generated_forms(seed, count, max_depth))]
    return directed + generated


def self_check():
    improper = list_value(1, tail=2)
    assert eval_form(("len", quoted(improper))) == 1
    assert eval_form(("car", 7)) is NIL
    assert eval_form(("cdr", 7)) is NIL
    assert eval_form(("nthcdr", 1, quoted(improper))) == 2
    assert eval_form(("nthcdr", 2, quoted(improper))) is NIL
    assert eval_form(("take", 3, quoted(improper))) == list_value(1, NIL, NIL)
    assert eval_form(("update-nth", 2, 9, quoted(improper))) == list_value(1, NIL, 9)
    assert eval_form(("append", quoted(list_value(1)), 2)) == improper
    assert render_result(improper) == "((1 . 2))"
    assert eval_form(("true-listp", quoted(improper))) is NIL
    assert eval_form(("endp", 7)) == T
    try:
        eval_form(("eq", 1, 1))
    except AuditError:
        pass
    else:
        raise AssertionError("numeric eq must be rejected as nonportable")
    corpus = make_corpus(11, len(OPERATIONS))
    assert len(corpus) > 100
    assert corpus == make_corpus(11, len(OPERATIONS))
    assert len({test["id"] for test in corpus}) == len(corpus)
    print(f"forms_lists self-check passed: {len(corpus)} deterministic cases")


if __name__ == "__main__":
    self_check()
