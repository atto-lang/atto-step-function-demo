#!/usr/bin/env python3
"""Bounded, descriptor-bound compiler build-info parser; NOT compiler attestation."""
import json
import os
import stat
import sys

MAX_BYTES = 2048
PROTECTED = {"guest_execution", "build_mode"}


def reject(message):
    raise ValueError(message)


def pairs_no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            reject("duplicate JSON member, including Unicode-escaped aliases")
        result[key] = value
    return result


def reject_constants(value):
    reject("non-JSON numeric constant: " + value)


def validate(data):
    try:
        root = json.loads(
            data.decode("utf-8", errors="strict"),
            object_pairs_hook=pairs_no_duplicates,
            parse_constant=reject_constants,
        )
    except (UnicodeError, json.JSONDecodeError, ValueError) as exc:
        reject("malformed, duplicate or non-UTF8 JSON: " + str(exc))
    if not isinstance(root, dict):
        reject("root must be JSON object")
    if set(PROTECTED) - set(root):
        reject("missing protected build-info fields")
    if root["guest_execution"] is not True:
        reject("guest execution must be literal JSON true")
    mode = root["build_mode"]
    if not isinstance(mode, str) or not (1 <= len(mode) <= 128):
        reject("build mode must be nonempty string at most 128 characters")
    # Nested protected names are shadow authorities, even if no consumer
    # currently reads them. Check iteratively to avoid recursion dependence.
    stack = list(root.values())
    while stack:
        value = stack.pop()
        if isinstance(value, dict):
            if PROTECTED.intersection(value):
                reject("nested protected build-info field")
            stack.extend(value.values())
        elif isinstance(value, list):
            stack.extend(value)
    return True


def bounded_regular_file(path):
    if not all(hasattr(os, name) for name in ("O_NOFOLLOW", "O_NONBLOCK", "O_CLOEXEC")):
        reject("secure descriptor flags unavailable")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or not (1 <= before.st_size <= MAX_BYTES):
            reject("build-info is not a bounded regular file")
        data = bytearray()
        while len(data) <= MAX_BYTES:
            block = os.read(fd, MAX_BYTES + 1 - len(data))
            if not block:
                break
            data.extend(block)
            if len(data) > MAX_BYTES:
                reject("build-info exceeds 2048 bytes")
        after = os.fstat(fd)
        if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns,
            before.st_ctime_ns) != (after.st_dev, after.st_ino, after.st_size,
            after.st_mtime_ns, after.st_ctime_ns) or len(data) != before.st_size:
            reject("build-info changed during read")
        return bytes(data)
    finally:
        os.close(fd)


def main(argv):
    if len(argv) != 2:
        reject("expected exactly one compiler build-info file")
    validate(bounded_regular_file(argv[1]))
    print("BUILD_INFO_JSON_PASS (reported capability only; not attestation)")


if __name__ == "__main__":
    try:
        main(sys.argv)
    except (OSError, ValueError) as exc:
        print("BUILD_INFO_INVALID: " + str(exc), file=sys.stderr)
        sys.exit(1)
