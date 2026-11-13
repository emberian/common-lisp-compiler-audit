#!/usr/bin/env python3
"""Independent semantics, rendering, and deterministic generation for control/value forms."""

from dataclasses import dataclass
import random

from semantics import AuditError, eval_term as eval_base_term, render_term as render_base_term


DECLARATIONS = """(declare (type (signed-byte 128) x) (type fixnum count)
          (optimize (speed 3) (safety 1)))"""
BOUNDARIES = (-65, -64, -17, -2, -1, 0, 1, 2, 17, 63, 64, 65,
              (1 << 63) - 1, 1 << 63, -(1 << 63))


@dataclass(frozen=True)
class _Closure:
    parameters: tuple
    body: tuple
    environment: dict


class _Return(AuditError):
    def __init__(self, name, values):
        self.name = name
        self.values = values


class _Go(AuditError):
    def __init__(self, tag):
        self.tag = tag


def _integer(value):
    return isinstance(value, int) and not isinstance(value, bool)


def _false(value):
    return value == "NIL" or value == []


def _primary(values):
    return values[0] if values else "NIL"


def _eval_primary(term, environment):
    return _primary(eval_term(term, environment))


def _eval_body(body, environment):
    if not body:
        return ["NIL"]
    for term in body[:-1]:
        eval_term(term, environment)
    return eval_term(body[-1], environment)


def _arity(op, arguments, minimum, maximum=None):
    if maximum is None:
        maximum = minimum
    if not minimum <= len(arguments) <= maximum:
        expected = str(minimum) if minimum == maximum else f"{minimum} to {maximum}"
        raise AuditError(f"{op} expects {expected} argument(s), got {len(arguments)}")


def _name(value, operation):
    if not isinstance(value, str) or not value:
        raise AuditError(f"{operation} requires a nonempty symbol name")
    return value


def _bindings(value, operation):
    if not isinstance(value, tuple):
        raise AuditError(f"{operation} requires a tuple of bindings")
    result = []
    for binding in value:
        if not isinstance(binding, tuple) or len(binding) != 2:
            raise AuditError(f"{operation} has an invalid binding: {binding!r}")
        result.append((_name(binding[0], operation), binding[1]))
    return result


def _call(function, arguments):
    if not isinstance(function, _Closure):
        raise AuditError(f"attempt to call a non-function: {function!r}")
    if len(function.parameters) != len(arguments):
        raise AuditError(
            f"lambda expects {len(function.parameters)} argument(s), got {len(arguments)}"
        )
    environment = dict(function.environment)
    environment.update(zip(function.parameters, arguments))
    return _eval_body(function.body, environment)


_STRICT_BASE_OPS = {
    "add", "sub", "logand", "logior", "logxor", "neg", "lognot",
    "integer-length", "mask-signed", "expt", "ash", "lt", "eq",
    "truncate", "floor", "round", "ceiling", "length", "cons", "car",
    "cdr", "append", "elt",
}


