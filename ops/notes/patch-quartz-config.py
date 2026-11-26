#!/usr/bin/env python3
"""Set pageTitle/baseUrl/ignorePatterns and publishAssets in a Quartz 5 config.

Line-based: preserves comments and every key it does not own. publishAssets is
set, not appended: all existing occurrences are dropped and exactly one
`publishAssets: "referenced"` is written after the ignorePatterns block.
"""
from __future__ import annotations

import argparse
import os
import sys

DEFAULT_IGNORE = [
    "raw/**",
    ".obsidian/**",
    ".trash/**",
    "node_modules/**",
    ".git/**",
    "**/__pycache__/**",
]


def die(message: str) -> None:
    print(f"patch-quartz-config: {message}", file=sys.stderr)
    raise SystemExit(1)


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file")
    parser.add_argument("--title", required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument(
        "--ignore",
        default=",".join(DEFAULT_IGNORE),
        help="comma-separated glob patterns",
    )
    args = parser.parse_args()

    globs = [item.strip() for item in args.ignore.split(",") if item.strip()]
    if not globs:
        die("--ignore is empty")

    try:
        with open(args.file, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError as exc:
        die(f"cannot read {args.file}: {exc}")

    try:
        start = next(
            i for i, line in enumerate(lines) if line.rstrip() == "configuration:"
        )
    except StopIteration:
        die("no top-level 'configuration:' block")

    end = len(lines)
    for i in range(start + 1, len(lines)):
        line = lines[i]
        if line.strip() and not line.startswith((" ", "\t", "#")):
            end = i
            break

    block = lines[start + 1 : end]
    has_ignore = any(
        line.startswith("  ignorePatterns:") and indent_of(line) == 2
        for line in block
    )

    output: list[str] = []
    seen_title = False
    seen_base = False
    seen_ignore = False
    wrote_publish = False

    def write_ignore() -> None:
        output.append("  ignorePatterns:")
        output.extend(f'    - "{glob}"' for glob in globs)

    def write_publish() -> None:
        nonlocal wrote_publish
        if not wrote_publish:
            output.append('  publishAssets: "referenced"')
            wrote_publish = True

    i = 0
    while i < len(block):
        line = block[i]

        if line.startswith("  pageTitle:") and indent_of(line) == 2:
            if seen_title:
                die("duplicate pageTitle")
            output.append(f'  pageTitle: "{args.title}"')
            seen_title = True
            i += 1
            continue

        if line.startswith("  baseUrl:") and indent_of(line) == 2:
            if seen_base:
                die("duplicate baseUrl")
            output.append(f'  baseUrl: "{args.base_url}"')
            seen_base = True
            i += 1
            if not has_ignore:
                write_ignore()
                write_publish()
            continue

        if line.startswith("  ignorePatterns:") and indent_of(line) == 2:
            if seen_ignore:
                die("duplicate ignorePatterns")
            write_ignore()
            seen_ignore = True
            i += 1
            while i < len(block) and block[i].strip() and indent_of(block[i]) > 2:
                i += 1
            write_publish()
            continue

        if line.startswith("  publishAssets:") and indent_of(line) == 2:
            # Drop every existing occurrence; it is re-added exactly once.
            i += 1
            continue

        output.append(line)
        i += 1

    if not seen_title:
        die("no '  pageTitle:' in the configuration block")
    if not seen_base:
        die("no '  baseUrl:' in the configuration block")
    if not seen_ignore:
        die("no '  ignorePatterns:' in the configuration block")
    if not wrote_publish:
        write_publish()

    patched = lines[: start + 1] + output + lines[end:]

    def count(prefix: str) -> int:
        return sum(1 for line in patched if line.startswith(prefix))

    if count("  pageTitle:") != 1:
        die(f"expected exactly one pageTitle, found {count('  pageTitle:')}")
    if count("  baseUrl:") != 1:
        die(f"expected exactly one baseUrl, found {count('  baseUrl:')}")
    if count("  publishAssets:") != 1:
        die(f"expected exactly one publishAssets, found {count('  publishAssets:')}")
    if count('  publishAssets: "referenced"') != 1:
        die('publishAssets is not exactly "referenced"')
    if not any(line.strip() == '- ".obsidian/**"' for line in patched):
        die("ignorePatterns is missing .obsidian/**")

    temp = f"{args.file}.tmp"
    with open(temp, "w", encoding="utf-8") as handle:
        handle.write("\n".join(patched) + "\n")
    os.replace(temp, args.file)

    print(
        f"patched {args.file}: pageTitle={args.title!r} "
        f"baseUrl={args.base_url!r} ignore={len(globs)} "
        'publishAssets="referenced"'
    )


if __name__ == "__main__":
    main()
