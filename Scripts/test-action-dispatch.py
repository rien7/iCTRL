#!/usr/bin/env python3
"""Run the actual Swift dispatcher on macOS, with device I/O replaced by spies."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def member(source, declaration):
    """Select a whole class member at its existing four-space indentation.

    Fail on missing/ambiguous declarations or boundaries, rather than silently
    testing a copy of the implementation after the production code changes.
    """
    pattern = re.compile(r"^    " + re.escape(declaration) + r"[^\n]*", re.M)
    matches = list(pattern.finditer(source))
    if len(matches) != 1:
        raise ValueError(f"Expected one {declaration!r}, found {len(matches)}")
    start, end = matches[0].span()
    line = source[start:end]
    if line.endswith("{"):
        end = source.index("\n    }", end) + len("\n    }")
    elif line.endswith("["):
        end = source.index("\n    ]", end) + len("\n    ]")
    return source[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path,
                        default=Path(__file__).resolve().parents[1],
                        help="Production checkout to test (also supports a baseline checkout)")
    args = parser.parse_args()
    root = args.source_root.resolve()
    fixtures = Path(__file__).resolve().parents[1] / "Tests/ActionDispatch"
    source = (root / "iCTRLUITests/ActionHandler.swift").read_text()
    declarations = [
        "func dispatch(", "private func validateCoordinate(",
        "private static let uiActionMethods:", "private static let seenOnRead:",
        "private static let alertCheckedReads:", "private static let switchingMethods:",
        "private static let pointTapMethods:", "private static let alertWatchSeconds",
        "private static let blindActionMethods:", "private static let settleMethods:",
        "private static let settleDefaultTimeout", "private static let settleMaxTimeout",
        "private static let settleCallBudget", "struct ScreenText {",
        "private static let captchaPhrases", "private static let rateLimitPhrases",
        "private static let promoPhrases", "private static let closeLabels",
        "static func blockers(", "private var blockedSeen:", "private func flagBlockers(",
    ]
    # Including this when present lets the same tests run against the original
    # dispatcher, where a read primes the CAPTCHA-specific rejection state.
    if re.search(r"^    private var lastChallenge:", source, re.M):
        declarations.append("private var lastChallenge:")
    selected = "\n\n".join(member(source, d) for d in declarations)
    host = (fixtures / "Host.swift").read_text()
    marker = "    // PRODUCTION_MEMBERS"
    if host.count(marker) != 1:
        raise ValueError("Host fixture must have exactly one production insertion point")
    with tempfile.TemporaryDirectory(prefix="ictrl-dispatch-tests-") as directory:
        tmp = Path(directory)
        main_swift = tmp / "main.swift"
        main_swift.write_text(host.replace(marker, selected) + "\n" +
                              (fixtures / "main.swift").read_text())
        inputs = ["iCTRLKit/RPCTypes.swift", "iCTRLKit/AuthManager.swift",
                  "iCTRLKit/SecureEnvelope.swift", "iCTRLUITests/ActionCommand.swift",
                  "iCTRLUITests/ContinuousDragPath.swift"]
        subprocess.run(["swiftc", "-module-cache-path", str(tmp / "module-cache"),
                        *[str(root / p) for p in inputs], str(main_swift),
                        "-o", str(tmp / "tests")], check=True)
        subprocess.run([str(tmp / "tests")], check=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode)
