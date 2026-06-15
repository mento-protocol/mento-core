#!/usr/bin/env python3
"""
Independent reference model for MedianDeltaBreakerV2.

This computes the time-normalized slew allowance:

    allowed = min(maxJump, baseJump + slewPerSecond * dt)

and the relative delta:

    relDelta = |current - prev| / prev

entirely in numpy floating point on the *fraction* scale (NOT the contract's
integer Fixidity arithmetic), then scales to Fixidity 1e24 for comparison.
This is deliberately an independent implementation: it must agree with the
Solidity `calculateAllowed` / `calculateRelativeDelta` to within 1e-9 relative,
validating the contract against an external model rather than against itself.

Run:  python3 test/references/median_delta_breaker_v2_reference.py
It prints a Solidity-ready table of reference values used in
test/oracles/DataStreamsMedianDeltaBreakerV2.t.sol.
"""

import numpy as np

FIX1 = 10**24

# Fixidity-scaled parameter presets. These are EXACT integers, identical to the
# values hardcoded in the Solidity test, so the only thing being independently
# modeled here is the formula, not the parameter encoding.
# FX-ish: baseJump 0.5%, slew 2%/hour, maxJump 5%.
FX = dict(
    baseJump=5 * 10**21,                 # 0.5%
    slewPerSecond=(2 * 10**22) // 3600,  # 2%/hour expressed per-second (floor)
    maxJump=5 * 10**22,                  # 5%
)
# Crypto-ish: baseJump 1%, slew 10%/hour, maxJump 20%.
CRYPTO = dict(
    baseJump=10 * 10**21,                  # 1%
    slewPerSecond=(10 * 10**22) // 3600,   # 10%/hour expressed per-second (floor)
    maxJump=20 * 10**22,                   # 20%
)


def allowed_ref(p, dt):
    """Reference allowance in Fixidity units, computed in float on the fraction scale."""
    base = p["baseJump"] / FIX1
    slew = p["slewPerSecond"] / FIX1
    mx = p["maxJump"] / FIX1
    a = np.float64(base) + np.float64(slew) * np.float64(dt)
    a = np.minimum(np.float64(mx), a)
    return a  # fraction (e.g. 0.05)


def rel_delta_ref(prev, current):
    """Reference relative delta in float on the fraction scale."""
    return np.abs(np.float64(current) - np.float64(prev)) / np.float64(prev)


def fix(frac):
    return int(round(frac * FIX1))


# (label, preset, dt) scenarios for calculateAllowed validation.
ALLOWED_SCENARIOS = [
    ("FX dt=0 (baseJump floor)", FX, 0),
    ("FX dt=30s (flash window)", FX, 30),
    ("FX dt=300s", FX, 300),
    ("FX dt=3600s", FX, 3600),
    ("FX dt=10800s (3h, hits maxJump ceiling)", FX, 10800),
    ("FX dt=100000s (deep ceiling)", FX, 100000),
    ("CRYPTO dt=0", CRYPTO, 0),
    ("CRYPTO dt=60s", CRYPTO, 60),
    ("CRYPTO dt=600s", CRYPTO, 600),
    ("CRYPTO dt=3600s", CRYPTO, 3600),
    ("CRYPTO dt=7200s (hits ceiling)", CRYPTO, 7200),
]

# (label, prev_fix, current_fix) scenarios for calculateRelativeDelta validation.
# Medians are exact Fixidity integers (identical in the Solidity test).
RELDELTA_SCENARIOS = [
    ("flat", 15 * 10**23, 15 * 10**23),       # 1.5 -> 1.5
    ("+3%", 10**24, 103 * 10**22),            # 1.0 -> 1.03
    ("-3%", 10**24, 97 * 10**22),             # 1.0 -> 0.97
    ("+0.5%", 2 * 10**24, 201 * 10**22),      # 2.0 -> 2.01
    ("+20%", 8 * 10**23, 96 * 10**22),        # 0.8 -> 0.96
]


def main():
    print("=== calculateAllowed reference (Fixidity 1e24) ===")
    for label, p, dt in ALLOWED_SCENARIOS:
        a = allowed_ref(p, dt)
        print(
            f"baseJump={p['baseJump']} slewPerSecond={p['slewPerSecond']} "
            f"maxJump={p['maxJump']} dt={dt} -> allowed={fix(a)}  // {label} ({a:.10g})"
        )

    print("\n=== calculateRelativeDelta reference (Fixidity 1e24) ===")
    for label, prev, cur in RELDELTA_SCENARIOS:
        rd = rel_delta_ref(prev, cur)
        print(f"prev={prev} current={cur} -> relDelta={fix(rd)}  // {label} ({rd:.10g})")

    print("\n=== presets ===")
    for name, p in (("FX", FX), ("CRYPTO", CRYPTO)):
        print(f"{name}: baseJump={p['baseJump']} slewPerSecond={p['slewPerSecond']} maxJump={p['maxJump']}")


if __name__ == "__main__":
    main()
