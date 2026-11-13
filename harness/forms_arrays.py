#!/usr/bin/env python3
import random
import re
from dataclasses import dataclass, replace
from typing import Union


Atom = Union[int, str]
Key = Union[int, tuple[int, int]]


@dataclass(frozen=True)
class DottedPair:
    car: object
    cdr: object


@dataclass(frozen=True)
class Array:
    dimensions: tuple[int, ...]
    maximum_length: int
    default: Atom = 0
    order: str | None = "<"
    entries: tuple[tuple[Key, Atom], ...] = ()
    explicit_order: bool = False
    header_position: int = 0

    def __post_init__(self):
        if len(self.dimensions) not in (1, 2):
            raise ValueError("only one- and two-dimensional arrays are supported")
        if any(type(n) is not int or n <= 0 for n in self.dimensions):
            raise ValueError("array dimensions must be positive integers")
        size = self.dimensions[0] * (self.dimensions[1] if len(self.dimensions) == 2 else 1)
        if type(self.maximum_length) is not int or not size < self.maximum_length:
            raise ValueError("maximum-length must exceed the array size")
        if self.order not in ("<", ">", None):
            raise ValueError("array order must be <, >, or None")
        if self.default not in ("T", "NIL") and type(self.default) is not int:
            raise ValueError("array defaults must be integers, T, or NIL")
        if type(self.header_position) is not int or not 0 <= self.header_position <= len(self.entries):
            raise ValueError("header position must lie within the array alist")
        for key, value in self.entries:
            self._check_key(key)
            if value not in ("T", "NIL") and type(value) is not int:
                raise ValueError("array values must be integers, T, or NIL")

    def _check_key(self, key):
        if len(self.dimensions) == 1:
            if type(key) is not int or not 0 <= key < self.dimensions[0]:
                raise ValueError(f"invalid one-dimensional array index: {key!r}")
            return
        if (not isinstance(key, tuple) or len(key) != 2 or
                any(type(n) is not int for n in key)):
            raise ValueError(f"invalid two-dimensional array index: {key!r}")
        if not (0 <= key[0] < self.dimensions[0] and
                0 <= key[1] < self.dimensions[1]):
            raise ValueError(f"two-dimensional array index out of bounds: {key!r}")


@dataclass(frozen=True)
class ArrayCase:
    id: str
    family: str
    name: str
    initial: Array
    operations: tuple[tuple, ...]

    def __post_init__(self):
        for value in (self.id, self.name):
            if not re.fullmatch(r"[A-Za-z0-9-]+", value):
                raise ValueError(f"invalid ACL2 audit symbol: {value!r}")

    def as_dict(self):
        return {
            "id": self.id,
            "family": self.family,
            "name": self.name,
            "initial": {
                "dimensions": self.initial.dimensions,
                "maximum_length": self.initial.maximum_length,
                "default": self.initial.default,
                "order": self.initial.order,
                "explicit_order": self.initial.explicit_order,
                "header_position": self.initial.header_position,
                "entries": self.initial.entries,
            },
            "operations": self.operations,
        }


@dataclass(frozen=True)
class StobjCase:
    id: str
    operations: tuple[tuple, ...]

    def as_dict(self):
        return {"id": self.id, "family": "stobj", "operations": self.operations}


def array_order(array):
    return array.order if array.order is not None else "NIL"


def _lookup(array, key):
    for entry_key, value in array.entries:
        if entry_key == key:
            return True, value
    return False, array.default


def aref1(array, index):
    array._check_key(index)
    return _lookup(array, index)[1]


def aref2(array, i, j):
    array._check_key((i, j))
    return _lookup(array, (i, j))[1]


def compress1(array):
    if len(array.dimensions) != 1:
        raise ValueError("compress1 requires a one-dimensional array")
    if array.order is None:
        return array
    entries = []
    for index in range(array.dimensions[0]):
        present, value = _lookup(array, index)
        if present and value != array.default:
            entries.append((index, value))
    if array.order == ">":
        entries.reverse()
    return replace(array, entries=tuple(entries), header_position=0)


def compress2(array):
    if len(array.dimensions) != 2:
        raise ValueError("compress2 requires a two-dimensional array")
    entries = []
    for i in range(array.dimensions[0]):
        for j in range(array.dimensions[1]):
            present, value = _lookup(array, (i, j))
            if present and value != array.default:
                entries.append(((i, j), value))
    return replace(array, entries=tuple(entries), header_position=0)