def eval_term(term, environment=None):
    """Return the complete list of values produced by an AST term."""
    if environment is None:
        environment = {}
    if _integer(term) or term in ("T", "NIL"):
        return [term]
    if not isinstance(term, tuple) or not term or not isinstance(term[0], str):
        raise AuditError(f"invalid term: {term!r}")

    op = term[0]
    arguments = term[1:]
    if op == "var":
        _arity(op, arguments, 1)
        name = _name(arguments[0], op)
        if name not in environment:
            raise AuditError(f"unbound variable: {name}")
        return [environment[name]]
    if op == "if":
        _arity(op, arguments, 3)
        return eval_term(arguments[2] if _false(_eval_primary(arguments[0], environment))
                         else arguments[1], environment)
    if op in ("let", "let*"):
        if len(arguments) < 1:
            raise AuditError(f"{op} requires bindings")
        bindings = _bindings(arguments[0], op)
        inner = dict(environment)
        if op == "let":
            values = [_eval_primary(initial, environment) for _, initial in bindings]
            inner.update(zip((name for name, _ in bindings), values))
        else:
            for name, initial in bindings:
                inner[name] = _eval_primary(initial, inner)
        return _eval_body(arguments[1:], inner)
    if op == "lambda":
        if len(arguments) < 1 or not isinstance(arguments[0], tuple):
            raise AuditError("lambda requires a tuple of parameters")
        parameters = tuple(_name(name, op) for name in arguments[0])
        if len(set(parameters)) != len(parameters):
            raise AuditError("lambda parameters must be unique")
        return [_Closure(parameters, tuple(arguments[1:]), dict(environment))]
    if op in ("call", "funcall"):
        if not arguments:
            raise AuditError(f"{op} requires a function")
        function = _eval_primary(arguments[0], environment)
        values = [_eval_primary(argument, environment) for argument in arguments[1:]]
        return _call(function, values)
    if op == "progn":
        return _eval_body(arguments, environment)
    if op == "block":
        if not arguments:
            raise AuditError("block requires a name")
        name = _name(arguments[0], op)
        try:
            return _eval_body(arguments[1:], environment)
        except _Return as transfer:
            if transfer.name != name:
                raise
            return transfer.values
    if op == "return":
        _arity(op, arguments, 0, 1)
        values = eval_term(arguments[0], environment) if arguments else ["NIL"]
        raise _Return("NIL", values)
    if op == "return-from":
        _arity(op, arguments, 1, 2)
        name = _name(arguments[0], op)
        values = eval_term(arguments[1], environment) if len(arguments) == 2 else ["NIL"]
        raise _Return(name, values)
    if op == "tagbody":
        labels = {}
        for index, item in enumerate(arguments):
            if isinstance(item, tuple) and len(item) == 2 and item[0] == "tag":
                labels[_name(item[1], "tag")] = index
        index = 0
        jumps = 0
        while index < len(arguments):
            item = arguments[index]
            if isinstance(item, tuple) and len(item) == 2 and item[0] == "tag":
                index += 1
                continue
            try:
                eval_term(item, environment)
            except _Go as transfer:
                if transfer.tag not in labels:
                    raise
                jumps += 1
                if jumps > 1000:
                    raise AuditError("tagbody exceeded 1000 jumps")
                index = labels[transfer.tag] + 1
            else:
                index += 1
        return ["NIL"]
    if op == "go":
        _arity(op, arguments, 1)
        raise _Go(_name(arguments[0], op))
    if op == "values":
        return [_eval_primary(argument, environment) for argument in arguments]
    if op == "mv-list":
        _arity(op, arguments, 1)
        return [list(eval_term(arguments[0], environment))]
    if op in ("multiple-value-bind", "mv-let"):
        if len(arguments) < 2 or not isinstance(arguments[0], tuple):
            raise AuditError(f"{op} requires variables and a values form")
        names = tuple(_name(name, op) for name in arguments[0])
        if len(set(names)) != len(names):
            raise AuditError(f"{op} variables must be unique")
        values = eval_term(arguments[1], environment)
        inner = dict(environment)
        for index, name in enumerate(names):
            inner[name] = values[index] if index < len(values) else "NIL"
        return _eval_body(arguments[2:], inner)
    if op == "nth-value":
        _arity(op, arguments, 2)
        index = _eval_primary(arguments[0], environment)
        if not _integer(index) or index < 0:
            raise AuditError("nth-value index must be a nonnegative integer")
        values = eval_term(arguments[1], environment)
        return [values[index] if index < len(values) else "NIL"]
    if op in ("and", "or"):
        if op == "and":
            if not arguments:
                return ["T"]
            for argument in arguments[:-1]:
                if _false(_eval_primary(argument, environment)):
                    return ["NIL"]
            return eval_term(arguments[-1], environment)
        for argument in arguments:
            values = eval_term(argument, environment)
            if not _false(_primary(values)):
                return values
        return ["NIL"]
    if op == "not":
        _arity(op, arguments, 1)
        return ["T" if _false(_eval_primary(arguments[0], environment)) else "NIL"]
    if op in ("implies", "iff"):
        _arity(op, arguments, 2)
        left = _eval_primary(arguments[0], environment)
        right = _eval_primary(arguments[1], environment)
        if op == "implies":
            return ["T" if _false(left) or not _false(right) else "NIL"]
        return ["T" if _false(left) == _false(right) else "NIL"]
    if op in _STRICT_BASE_OPS:
        values = [_eval_primary(argument, environment) for argument in arguments]
        return eval_base_term((op, *values), environment)
    raise AuditError(f"unknown operator: {op!r}")


def render_results(values):
    """Render a value list using canonical Common Lisp NIL notation."""
    if not isinstance(values, list):
        raise AuditError("results must be a list")
    if not values:
        return "NIL"
    items = []
    for value in values:
        if isinstance(value, list):
            items.append(render_results(value))
        else:
            items.append(render_base_term(value))
    return "(" + " ".join(items) + ")"


