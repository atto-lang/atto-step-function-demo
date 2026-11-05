#!/usr/bin/env python3
"""Source-owned adversarial tests for ci/verify-build-info.sh (host only).

Run: python3 ci/validate_build_info_wave55.py
This checks parser admission, NOT the legitimacy of any compiler binary,
durable workflow replay, or actual AttoLang guest execution.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

VERIFY = Path(__file__).resolve().parent / "verify-build-info.sh"


@unittest.skipUnless(shutil.which("python3"), "Python 3 required by production verifier")
class BuildInfoAdmission(unittest.TestCase):
    def check(self, payload, accepted):
        with tempfile.TemporaryDirectory(prefix="workflow-build-info-") as tmp:
            path = Path(tmp) / "build-info.json"
            path.write_bytes(payload if isinstance(payload, bytes) else payload.encode("utf-8"))
            result = subprocess.run(
                ["sh", str(VERIFY), str(path)], capture_output=True, timeout=5,
                check=False)
            if accepted:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(b"BUILD_INFO_JSON_PASS", result.stdout)
            else:
                self.assertNotEqual(result.returncode, 0, payload)
                self.assertNotIn(b"BUILD_INFO_JSON_PASS", result.stdout)

    def test_accepted_minimal_and_escaped_unprotected_keys(self):
        for value in (
            '{"build_mode":"native","guest_execution":true}',
            '{"guest_execution":true,"build_mode":"native","other":{"mode":"not used"}}',
            '{"build_mode":"a","guest_execution":true,"unknown":null}',
        ):
            with self.subTest(value=value):
                self.check(value, True)

    def test_boolean_type_forgery_and_syntax_fail(self):
        for value in (
            '{"build_mode":"native","guest_execution":false}',
            '{"build_mode":"native","guest_execution":"true"}',
            '{"build_mode":"native","guest_execution":1}',
            '{"build_mode":null,"guest_execution":true}',
            '{"build_mode":"","guest_execution":true}',
            '{"build_mode":"native","guest_execution":true} trailing',
            '{"build_mode":"native","guest_execution":',
        ):
            with self.subTest(value=value):
                self.check(value, False)

    def test_duplicate_and_nested_authority_rejected(self):
        for value in (
            '{"build_mode":"native","build_mode":"fake","guest_execution":true}',
            '{"build_mode":"native","guest_execution":false,"guest_execution":true}',
            '{"build_mode":"native","guest_execution":true,"guest_executi\\u006fn":true}',
            '{"build_mode":"native","guest_execution":true,"nested":{"guest_execution":false}}',
            '{"build_mode":"native","guest_execution":true,"nested":{"build_mode":"fake"}}',
            '{"build_mode":"native","guest_execution":true,"nested":[{"guest_execution":true}]}',
        ):
            with self.subTest(value=value):
                self.check(value, False)

    def test_invalid_utf8_and_oversized_payload_fail(self):
        self.check(b'{"build_mode":"native","guest_execution":true}\xff', False)
        self.check('{"build_mode":"' + 'x' * 2100 + '","guest_execution":true}', False)

    def test_symlink_does_not_read_target(self):
        with tempfile.TemporaryDirectory(prefix="workflow-build-info-") as tmp:
            target = Path(tmp) / "target"
            target.write_text('{"build_mode":"native","guest_execution":true}')
            alias = Path(tmp) / "alias"
            alias.symlink_to(target)
            result = subprocess.run(["sh", str(VERIFY), str(alias)],
                                    capture_output=True, timeout=5, check=False)
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
