"""Safety regression tests for SUNO V2 manifest gating."""
import csv
from pathlib import Path
import tempfile
import unittest
import wave

from ml.tools.prepare_v2_manifest import DatasetPolicyError, build_manifest


class V2ManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.policy = Path(__file__).resolve().parents[1] / "config/v2_dataset_policy.json"
        self.rows = []

    def tearDown(self):
        self.temp.cleanup()

    def add(self, folder="a01_scream_loud", filename="x.wav", **fields):
        dest = self.root / folder / filename
        dest.parent.mkdir(exist_ok=True)
        with wave.open(str(dest), "wb") as output:
            output.setparams((1, 2, 16000, 800, "NONE", "not compressed"))
            output.writeframes(b"\0" * 1600)
        row = dict(relative_path=f"{folder}/{filename}", review_status="approved",
                   reviewer="human", source_group="speaker-event-1", license="CC0",
                   false_negative_review="pass", original_split="")
        row.update(fields)
        self.rows.append(row)

    def build(self):
        path = self.root / "review.csv"
        with path.open("w", newline="") as output:
            writer = csv.DictWriter(output, fieldnames=self.rows[0].keys())
            writer.writeheader()
            writer.writerows(self.rows)
        return build_manifest(self.root, path, self.policy)

    def test_scream_candidate_after_approval(self):
        self.add()
        self.assertEqual(self.build()[0]["class_label"], "scream_loud")

    def test_glass_candidate_after_approval(self):
        self.add(folder="a03_glass_break")
        self.assertEqual(self.build()[0]["class_label"], "glass_break")

    def test_unreviewed_never_trains(self):
        self.add(review_status="pending")
        self.assertEqual(self.build(), [])

    def test_help_and_gunshot_are_disabled(self):
        for folder in ("a02_help_shout", "a06_gunshot_blast"):
            self.rows.clear()
            self.add(folder=folder)
            with self.assertRaises(DatasetPolicyError):
                self.build()

    def test_alarm_and_crash_are_disabled(self):
        for folder in ("a04_crash_heavy", "a05_alarm_home"):
            self.rows.clear()
            self.add(folder=folder)
            with self.assertRaises(DatasetPolicyError):
                self.build()

    def test_ambiguous_negatives_require_special_review(self):
        self.add(folder="n01_scream_light", false_negative_review="")
        with self.assertRaises(DatasetPolicyError):
            self.build()

    def test_grouped_augmentations_cannot_split(self):
        self.add(filename="one.wav")
        self.add(filename="two.wav", source_group="speaker-event-1")
        a, b = self.build()
        self.assertEqual(a["split"], b["split"])

    def test_evaluation_audio_rejected(self):
        self.add(original_split="original_evaluation")
        with self.assertRaises(DatasetPolicyError):
            self.build()


if __name__ == "__main__":
    unittest.main()