_BASE_NAMES = {
    "add": "+", "sub": "-", "neg": "-", "lt": "<",
    "mv-list": "multiple-value-list",
}
_MV_LET_MACRO = """(macrolet ((mv-let (vars values-form &body body)
             `(multiple-value-bind ,vars ,values-form ,@body)))"""


def _render_names(names):
    rendered = [render_base_term(("var", name)) for name in names]
    return "(" + " ".join(rendered) + ")"


def _render_body(body):
    return " ".join(render_term(term) for term in body)


def render_term(term):
    """Render an AST term as a self-contained Common Lisp expression."""
    if _integer(term) or term in ("T", "NIL"):
        return render_base_term(term)
    if not isinstance(term, tuple) or not term or not isinstance(term[0], str):
        raise AuditError(f"invalid term: {term!r}")
    op = term[0]
    arguments = term[1:]
    if op == "var":
        return render_base_term(term)
    if op == "if":
        return "(if " + " ".join(render_term(arg) for arg in arguments) + ")"
    if op in ("let", "let*"):
        bindings = _bindings(arguments[0], op)
        rendered = "(" + " ".join(
            f"({render_base_term(('var', name))} {render_term(initial)})"
            for name, initial in bindings
        ) + ")"
        return f"({op} {rendered} {_render_body(arguments[1:])})"
    if op == "lambda":
        return (f"(function (lambda {_render_names(arguments[0])} "
                f"{_render_body(arguments[1:])}))")
    if op == "call":
        function = arguments[0]
        rendered_function = (f"(lambda {_render_names(function[1])} "
                             f"{_render_body(function[2:])})"
                             if isinstance(function, tuple) and function and
                             function[0] == "lambda" else render_term(function))
        return "(" + " ".join([rendered_function] +
                              [render_term(arg) for arg in arguments[1:]]) + ")"
    if op == "funcall":
        return "(funcall " + " ".join(render_term(arg) for arg in arguments) + ")"
    if op == "progn":
        return f"(progn {_render_body(arguments)})"
    if op == "block":
        return f"(block {render_base_term(('var', arguments[0]))} {_render_body(arguments[1:])})"
    if op == "return":
        return "(return" + (" " + render_term(arguments[0]) if arguments else "") + ")"
    if op == "return-from":
        result = f"(return-from {render_base_term(('var', arguments[0]))}"
        return result + (" " + render_term(arguments[1]) if len(arguments) > 1 else "") + ")"
    if op == "tagbody":
        items = []
        for item in arguments:
            if isinstance(item, tuple) and len(item) == 2 and item[0] == "tag":
                items.append(render_base_term(("var", item[1])))
            else:
                items.append(render_term(item))
        return "(tagbody " + " ".join(items) + ")"
    if op == "go":
        return f"(go {render_base_term(('var', arguments[0]))})"
    if op == "values":
        return "(values " + " ".join(render_term(arg) for arg in arguments) + ")"
    if op == "mv-list":
        return f"(multiple-value-list {render_term(arguments[0])})"
    if op == "multiple-value-bind":
        return (f"(multiple-value-bind {_render_names(arguments[0])} "
                f"{render_term(arguments[1])} {_render_body(arguments[2:])})")
    if op == "mv-let":
        return (f"{_MV_LET_MACRO}\n  (mv-let {_render_names(arguments[0])} "
                f"{render_term(arguments[1])} {_render_body(arguments[2:])}))")
    if op == "nth-value":
        return f"(nth-value {render_term(arguments[0])} {render_term(arguments[1])})"
    if op in ("and", "or", "not"):
        return f"({op} " + " ".join(render_term(arg) for arg in arguments) + ")"
    if op == "implies":
        return ("(flet ((implies (p q) (if p q t))) (implies "
                + " ".join(render_term(arg) for arg in arguments) + "))")
    if op == "iff":
        return ("(flet ((iff (p q) (if p (if q t nil) (if q nil t)))) (iff "
                + " ".join(render_term(arg) for arg in arguments) + "))")
    if op in _STRICT_BASE_OPS:
        rendered = _BASE_NAMES.get(op, op)
        return "(" + " ".join([rendered] + [render_term(arg) for arg in arguments]) + ")"
    raise AuditError(f"unknown operator: {op!r}")


