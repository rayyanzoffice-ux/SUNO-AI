# SUNO V2: A-folder corrective implementation (22 October 2026)

This branch implements the uploaded "rayyan work for A Folders" guidance as a **non-shipping ML training safety policy**. Existing main-branch Android models, metadata, and alert logic remain unchanged.

## Audited Google Drive curation (already performed)

The Drive root `SUNO_dataset` has `SUNO_A_V2_LABEL_POLICY.json` and `SUNO_A_V2_CURATED_STATUS_20261022.md`. The current curated tree includes 134 candidate A01 screams and 150 candidate A03 glass sounds; A02 has no approved help shouting; A04 has two same-source provisional effects; A05 has seven provisional alarms; A06 is excluded under `_A_V2_QUARANTINE_DO_NOT_TRAIN_20261022`. These counts are **not verified emergency-event counts** and **not approval to train**.

| Folder | V2 decision | Remaining action |
| --- | --- | --- |
| a01_scream_loud | Candidate | Human listening: move only genuinely light/playful screams to N01; group augmentations with parent |
| a02_help_shout | Disabled | Record 5+ consenting voices urgently saying **help, bachao, madad, chhor do** at 2–3 distances and 2–3 takes each; confirm urgency, avoid dangerous staged public incidents |
| a03_glass_break | Candidate | Review for background human speech; trim without removing the glass event, or quarantine |
| a04_crash_heavy | Disabled | Old keyword-matched clips rejected; source **genuine audible crashes** and verify by ear; re-record clean legally licensed effects through demo phone at 1m/3m |
| a05_alarm_home | Disabled | Source literal smoke detector, fire alarm, intruder alarm or car-theft alarm. **Never** treat passing police/ambulance/outdoor sirens as positives |
| a06_gunshot_blast | Disabled | Phase 2; never train on weak gunshot samples in this V2 |

## Train-data gate

`ml/config/v2_dataset_policy.json` records what is enabled or excluded. `ml/tools/prepare_v2_manifest.py` **only accepts human-reviewed** WAVs that are 16 kHz, mono, 16-bit PCM and rejects disabled classes, evaluation-source leakage, missing source/license metadata and unsafe negatives. Source event, speaker/session, and all augmentations **must use the same** `source_group`; group-derived splits prevent leakage.

Prepare a human-listening review CSV with header:

```csv
relative_path,review_status,reviewer,source_group,license,false_negative_review,original_split
```

The only training-eligible `review_status` is `approved`. For n01/n02/n06/n07/n10/n18 also require `false_negative_review=pass`; ensure genuinely urgent sounds are not mislabeled as safe. Running the script with only pending reviews produces an empty manifest.

```bash
python -m unittest discover -s ml/tests -p 'test_*.py'
python ml/tools/prepare_v2_manifest.py --dataset-root /path/to/SUNO_dataset --reviews /path/to/human_review.csv --out /path/to/v2_training_manifest.csv
```

## Next replacement-audio sources — candidates only, not imported or approved

- [CC0 house smoke detector](https://bigsoundbank.com/smoke-detector-alarm-s0800.html), [another CC0 smoke detector](https://bigsoundbank.com/smoke-detector-alarm-3-s1153.html)
- [Public-domain smoke alarm](https://commons.wikimedia.org/wiki/File:Smoke_alarm.ogg)
- [CC BY-SA actual fire alarm](https://commons.wikimedia.org/wiki/File:Activated_fire_alarm_(sound).ogg)
- [FSD50K](https://zenodo.org/records/4060432) is weakly clip-labeled and carries **per-source CC terms**; a broad `Alarm` annotation is not proof of a home alarm

Download limitations and lack of in-person phone recording mean those sources have **not** yet been verified as training positives.

## Critical runtime compatibility rule

On `main`, `assets/ml/suno_audio_classifier.tflite` and `assets/ml/labels.json` still define a **four-output head**: `ambient_safe`, `distress_voice`, `alarm_siren`, `breaking_crash`. This V2 proposal is a **three-output head**: `ambient_safe`, `scream_loud`, `glass_break`.

**Do not merely swap the label JSON or deploy a new APK.** Retrain the TFLite head, verify ordered output tensors, adjust Dart prediction mapping and risk engine, measure held-out precision/recall and false alerts per device-day on real phones, then do end-to-end Safety Check and notification checks. No claim of 95%+ accuracy is justified yet.
