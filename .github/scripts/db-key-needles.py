"""T-015: prints the search needles of the synthetic test keys, one per line.

Same formula as app/test/support/synthetic_key.dart:
byte[i] = (seed + 97*i) mod 256, seeds 61 and 62. Needles: lowercase hex,
uppercase hex, standard base64 (text logs cannot hold the raw bytes).
The keys are synthetic test keys, not secrets; still, callers never print
these lines (db-key-log-scan.sh only counts matches).
"""
import base64

for seed in (61, 62):
    key = bytes((seed + 97 * i) & 0xFF for i in range(32))
    print(key.hex())
    print(key.hex().upper())
    print(base64.b64encode(key).decode("ascii"))
