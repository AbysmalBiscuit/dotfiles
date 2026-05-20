import argparse
import math
import sys


def find_float(value: float, bits_of_precision: int = 23) -> tuple[float, float, float]:
    """Finds the closest exact base-2 representable floats.

    For 32-bit single precision floats, use 23 bits.
    For 64-bit double precision floats, use 52 bits.
    """
    if value == 0.0:
        return (0.0, 0.0, 0.0)

    sign: float = math.copysign(1.0, value)
    abs_val: float = abs(value)

    # Extract the exponent component (value = mantissa * 2**exponent).
    _, exponent = math.frexp(abs_val)

    # Calculate the size of the smallest possible bit step (LSB) at this scale.
    # frexp uses a mantissa between 0.5 and 1.0, so the step size is:
    step_size: int = 2 ** (exponent - 1 - bits_of_precision)

    # Quantize the value to the nearest exact bit step.
    # This strips away the fractional drift.
    snapped_steps: int = round(abs_val / step_size)

    prev_val: float = (snapped_steps - 1) * step_size * sign
    exact_val: float = snapped_steps * step_size * sign
    next_val: float = (snapped_steps + 1) * step_size * sign

    return prev_val, exact_val, next_val


def parse_args(args: list[str] | None = None) -> argparse.Namespace:
    """Parses `args` or `sys.stdin` to get arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "number",
        type=float,
        help="Number for which to find the nearest exact binary representations.",
    )
    # Defaulting to 23 bits (32-bit single precision float)
    parser.add_argument(
        "-b",
        "--bits",
        type=int,
        default=23,
        help="Bits of precision in mantissa (23 for float, 52 for double).",
    )
    parser.add_argument(
        "-p",
        "--pretty",
        action="store_true",
        help="Output result in a pretty-formatted way.",
    )
    return parser.parse_args(args)


if __name__ == "__main__":
    args: argparse.Namespace = parse_args()

    p, r, n = find_float(args.number, args.bits)

    if args.pretty:
        print(f"Targeting {args.bits}-bit mantissa precision:", file=sys.stderr, flush=True)
        print(f"Previous Exact: {p}")
        print(f"Closest Exact:  {r}")
        print(f"Next Exact:     {n}")
    else:
        print(p, r, n)