def aset1(array, index, value):
    array._check_key(index)
    updated = replace(array, entries=((index, value),) + array.entries,
                      header_position=array.header_position + 1)
    if len(updated.entries) + 1 > array.maximum_length:
        return compress1(updated)
    return updated


def aset2(array, i, j, value):
    array._check_key((i, j))
    updated = replace(array, entries=(((i, j), value),) + array.entries,
                      header_position=array.header_position + 1)
    if len(updated.entries) + 1 > array.maximum_length:
        return compress2(updated)
    return updated


def maybe_flush_and_compress1(array):
    return compress1(array)


def header_value(array):
    result = [":HEADER", ":DIMENSIONS", list(array.dimensions),
              ":MAXIMUM-LENGTH", array.maximum_length,
              ":DEFAULT", array.default]
    if array.explicit_order:
        result.extend((":ORDER", "NIL" if array.order is None else array.order))
    return result


def externalize(value):
    if isinstance(value, Array):
        entries = []
        for key, entry_value in value.entries:
            external_key = DottedPair(*key) if isinstance(key, tuple) else key
            if entry_value == "NIL":
                entries.append([external_key])
            else:
                entries.append(DottedPair(external_key, entry_value))
        position = value.header_position
        return entries[:position] + [header_value(value)] + entries[position:]
    if isinstance(value, tuple):
        return [externalize(item) for item in value]
    if isinstance(value, list):
        return [externalize(item) for item in value]
    return value


def evaluate_array_case(case):
    array = case.initial
    observations = []
    for operation in case.operations:
        op = operation[0]
        if op == "aref1":
            observations.append(aref1(array, operation[1]))
        elif op == "aset1":
            array = aset1(array, operation[1], operation[2])
            observations.append(array)
        elif op == "compress1":
            array = compress1(array)
            observations.append(array)
        elif op == "maybe-flush-and-compress1":
            array = maybe_flush_and_compress1(array)
            observations.append(array)
        elif op == "array-order":
            observations.append(array_order(array))
        elif op == "aref2":
            observations.append(aref2(array, operation[1], operation[2]))
        elif op == "aset2":
            array = aset2(array, operation[1], operation[2], operation[3])
            observations.append(array)
        elif op == "compress2":
            array = compress2(array)
            observations.append(array)
        else:
            raise ValueError(f"unknown array operation: {op!r}")
    return tuple(observations)


def evaluate_stobj_case(case, vector_length=4):
    scalar = 0
    vector = [0] * vector_length
    observations = []
    for operation in case.operations:
        op = operation[0]
        if op == "set-scalar":
            scalar = operation[1]
            observations.append(scalar)
        elif op == "get-scalar":
            observations.append(scalar)
        elif op == "set-vector":
            index, value = operation[1], operation[2]
            if not 0 <= index < vector_length:
                raise ValueError("stobj vector index out of bounds")
            vector[index] = value
            observations.append(vector[index])
        elif op == "get-vector":
            index = operation[1]
            if not 0 <= index < vector_length:
                raise ValueError("stobj vector index out of bounds")
            observations.append(vector[index])
        else:
            raise ValueError(f"unknown stobj operation: {op!r}")
    return tuple(observations)


def render_value(value):
    if type(value) is int:
        return str(value)
    if isinstance(value, DottedPair):
        return f"({render_value(value.car)} . {render_value(value.cdr)})"
    if isinstance(value, (list, tuple)):
        return "(" + " ".join(render_value(item) for item in value) + ")"
    if isinstance(value, str):
        if re.fullmatch(r"[A-Za-z0-9+*/<>=!?._%&$:-]+", value):
            return value
        return "|" + value.replace("\\", "\\\\").replace("|", "\\|") + "|"
    raise TypeError(f"cannot render ACL2 value: {value!r}")


def _array_expression(case):
    bindings = [("A0", "'" + render_value(externalize(case.initial)))]
    observations = []
    for index, operation in enumerate(case.operations):
        op = operation[0]
        current = f"A{index}"
        following = f"A{index + 1}"
        observation = f"V{index}"
        arguments = operation[1:]
        if op in ("aref1", "aref2", "array-order"):
            expression = f"({op} '{case.name} {current}" if op != "array-order" else None
            if op == "array-order":
                expression = f"(array-order (header '{case.name} {current}))"
            else:
                expression += " " + " ".join(str(arg) for arg in arguments) + ")"
            bindings.append((following, current))
        elif op in ("aset1", "aset2", "compress1", "compress2",
                    "maybe-flush-and-compress1"):
            expression = f"({op} '{case.name} {current}"
            if arguments:
                expression += " " + " ".join(render_value(arg) for arg in arguments) + ")"
            else:
                expression += ")"
            bindings.append((following, expression))
            expression = following
        else:
            raise ValueError(f"unknown array operation: {op!r}")
        bindings.append((observation, expression))
        observations.append(observation)
    binding_text = "\n       ".join(f"({name} {value})" for name, value in bindings)
    array_variables = " ".join(f"A{index}" for index in range(len(case.operations) + 1))
    return (f"(let* ({binding_text})\n"
            f"  (declare (ignorable {array_variables}))\n"
            f"  (list {' '.join(observations)}))")


