#!/usr/bin/env python3
"""Checks the app localizations.

Every key passed to L("…") in app/Sources must exist in every
app/Resources/<lang>.lproj/Localizable.strings, with the same format
specifiers (%d, %@). Unused keys are reported as warnings.

Usage: tools/check_l10n.py   (exit code 1 on error)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "app" / "Sources"
RESOURCES = ROOT / "app" / "Resources"

KEY_IN_CODE = re.compile(r'\bL\("((?:[^"\\]|\\.)*)"')
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
SPEC = re.compile(r"%[@d]")


def unescape(s):
    return s.replace('\\"', '"').replace("\\\\", "\\")


def main():
    used = set()
    for f in SOURCES.glob("*.swift"):
        used |= {unescape(k) for k in KEY_IN_CODE.findall(f.read_text(encoding="utf-8"))}

    errors = 0
    langs = sorted(RESOURCES.glob("*.lproj"))
    if not any(p.name == "en.lproj" for p in langs):
        print("error: en.lproj is missing")
        errors += 1

    for lproj in langs:
        table = {}
        for n, line in enumerate((lproj / "Localizable.strings").read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip() or line.lstrip().startswith("/*"):
                continue
            m = ENTRY.match(line)
            if not m:
                print(f"error: {lproj.name}:{n}: unparsable line")
                errors += 1
                continue
            table[unescape(m.group(1))] = unescape(m.group(2))
        for key in sorted(used - table.keys()):
            print(f"error: {lproj.name}: missing key {key!r}")
            errors += 1
        for key, value in table.items():
            if sorted(SPEC.findall(key)) != sorted(SPEC.findall(value)):
                print(f"error: {lproj.name}: format specifiers differ for {key!r}")
                errors += 1
        for key in sorted(table.keys() - used):
            print(f"warning: {lproj.name}: unused key {key!r}")

    print(f"{len(used)} keys, {len(langs)} languages, {errors} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
