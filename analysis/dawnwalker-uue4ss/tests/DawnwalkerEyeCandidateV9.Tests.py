"""Pure issuer composition checks; never invoke the attestation or native host."""
import importlib.util
from pathlib import Path
import unittest


def cyberfox1337x(module_name):
    return module_name


cyberfox1337x("dawnwalker_eye_candidate_v9_tests")
SOURCE = Path(__file__).resolve().parents[1] / "probes/DawnwalkerEyeCandidateV9.py"
spec = importlib.util.spec_from_file_location("eye_candidate_v9", SOURCE)
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


class IssuerTests(unittest.TestCase):
    def setUp(self):
        self.previous = (candidate.FROZEN / "New-EyePilotAttestation.ps1").read_text(encoding="utf-8-sig")

    def test_exact_operations_schema_and_payloads(self):
        issuer = candidate.compose_issuer(self.previous)
        self.assertIn("$manifest.schema -ne 8 -or $manifest.revision -ne 9", issuer)
        self.assertIn("'schema=8'", issuer)
        self.assertIn("'session-start' = 'eye-session-start'; 'session-stop' = 'eye-session-stop'", issuer)
        self.assertEqual(2, issuer.count("DawnwalkerAppearanceSourcesV9.lua"))
        for leaf in candidate.EXTRA:
            self.assertEqual(2, issuer.count(leaf))
        self.assertNotIn("DawnwalkerAppearanceSources.lua", issuer)

    def test_only_start_creates_fixed_owner_channel_after_nonce(self):
        issuer = candidate.compose_issuer(self.previous)
        start = issuer.index("if ($Operation -ceq 'session-start')")
        self.assertGreater(start, issuer.index("$nonce = [Guid]::NewGuid().ToString('N')"))
        block = issuer[start:issuer.index("$issuedAt =", start)]
        self.assertIn("$channelDirectory = Join-Path $channelBootDirectory $nonce", block)
        self.assertEqual(2, block.count("Assert-EyeNoReparseAncestors -LiteralPath $channelDirectory"))
        self.assertIn("if (Test-Path -LiteralPath $channelDirectory)", block)
        self.assertNotIn("-Force | Out-Null", block)
        self.assertIn("Native channel is not empty".lower(), block.lower())

    def test_modified_insertion_points_refuse_composition(self):
        for before, after in [("'schema=7'", "'schema=6'"),
            ("'human-iris-pair-roundtrip')]", "'unknown')]"),
            ("$nonce = [Guid]::NewGuid().ToString('N')", "$nonce = 'fixed'")]:
            with self.subTest(before=before), self.assertRaises(ValueError):
                candidate.compose_issuer(self.previous.replace(before, after))

    def test_preserves_appearance_and_matches_cleanup_reserve(self):
        self.assertNotIn("DawnwalkerPrivateEyePreviewProbe.lua", candidate.REPLACEMENTS)
        self.assertEqual("DawnwalkerPrivateEyeRendererV9.lua", candidate.EXTRA_SOURCES["DawnwalkerPrivateEyeRenderer.lua"])
        profile = candidate.SESSION_PROFILE
        self.assertEqual((64, 8, 300000, 30000), (profile["maximumResponses"], profile["cleanupReserveResponses"],
            profile["maximumHostLifetimeMs"], profile["cleanupReserveMs"]))
        self.assertFalse(profile["restoresOnStop"] or profile["productionReady"] or profile["producesUnrequestedFrames"])


if __name__ == "__main__":
    unittest.main()