def array_function_name(case):
    return f"AUDIT-FN-{case.id}"


def array_definition(case):
    return (f"(defun {array_function_name(case)} ()\n"
            "  (declare (xargs :verify-guards nil))\n"
            f"  {_array_expression(case)})")


def array_invocation(case):
    function = array_function_name(case)
    return f"(value-triple (list :array-audit '{case.id} ({function})))"


STOBJ_DEFINITION = """(defstobj audit-st
  (audit-scalar :type integer :initially 0)
  (audit-vector :type (array integer (4)) :initially 0))"""


def stobj_function_name(case):
    return f"AUDIT-STOBJ-FN-{case.id}"


def stobj_definition(case):
    body = f"(mv (list {' '.join(f'V{i}' for i in range(len(case.operations)))}) audit-st)"
    for index in reversed(range(len(case.operations))):
        operation = case.operations[index]
        op = operation[0]
        if op == "set-scalar":
            accessor = "(audit-scalar audit-st)"
            update = f"(update-audit-scalar {operation[1]} audit-st)"
        elif op == "get-scalar":
            accessor = "(audit-scalar audit-st)"
            update = None
        elif op == "set-vector":
            accessor = f"(audit-vectorI {operation[1]} audit-st)"
            update = f"(update-audit-vectorI {operation[1]} {operation[2]} audit-st)"
        elif op == "get-vector":
            accessor = f"(audit-vectorI {operation[1]} audit-st)"
            update = None
        else:
            raise ValueError(f"unknown stobj operation: {op!r}")
        body = f"(let ((V{index} {accessor}))\n  {body})"
        if update is not None:
            body = f"(let ((audit-st {update}))\n  {body})"
    return (f"(defun {stobj_function_name(case)} (audit-st)\n"
            "  (declare (xargs :stobjs audit-st :verify-guards nil))\n"
            f"  {body})")


def stobj_invocation(case):
    return (f"(mv-let (audit-result audit-st)\n"
            f"  ({stobj_function_name(case)} audit-st)\n"
            f"  (mv nil (list :stobj-audit '{case.id} audit-result) audit-st state))")


def _case(case_id, family, array, operations):
    return ArrayCase(case_id, family, f"AUDIT-AR-{case_id}", array, tuple(operations))


def known_maybe_flush_case():
    array = Array((2,), 4, default=0)
    return _case("KNOWN-MAYBE-FLUSH", "known-maybe-flush", array,
                 [("compress1",), ("aset1", 0, 1),
                  ("maybe-flush-and-compress1",)])


