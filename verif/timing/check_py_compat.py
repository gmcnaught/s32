#!/usr/bin/env python3
"""Reject Python syntax newer than the interpreter that will actually run it.

    check_py_compat.py --target 3.5 verif/timing/check_timing_gate.py

Why this exists
---------------
check_timing_gate.py was written with f-strings.  It passed locally, then died
with SyntaxError inside CI -- 40 minutes into a Quartus fit, on a container
whose python3 predates 3.6 -- and the wrapper reported the crash as "timing
gate rejected this bitstream".

The obvious guards do not work:

  * running it locally proves nothing; the local interpreter is 3.14 and the
    oldest on this machine is 3.9, so no available interpreter would refuse an
    f-string by running it.
  * pulling the CI image to test against the real interpreter costs ~20 GB for
    a one-line answer, which is not a sane local dependency.
  * ast.parse(feature_version=(3,5)) does NOT reject f-strings.  CPython gates
    only a few constructs that way (walrus, async), verified empirically --
    so that plausible-looking check is a false sense of safety.
  * grepping for 'f"' trips over ordinary strings and comments.

Walking the AST and flagging node types by the version that introduced them is
exact, instant, and needs no second interpreter.
"""
from __future__ import print_function

import argparse
import ast
import sys

# node class name -> (major, minor) that introduced it
NODE_MIN_VERSION = {
    "JoinedStr":      (3, 6),   # f-strings
    "FormattedValue": (3, 6),
    "AnnAssign":      (3, 6),   # variable annotations
    "NamedExpr":      (3, 8),   # walrus
    "Match":          (3, 10),
    "MatchValue":     (3, 10),
    "MatchAs":        (3, 10),
    "MatchSequence":  (3, 10),
    "MatchMapping":   (3, 10),
    "MatchClass":     (3, 10),
    "MatchStar":      (3, 10),
    "MatchOr":        (3, 10),
    "TryStar":        (3, 11),
    "TypeAlias":      (3, 12),
    "ParamSpec":      (3, 12),
    "TypeVar":        (3, 12),
    "TypeVarTuple":   (3, 12),
}

WHY = {
    "JoinedStr": "f-string",
    "FormattedValue": "f-string",
    "AnnAssign": "variable annotation",
    "NamedExpr": "walrus operator",
    "TryStar": "except* group",
}


def check(path, target):
    with open(path) as fh:
        src = fh.read()
    try:
        tree = ast.parse(src, filename=path)
    except SyntaxError as exc:
        return [(getattr(exc, "lineno", 0), "does not parse at all: %s" % exc)]

    bad = []
    for node in ast.walk(tree):
        name = type(node).__name__
        need = NODE_MIN_VERSION.get(name)
        if need and need > target:
            bad.append((getattr(node, "lineno", 0),
                        "%s needs python %d.%d, target is %d.%d"
                        % (WHY.get(name, name), need[0], need[1],
                           target[0], target[1])))
    # posonly args are a node ATTRIBUTE, not a node type
    for node in ast.walk(tree):
        if isinstance(node, ast.arguments) and getattr(node, "posonlyargs", None):
            if (3, 8) > target:
                bad.append((0, "positional-only parameters need python 3.8"))
            break
    return sorted(set(bad))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", default="3.5",
                    help="oldest interpreter that must run these files")
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()

    major, minor = (int(p) for p in args.target.split(".")[:2])
    target = (major, minor)

    failed = False
    for path in args.files:
        problems = check(path, target)
        if problems:
            failed = True
            for lineno, why in problems:
                print("%s:%d: %s" % (path, lineno, why), file=sys.stderr)
        else:
            print("PY-COMPAT OK (>= %s): %s" % (args.target, path))

    if failed:
        print("PY-COMPAT FAIL", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
