import random

from constraints import integer_boundary_cases
from semantics import eval_term, render_term, render_value, AuditError

VARIABLES = (("var", "x"), ("var", "count"))

def gen_bool(rng, depth):
    left = gen_int(rng, depth)
    right = gen_int(rng, depth)
    return (rng.choice(("lt", "eq")), left, right)

def gen_int(rng, depth):
    if depth <= 0:
        return rng.choice(VARIABLES + tuple(integer_boundary_cases()[:12]))
    choice = rng.randrange(12)
    next_depth = depth - 1
    if choice == 0:
        return ("add", gen_int(rng, next_depth), gen_int(rng, next_depth))
    if choice == 1:
        return ("sub", gen_int(rng, next_depth), gen_int(rng, next_depth))
    if choice == 2:
        return ("neg", gen_int(rng, next_depth))
    if choice == 3:
        return (rng.choice(("logand", "logior", "logxor")),
                gen_int(rng, next_depth), gen_int(rng, next_depth))
    if choice == 4:
        return ("lognot", gen_int(rng, next_depth))
    if choice == 5:
        return ("ash", gen_int(rng, next_depth), ("var", "count"))
    if choice == 6:
        return ("mask-signed", rng.choice((1, 31, 62, 63, 64, 65, 127)),
                gen_int(rng, next_depth))
    if choice == 7:
        return ("integer-length", gen_int(rng, next_depth))
    if choice == 8:
        return (rng.choice(("truncate", "floor", "round", "ceiling")),
                gen_int(rng, next_depth))
    if choice == 9:
        return ("if", gen_bool(rng, next_depth),
                gen_int(rng, next_depth), gen_int(rng, next_depth))
    if choice == 10:
        return ("let", "x", gen_int(rng, next_depth), gen_int(rng, next_depth))
    return rng.choice(VARIABLES)

def gen_form(rng, depth):
    if rng.randrange(4) == 0:
        return ("mv-list", gen_int(rng, depth))
    return gen_int(rng, depth)

def generated_tests(seed, count, make_test, max_depth=4):
    rng = random.Random(seed)
    tests = []
    declarations = "(declare (type (signed-byte 128) x) (type fixnum count))"
    boundaries = integer_boundary_cases()
    for index in range(count):
        form = gen_form(rng, rng.randrange(1, max_depth + 1))
        args = {"x": rng.choice(boundaries), "count": rng.randrange(-140, 141)}
        tests.append(make_test("generated", index, form, args, declarations))
    return tests
