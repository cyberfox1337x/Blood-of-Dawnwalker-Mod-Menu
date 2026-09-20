"""Cleanup evidence identity, budget and actual-frame regressions; no game access."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


def cyberfox1337x(module_name):
    return module_name


cyberfox1337x("dawnwalker_eye_cleanup_report_tests")
SOURCE = Path(__file__).parents[1] / "probes"
sys.path.insert(0, str(SOURCE))
spec = importlib.util.spec_from_file_location("eye_cleanup", SOURCE / "DawnwalkerEyeCleanupReport.py")
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
NONCE = "a" * 32


def receipt(frames=1, complete=True):
    fields = {"schema": "5", "boot_id": "100-123", "nonce": NONCE, "operation": "private-preview-roundtrip",
              "requested_frames": str(frames), "mutation_authorized": "false", "gameplay_verified": "false",
              "production_capabilities": "none", "schedule.requested_frames": str(frames),
              "schedule.schedule_complete": str(complete).lower(), "schedule.started_frame": "100",
              "schedule.observed_frame": str(100 + frames), "schedule.elapsed_frames": str(frames),
              "observation.kind": "native-private-preview-cleanup-observation", "observation.schema": "1",
              "observation.boot_id": "100-123", "observation.nonce": NONCE, "observation.after_frames": str(frames),
              "observation.actor_state.valid": "true", "observation.actor_state.actor_invalidated": "false"}
    return (f"[DawnwalkerEyeCleanupObservation] report_begin boot_id=100-123 nonce={NONCE} operation=private-preview-roundtrip after_frames={frames}\n"
            + "\n".join("eye_cleanup." + key + "=" + value for key, value in fields.items())
            + f"\n[DawnwalkerEyeCleanupObservation] report_end operation=private-preview-roundtrip after_frames={frames} gameplay_verified=false\n")


class CleanupTests(unittest.TestCase):
    def parse(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "log.txt"
            path.write_text(text, encoding="utf-8")
            return reader.read_observations(path, NONCE)

    def test_three_frames_preserve_native_states_without_inventing_success(self):
        result = self.parse(receipt(30) + receipt(1) + receipt(3))
        self.assertTrue(result["allScheduledObservationsPresent"])
        self.assertEqual([item["afterFrames"] for item in result["observations"]], [1, 3, 30])
        self.assertEqual(result["observations"][0]["native"]["observation"]["actor_state"]["actor_invalidated"], "false")
        self.assertNotIn("cleanupConfirmed", result)

    def test_partial_incomplete_observation_is_explicit(self):
        result = self.parse(receipt(1, False))
        self.assertFalse(result["allScheduledObservationsPresent"])
        self.assertEqual(result["observations"][0]["native"]["schedule"]["schedule_complete"], "false")

    def test_v7_schema_preserved_without_mixing_candidate_generations(self):
        v7 = receipt(1).replace("eye_cleanup.schema=5", "eye_cleanup.schema=6")
        result = self.parse(v7)
        self.assertEqual(result["observations"][0]["native"]["schema"], "6")
        with self.assertRaises(ValueError):
            self.parse(v7 + receipt(3))

    def test_v8_preserves_original_cleanup_observation_result(self):
        result = self.parse(receipt(1, False).replace("eye_cleanup.schema=5", "eye_cleanup.schema=7"))
        self.assertEqual(result["observations"][0]["native"]["schema"], "7")
        self.assertEqual(result["observations"][0]["native"]["schedule"]["schedule_complete"], "false")

    def test_identity_and_claim_tampering_rejected(self):
        for old, new in [("eye_cleanup.nonce=" + NONCE, "eye_cleanup.nonce=" + "b" * 32),
                         ("eye_cleanup.schema=5", "eye_cleanup.schema=4"),
                         ("eye_cleanup.mutation_authorized=false", "eye_cleanup.mutation_authorized=true"),
                         ("eye_cleanup.observation.after_frames=1", "eye_cleanup.observation.after_frames=3")]:
            with self.subTest(old=old), self.assertRaises(ValueError):
                self.parse(receipt().replace(old, new))

    def test_actual_frame_count_mismatch_rejected(self):
        for text in [receipt(3).replace("observed_frame=103", "observed_frame=101"),
                     receipt().replace("elapsed_frames=1", "elapsed_frames=121"),
                     receipt().replace("started_frame=100", "started_frame=nil")]:
            with self.assertRaises(ValueError):
                self.parse(text)

    def test_duplicate_truncated_nested_and_oversized_rejected(self):
        for text in [receipt() + receipt(), receipt().split("[DawnwalkerEyeCleanupObservation] report_end")[0],
                     receipt().split("eye_cleanup.schema=5")[0] + receipt(),
                     receipt().replace("eye_cleanup.schema=5", "eye_cleanup.reason=" + "x" * 65536 + "\neye_cleanup.schema=5")]:
            with self.assertRaises(ValueError):
                self.parse(text)


if __name__ == "__main__":
    unittest.main()
