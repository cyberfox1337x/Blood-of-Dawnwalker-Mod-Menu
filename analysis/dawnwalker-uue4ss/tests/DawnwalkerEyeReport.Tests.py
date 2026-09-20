"""Bounded native report transport envelope checks; no runtime access."""
import importlib.util
from pathlib import Path
import tempfile
import unittest


def cyberfox1337x(module_name):
    return module_name


cyberfox1337x("dawnwalker_eye_report_tests")
spec = importlib.util.spec_from_file_location("eye_report", Path(__file__).parents[1] / "probes" / "DawnwalkerEyeReport.py")
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
NONCE = "a" * 32
PILOT = f"""[DawnwalkerEyeNativePilot] report_begin boot_id=123-456 nonce={NONCE} operation=observe
eye_pilot.schema=2
eye_pilot.boot_id=123-456
eye_pilot.nonce={NONCE}
eye_pilot.operation=observe
eye_pilot.ok=true
eye_pilot.gameplay_verified=false
eye_pilot.production_capabilities=none
eye_pilot.native.slots.1.value.R=0.125
eye_pilot.native.reason=Literal%25Percent%0ALine
[DawnwalkerEyeNativePilot] report_end ok=true operation=observe gameplay_verified=false
"""
LEGACY = f"""[DawnwalkerRequestedReadOnly] report_begin boot_id=123-456 nonce={NONCE}
eye_discovery.mutation_authorized=false
eye_discovery.gameplay_verified=false
[DawnwalkerRequestedReadOnly] report_end ok=true mutation_authorized=false gameplay_verified=false
"""


class ReportTests(unittest.TestCase):
    def parse(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "log.txt"
            path.write_text(text, encoding="utf-8")
            return reader.read_reports(path)

    def test_native_preserves_strings_indexes_and_escapes(self):
        result = reader.summarize(self.parse(PILOT)[0])
        self.assertEqual(result["native"]["native"]["slots"]["1"]["value"]["R"], "0.125")
        self.assertEqual(result["native"]["native"]["reason"], "Literal%Percent\nLine")
        self.assertEqual(result["productionCapabilities"], [])

    def test_legacy_compatibility_and_mixed_log(self):
        records = self.parse(LEGACY + PILOT)
        self.assertEqual([reader.summarize(r)["schema"] for r in records], [1, 2])

    def test_v4_new_operations_require_schema_three(self):
        v4 = PILOT.replace("observe", "variant-observe")
        with self.assertRaises(ValueError):
            self.parse(v4)
        result = reader.summarize(self.parse(v4.replace("eye_pilot.schema=2", "eye_pilot.schema=3"))[0])
        self.assertEqual((result["schema"], result["operation"]), (3, "variant-observe"))

    def test_v5_scalar_operation_requires_schema_four(self):
        pilot = PILOT.replace("observe", "human-iris-pair-roundtrip")
        for schema in ("2", "3"):
            with self.subTest(schema=schema), self.assertRaises(ValueError):
                self.parse(pilot.replace("eye_pilot.schema=2", "eye_pilot.schema=" + schema))
        result = reader.summarize(self.parse(pilot.replace("eye_pilot.schema=2", "eye_pilot.schema=4"))[0])
        self.assertEqual((result["schema"], result["operation"]), (4, "human-iris-pair-roundtrip"))
        self.assertEqual(result["productionCapabilities"], [])
        self.assertFalse(result["gameplayVerified"])

    def test_v5_preserves_earlier_operations_and_rejects_unknown(self):
        for operation in reader.OPERATIONS | reader.V4_OPERATIONS:
            with self.subTest(operation=operation):
                result = reader.summarize(self.parse(PILOT.replace("observe", operation).replace("eye_pilot.schema=2", "eye_pilot.schema=4"))[0])
                self.assertEqual((result["schema"], result["operation"]), (4, operation))
        with self.assertRaises(ValueError):
            self.parse(PILOT.replace("observe", "unknown-eye-operation").replace("eye_pilot.schema=2", "eye_pilot.schema=4"))

    def test_mismatching_operation_rejected(self):
        with self.assertRaises(ValueError):
            self.parse(PILOT.replace("report_end ok=true operation=observe", "report_end ok=true operation=export"))

    def test_v6_preserves_exact_eight_operation_profile(self):
        for operation in reader.OPERATIONS | reader.V4_OPERATIONS | reader.V5_OPERATIONS:
            result = reader.summarize(self.parse(PILOT.replace("observe", operation).replace("eye_pilot.schema=2", "eye_pilot.schema=5"))[0])
            self.assertEqual((result["schema"], result["operation"]), (5, operation))
        with self.assertRaises(ValueError):
            self.parse(PILOT.replace("eye_pilot.schema=2", "eye_pilot.schema=9"))

    def test_v7_preserves_exact_operations_and_failed_capture_result(self):
        for operation in reader.OPERATIONS | reader.V4_OPERATIONS | reader.V5_OPERATIONS:
            text = PILOT.replace("observe", operation).replace("eye_pilot.schema=2", "eye_pilot.schema=6")
            text = text.replace("ok=true", "ok=false")
            result = reader.summarize(self.parse(text)[0])
            self.assertEqual((result["schema"], result["operation"]), (6, operation))
            self.assertFalse(result["operationOk"])

    def test_v8_preserves_exact_eight_operations_without_admitting_sessions(self):
        for operation in reader.OPERATIONS | reader.V4_OPERATIONS | reader.V5_OPERATIONS:
            text = PILOT.replace("observe", operation).replace("eye_pilot.schema=2", "eye_pilot.schema=7")
            self.assertEqual(reader.summarize(self.parse(text)[0])["schema"], 7)
        with self.assertRaises(ValueError):
            self.parse(PILOT.replace("observe", "session-start").replace("eye_pilot.schema=2", "eye_pilot.schema=7"))

    def test_v9_session_operations_require_their_new_schema(self):
        for operation in reader.V9_OPERATIONS:
            for schema in ("2", "3", "4", "5", "6", "7"):
                with self.subTest(operation=operation, schema=schema), self.assertRaises(ValueError):
                    self.parse(PILOT.replace("observe", operation).replace("eye_pilot.schema=2", "eye_pilot.schema=" + schema))
            result = reader.summarize(self.parse(PILOT.replace("observe", operation).replace("eye_pilot.schema=2", "eye_pilot.schema=8"))[0])
            self.assertEqual((result["schema"], result["operation"]), (8, operation))

    def test_mismatching_identity_rejected(self):
        for key, value in [("schema", "1"), ("nonce", "b" * 32), ("boot_id", "123-457"), ("ok", "false"), ("production_capabilities", "eyes")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.parse(__import__("re").sub(rf"eye_pilot\.{key}=.*", f"eye_pilot.{key}={value}", PILOT))

    def test_duplicate_and_incomplete_rejected(self):
        for bad in [PILOT.replace("eye_pilot.schema=2", "eye_pilot.schema=2\neye_pilot.schema=2"), PILOT[:PILOT.index("[DawnwalkerEyeNativePilot] report_end")]]:
            with self.assertRaises(ValueError):
                self.parse(bad)

    def test_nested_collision_rejected(self):
        with self.assertRaises(ValueError):
            reader.nested_fields({"eye_pilot.x": "1", "eye_pilot.x.y": "2"}, "eye_pilot")

    def test_oversized_record_rejected(self):
        with self.assertRaises(ValueError):
            self.parse(PILOT.replace("eye_pilot.schema=2", "eye_pilot.reason=" + "x" * 1048576 + "\neye_pilot.schema=2"))


if __name__ == "__main__":
    unittest.main()