class _Generator:
    def __init__(self, rng):
        self.rng = rng
        self.serial = 0

    def fresh(self, prefix):
        self.serial += 1
        return f"{prefix}{self.serial}"

    def boolean(self, depth, integers, functions):
        if depth <= 0:
            return (self.rng.choice(("lt", "eq")),
                    self.integer(0, integers, functions),
                    self.integer(0, integers, functions))
        choice = self.rng.randrange(6)
        if choice == 0:
            return ("not", self.boolean(depth - 1, integers, functions))
        if choice in (1, 2):
            return (self.rng.choice(("and", "or")),
                    self.boolean(depth - 1, integers, functions),
                    self.boolean(depth - 1, integers, functions))
        if choice == 3:
            return (self.rng.choice(("implies", "iff")),
                    self.boolean(depth - 1, integers, functions),
                    self.boolean(depth - 1, integers, functions))
        return (self.rng.choice(("lt", "eq")),
                self.integer(depth - 1, integers, functions),
                self.integer(depth - 1, integers, functions))

    def integer(self, depth, integers, functions):
        variables = [("var", name) for name in sorted(integers)]
        if depth <= 0:
            return self.rng.choice(variables + list(BOUNDARIES[:12]))
        choice = self.rng.randrange(17)
        next_depth = depth - 1
        if choice == 0:
            return ("add", self.integer(next_depth, integers, functions),
                    self.integer(next_depth, integers, functions))
        if choice == 1:
            return ("sub", self.integer(next_depth, integers, functions),
                    self.integer(next_depth, integers, functions))
        if choice == 2:
            return (self.rng.choice(("logand", "logior", "logxor")),
                    self.integer(next_depth, integers, functions),
                    self.integer(next_depth, integers, functions))
        if choice == 3:
            return ("if", self.boolean(next_depth, integers, functions),
                    self.integer(next_depth, integers, functions),
                    self.integer(next_depth, integers, functions))
        if choice == 4:
            name = self.fresh("l")
            initial = self.integer(next_depth, integers, functions)
            return ("let", ((name, initial),),
                    self.integer(next_depth, integers | {name}, functions))
        if choice == 5:
            first, second = self.fresh("s"), self.fresh("s")
            initial = self.integer(next_depth, integers, functions)
            middle = self.integer(next_depth, integers | {first}, functions)
            return ("let*", ((first, initial), (second, middle)),
                    self.integer(next_depth, integers | {first, second}, functions))
        if choice == 6:
            parameter = self.fresh("a")
            function = ("lambda", (parameter,),
                        self.integer(next_depth, integers | {parameter}, functions))
            return ("call", function, self.integer(next_depth, integers, functions))
        if choice == 7:
            captured, function_name, parameter = (self.fresh("c"), self.fresh("f"),
                                                  self.fresh("a"))
            initial = self.integer(next_depth, integers, functions)
            body = self.integer(next_depth, integers | {captured, parameter}, functions)
            function = ("lambda", (parameter,), body)
            call = ("funcall", ("var", function_name),
                    self.integer(next_depth, integers | {captured},
                                 functions | {function_name}))
            return ("let*", ((captured, initial), (function_name, function)), call)
        if choice == 8:
            return ("progn", self.integer(next_depth, integers, functions),
                    self.integer(next_depth, integers, functions))
        if choice == 9:
            returned = ("if", self.boolean(next_depth, integers, functions),
                        ("return", self.integer(next_depth, integers, functions)),
                        self.integer(next_depth, integers, functions))
            return ("block", "NIL", returned,
                    self.integer(next_depth, integers, functions))
        if choice == 10:
            transfer = ("if", self.boolean(next_depth, integers, functions),
                        ("go", "done"), "NIL")
            body = ("tagbody", ("tag", "start"), transfer,
                    self.integer(next_depth, integers, functions), ("tag", "done"))
            return ("progn", body, self.integer(next_depth, integers, functions))
        if choice == 11:
            values = tuple(self.integer(next_depth, integers, functions)
                           for _ in range(3))
            return ("nth-value", self.rng.randrange(3), ("values", *values))
        if choice in (12, 13):
            first, second = self.fresh("m"), self.fresh("m")
            values = ("values", self.integer(next_depth, integers, functions),
                      self.integer(next_depth, integers, functions))
            body = self.integer(next_depth, integers | {first, second}, functions)
            op = "multiple-value-bind" if choice == 12 else "mv-let"
            return (op, (first, second), values, body)
        if choice == 14:
            return (self.rng.choice(("truncate", "floor", "round", "ceiling")),
                    self.integer(next_depth, integers, functions),
                    self.rng.choice((-3, -2, -1, 1, 2, 3)))
        if choice == 15:
            return ("integer-length", self.integer(next_depth, integers, functions))
        return self.rng.choice(variables + list(BOUNDARIES[:12]))

    def form(self, depth):
        integers = {"x", "count"}
        functions = set()
        choice = self.rng.randrange(8)
        if choice == 0:
            values = tuple(self.integer(depth, integers, functions)
                           for _ in range(self.rng.randrange(4)))
            return ("mv-list", ("values", *values))
        if choice == 1:
            first, second = self.fresh("v"), self.fresh("v")
            values = ("values", self.integer(depth, integers, functions))
            return ("multiple-value-bind", (first, second), values,
                    ("values", ("var", first), ("var", second)))
        if choice == 2:
            first, second = self.fresh("v"), self.fresh("v")
            values = ("values", self.integer(depth, integers, functions),
                      self.integer(depth, integers, functions))
            return ("mv-let", (first, second), values,
                    ("values", ("var", second), ("var", first)))
        if choice == 3:
            return ("nth-value", self.rng.randrange(3, 6),
                    ("values", self.integer(depth, integers, functions)))
        if choice == 4:
            return self.boolean(depth, integers, functions)
        return self.integer(depth, integers, functions)