def directed_array_cases():
    cases = [known_maybe_flush_case()]
    for order in ("<", ">", None):
        label = "NONE" if order is None else "LT" if order == "<" else "GT"
        array = Array((4,), 7, default=0, order=order,
                      explicit_order=order != "<",
                      entries=((2, 8), (0, 0), (2, 9), (3, 4), (1, 0)))
        cases.append(_case(f"ORDER-{label}", "array-order", array,
                           [("array-order",), ("aref1", 0), ("aref1", 1),
                            ("aref1", 2), ("compress1",), ("aref1", 2)]))
    repeated = Array((3,), 5, default=-1, entries=((1, 7),))
    cases.append(_case("REPEATED-WRITES", "repeated-writes", repeated,
                       [("aref1", 0), ("aset1", 0, 4), ("aset1", 0, 5),
                        ("aref1", 0), ("aset1", 2, -1), ("aset1", 1, 9),
                        ("compress1",), ("aref1", 2)]))
    identity = Array((3,), 6, default=0, entries=((2, 3), (0, 1)))
    cases.append(_case("CACHE-CANONICAL", "cache-canonicalization", identity,
                       [("compress1",), ("compress1",), ("aset1", 1, 2),
                        ("compress1",), ("compress1",)]))
    cases.append(_case("CACHE-EQUAL-INPUT", "cache-canonicalization", identity,
                       [("aset1", 1, 2), ("compress1",), ("aref1", 0),
                        ("aref1", 1), ("aref1", 2)]))
    fresh = Array((2,), 4, default=0, entries=((1, 6), (0, 5)))
    cases.append(_case("MAYBE-FRESH", "maybe-flush-other", fresh,
                       [("maybe-flush-and-compress1",)]))
    cases.append(_case("MAYBE-CANONICAL", "maybe-flush-other", fresh,
                       [("compress1",), ("maybe-flush-and-compress1",)]))
    cases.append(_case("MAYBE-FLUSH-OLD", "maybe-flush-other", fresh,
                       [("compress1",), ("aset1", 0, 7),
                        ("maybe-flush-and-compress1",), ("compress1",)]))
    two_d = Array((2, 3), 8, default="NIL",
                  entries=(((1, 2), 8), ((0, 1), 0), ((1, 2), 9),
                           ((0, 0), 4), ((1, 0), "NIL")))
    cases.append(_case("TWO-D-COMPRESS", "array2", two_d,
                       [("aref2", 0, 1), ("aref2", 0, 2), ("aref2", 1, 2),
                        ("compress2",), ("aref2", 1, 2), ("compress2",)]))
    cases.append(_case("TWO-D-WRITES", "array2", two_d,
                       [("aset2", 0, 2, 3), ("aset2", 1, 1, 5),
                        ("aset2", 0, 2, 6), ("aref2", 0, 2),
                        ("aset2", 1, 0, 7), ("compress2",)]))
    return cases


def random_array_cases(seed=0, count=200):
    rng = random.Random(seed)
    cases = []
    values = (-3, -1, 0, 1, 2, 7, "NIL")
    for index in range(count):
        dimension = rng.randrange(2, 7)
        default = rng.choice(values)
        order = rng.choice(("<", ">"))
        entries = tuple((rng.randrange(dimension), rng.choice(values))
                        for _ in range(rng.randrange(0, dimension + 3)))
        array = Array((dimension,), dimension + rng.randrange(1, 6),
                      default=default, order=order, entries=entries,
                      explicit_order=order == ">" or rng.choice((False, True)))
        operations = []
        for _ in range(rng.randrange(6, 17)):
            choice = rng.random()
            if choice < 0.42:
                operations.append(("aset1", rng.randrange(dimension), rng.choice(values)))
            elif choice < 0.72:
                operations.append(("aref1", rng.randrange(dimension)))
            elif choice < 0.95:
                operations.append(("compress1",))
            else:
                operations.append(("array-order",))
        cases.append(_case(f"RANDOM-{index:05d}", "random-array1", array, operations))
    return cases


def stobj_cases(seed=0, count=40):
    rng = random.Random(seed + 101)
    cases = []
    reset = [("set-scalar", 0)] + [("set-vector", i, 0) for i in range(4)]
    directed = reset + [
        ("get-scalar",), ("set-scalar", 4), ("set-scalar", -2),
        ("get-scalar",), ("set-vector", 1, 8), ("set-vector", 1, 9),
        ("get-vector", 1), ("get-vector", 0), ("set-vector", 1, 0),
        ("get-vector", 1),
    ]
    cases.append(StobjCase("STOBJ-DIRECTED", tuple(directed)))
    for index in range(count):
        operations = list(reset)
        for _ in range(rng.randrange(4, 15)):
            if rng.random() < 0.5:
                operations.append(("set-scalar", rng.randrange(-20, 21)))
            else:
                operations.append(("set-vector", rng.randrange(4), rng.randrange(-20, 21)))
            if rng.random() < 0.6:
                if rng.random() < 0.5:
                    operations.append(("get-scalar",))
                else:
                    operations.append(("get-vector", rng.randrange(4)))
        cases.append(StobjCase(f"STOBJ-{index:05d}", tuple(operations)))
    return cases


if __name__ == "__main__":
    control = known_maybe_flush_case()
    trace = evaluate_array_case(control)
    assert trace[0] == Array((2,), 4)
    assert trace[1].entries == ((0, 1),)
    assert trace[1].header_position == 1
    assert trace[2].entries == trace[1].entries
    assert trace[2].header_position == 0
    assert externalize(trace[2]) != externalize(trace[1])
    descending = Array((3,), 5, entries=((0, 1), (2, 3)), order=">", explicit_order=True)
    assert compress1(descending).entries == ((2, 3), (0, 1))
    assert aref1(Array((2,), 4, default=9), 1) == 9
    print("array model self-check passed")
