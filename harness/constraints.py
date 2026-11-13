import random

from z3 import BitVec, BitVecVal, Or, Solver, sat


_COUNT_WIDTH = 16
_MAX_SHIFT_COUNT = 140


def _signed(value, width):
    value &= (1 << width) - 1
    if value & (1 << (width - 1)):
        return value - (1 << width)
    return value


def _spread_bits(width):
    value = 0
    for limb in range(0, width, 32):
        value |= 1 << limb
        value |= 1 << min(limb + 31, width - 1)
    return value


def _alternating_bits(width, byte):
    value = 0
    for offset in range(0, width, 8):
        value |= byte << offset
    return value


def _validate_width(width):
    if isinstance(width, bool) or not isinstance(width, int):
        raise TypeError("width must be an integer")
    if width <= 0:
        raise ValueError("width must be positive")


def integer_boundary_cases(width=128):
    """Return signed integer values at bit, byte, and machine-word boundaries."""
    _validate_width(width)
    minimum = -(1 << (width - 1))
    maximum = (1 << (width - 1)) - 1
    values = [0, 1, -1, 2, -2, minimum, maximum]

    for bit in range(width - 1):
        power = 1 << bit
        values.extend((power - 1, power, power + 1))
        values.extend((-power - 1, -power, -power + 1))

    word_width = min(32, width)
    low_word = (1 << word_width) - 1
    high_word = low_word << (width - word_width)
    values.extend(
        (
            low_word,
            high_word,
            _alternating_bits(width, 0xAA),
            _alternating_bits(width, 0x55),
            _spread_bits(width),
        )
    )

    result = []
    seen = set()
    for value in values:
        value = _signed(value, width)
        if value not in seen:
            seen.add(value)
            result.append(value)
    return result


def shift_cases(seed=0, count=24, width=128):
    """Generate diverse, deterministic signed shift operands using Z3 models."""
    _validate_width(width)
    if isinstance(seed, bool) or not isinstance(seed, int):
        raise TypeError("seed must be an integer")
    if isinstance(count, bool) or not isinstance(count, int):
        raise TypeError("count must be an integer")
    if count < 0:
        raise ValueError("count must be nonnegative")

    rng = random.Random(seed)
    x = BitVec("x", width)
    shift_count = BitVec("count", _COUNT_WIDTH)
    word_width = min(32, width)
    low_word = (1 << word_width) - 1
    high_word = _signed(low_word << (width - word_width), width)
    low_word = _signed(low_word, width)
    core_scenarios = (
        (0, "zero"),
        (1, "one"),
        (-1, "minus-one"),
        (-(1 << (width - 1)), "maximum"),
        ((1 << (width - 1)) - 1, "minimum"),
        (low_word, "positive"),
        (high_word, "negative"),
        (_signed(_alternating_bits(width, 0xAA), width), "any"),
        (_signed(_spread_bits(width), width), "any"),
    )
    patterns = integer_boundary_cases(width)
    results = []
    seen = set()

    def add_count_constraint(mode):
        if mode == "any":
            return
        if mode == "zero":
            solver.add(shift_count == 0)
        elif mode == "one":
            solver.add(shift_count == 1)
        elif mode == "minus-one":
            solver.add(shift_count == -1)
        elif mode == "maximum":
            solver.add(shift_count == _MAX_SHIFT_COUNT)
        elif mode == "minimum":
            solver.add(shift_count == -_MAX_SHIFT_COUNT)
        elif mode == "positive":
            solver.add(shift_count > 0)
        elif mode == "negative":
            solver.add(shift_count < 0)
        else:
            raise AssertionError("unknown count mode")

    def minimize_signed(variable, bits, lower, upper):
        while lower < upper:
            midpoint = (lower + upper) // 2
            solver.push()
            solver.add(variable <= BitVecVal(midpoint, bits))
            if solver.check() == sat:
                upper = midpoint
            else:
                lower = midpoint + 1
            solver.pop()
        return lower

    def next_unique_model():
        while solver.check() == sat:
            x_value = minimize_signed(
                x, width, -(1 << (width - 1)), (1 << (width - 1)) - 1
            )
            solver.push()
            solver.add(x == BitVecVal(x_value, width))
            count_value = minimize_signed(
                shift_count,
                _COUNT_WIDTH,
                -_MAX_SHIFT_COUNT,
                _MAX_SHIFT_COUNT,
            )
            solver.add(shift_count == BitVecVal(count_value, _COUNT_WIDTH))
            if solver.check() != sat:
                raise AssertionError("canonical model disappeared")
            model = solver.model()
            x_value = _signed(model.eval(x).as_long(), width)
            count_value = _signed(model.eval(shift_count).as_long(), _COUNT_WIDTH)
            solver.pop()
            solver.add(
                Or(
                    x != BitVecVal(x_value, width),
                    shift_count != BitVecVal(count_value, _COUNT_WIDTH),
                )
            )
            if (x_value, count_value) not in seen:
                return x_value, count_value
        return None

    for index in range(count):
        solver = Solver()
        solver.set(random_seed=seed & 0xFFFFFFFF)
        solver.add(shift_count >= -_MAX_SHIFT_COUNT)
        solver.add(shift_count <= _MAX_SHIFT_COUNT)
        for previous_x, previous_count in seen:
            solver.add(
                Or(
                    x != BitVecVal(previous_x, width),
                    shift_count != BitVecVal(previous_count, _COUNT_WIDTH),
                )
            )

        solver.push()
        if index < len(core_scenarios):
            x_value, count_mode = core_scenarios[index]
            solver.add(x == BitVecVal(x_value, width))
        else:
            x_value = patterns[rng.randrange(len(patterns))]
            if index % 2:
                solver.add(x == BitVecVal(x_value, width))
            else:
                mask = _spread_bits(width)
                solver.add(
                    (x & BitVecVal(mask, width))
                    == BitVecVal(x_value & mask, width)
                )
            count_mode = ("any", "positive", "negative", "zero")[
                rng.randrange(4)
            ]
        add_count_constraint(count_mode)
        values = next_unique_model()
        solver.pop()

        if values is None:
            solver.push()
            values = next_unique_model()
            solver.pop()
        if values is None:
            raise RuntimeError("the bounded bit-vector space is exhausted")

        x_value, count_value = values
        seen.add(values)
        results.append({"x": x_value, "count": count_value})

    return results


if __name__ == "__main__":
    cases = shift_cases()
    assert len(cases) == 24
    assert cases == shift_cases()
    assert len({(case["x"], case["count"]) for case in cases}) == len(cases)
    assert all(type(case["x"]) is int for case in cases)
    assert all(type(case["count"]) is int for case in cases)
    assert all(-140 <= case["count"] <= 140 for case in cases)
    assert any(case["x"] > 0 for case in cases)
    assert any(case["x"] < 0 for case in cases)
    assert any(case["count"] > 0 for case in cases)
    assert any(case["count"] < 0 for case in cases)
    assert any(case["count"] == 0 for case in cases)
    boundaries = integer_boundary_cases()
    assert all(value in boundaries for value in (0, 1, -1))
    print("count:", len(cases))
    print("sample cases:")
    for case in cases[:6]:
        print(case)