def generated_terms(seed=0, count=100, max_depth=4):
    """Yield a reproducible list of valid, source-guided AST terms."""
    if count < 0 or max_depth < 0:
        raise ValueError("count and max_depth must be nonnegative")
    rng = random.Random(seed)
    generator = _Generator(rng)
    return [generator.form(rng.randrange(1, max_depth + 1)) for _ in range(count)]


def features(term):
    """Return the set of AST operators, including base operators, in a term."""
    found = set()

    def visit(value):
        if not isinstance(value, tuple):
            return
        if value and isinstance(value[0], str):
            found.add(value[0])
            if value[0] == "tag":
                return
            if value[0] in ("let", "let*") and len(value) > 1:
                for binding in value[1]:
                    visit(binding[1])
                for child in value[2:]:
                    visit(child)
                return
            if value[0] in ("lambda", "multiple-value-bind", "mv-let"):
                for child in value[2:]:
                    visit(child)
                return
        for child in value:
            visit(child)

    visit(term)
    return found


def _self_check():
    env = {"x": 9, "count": 0}
    parallel = ("let", (("x", 1), ("y", ("var", "x"))),
                ("values", ("var", "x"), ("var", "y")))
    sequential = ("let*", (("x", 1), ("y", ("var", "x"))),
                  ("values", ("var", "x"), ("var", "y")))
    assert eval_term(parallel, env) == [1, 9]
    assert eval_term(sequential, env) == [1, 1]
    closure = ("let*", (("c", 7), ("f", ("lambda", ("a",),
                                         ("add", ("var", "a"), ("var", "c"))))),
               ("let", (("c", 100),), ("funcall", ("var", "f"), 5)))
    assert eval_term(closure, env) == [12]
    assert eval_term(("block", "NIL", ("return", ("values", 1, 2)), 3), env) == [1, 2]
    jumped = ("progn", ("tagbody", ("go", "done"), 1, ("tag", "done")), 4)
    assert eval_term(jumped, env) == [4]
    assert eval_term(("multiple-value-bind", ("a", "b"), ("values", 1),
                      ("values", ("var", "a"), ("var", "b"))), env) == [1, "NIL"]
    assert eval_term(("and", "T", 0, 8), env) == [8]
    assert eval_term(("and", "T", ("values", 7, 8)), env) == [7, 8]
    assert eval_term(("or", "NIL", 0, 8), env) == [0]
    assert eval_term(("or", "NIL", ("values", 7, 8)), env) == [7, 8]
    assert eval_term(("and", "NIL", ("truncate", 1, 0)), env) == ["NIL"]
    assert render_results([]) == "NIL"
    assert render_results([[]]) == "(NIL)"
    assert eval_term(("implies", "T", "NIL"), env) == ["NIL"]
    assert eval_term(("iff", 0, "NIL"), env) == ["NIL"]
    for term in (parallel, sequential, closure, jumped):
        assert isinstance(render_term(term), str)
    for term in generated_terms(73, 100):
        eval_term(term, env)
        render_term(term)
    print("forms_values self-check passed")


if __name__ == "__main__":
    _self_check()
