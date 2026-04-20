# Demo Transcript Pipeline

Scripts for capturing, sanitizing, and publishing demo transcripts for pathfinding-labs scenarios. Transcripts are displayed in the pathfinding.cloud game mode via the **Run Simulated Demo** button (or press **D** while playing).

## Overview

```
capture_demos.py      — one-stop wrapper for the full pipeline
run_demos.py          — runs demo_attack.sh scripts, saves raw output to /tmp
redact_transcripts.py — strips credentials and account IDs from raw files
```

---

## Full Pipeline (recommended)

```bash
cd pathfinding-labs

# Run demos for all currently enabled+deployed scenarios, redact, publish, update JSON
python scripts/capture_demos.py

# Preview what would run without executing anything
python scripts/capture_demos.py --dry-run

# Run with more parallelism (default is 4 concurrent workers)
python scripts/capture_demos.py --workers 8

# Skip running cleanup_attack.sh after each demo
python scripts/capture_demos.py --no-cleanup

# Skip re-running demos — re-use raw files already in /tmp from a previous run
python scripts/capture_demos.py --skip-run

# Skip regenerating pathfinding.cloud JSON at the end
python scripts/capture_demos.py --skip-json

# Re-run demos that already have a transcript in pathfinding.cloud (default: skip them)
python scripts/capture_demos.py --force
```

The pipeline does:
1. Queries `plabs status` to find enabled scenarios
2. Runs `demo_attack.sh` for each concurrently → `/tmp/pathfinding-demos-raw/{slug}.txt`
3. Redacts account IDs and credentials → `pathfinding.cloud/docs/labs/demo-transcripts/{slug}.txt`
4. Runs `generate-labs-json.py` so `hasDemoTranscript` is updated in the frontend

---

## Running Specific Labs

```bash
# Run and capture demos for specific labs only
python scripts/run_demos.py --labs iam-001 sts-001 --output-dir /tmp/demos-raw/

# See what slugs are available
python scripts/run_demos.py --list

# Run all labs that have a demo script (not just enabled ones)
python scripts/run_demos.py --all --output-dir /tmp/demos-raw/ --workers 6
```

---

## Redacting Only

Useful if you already have raw captures and just need to sanitize them.

```bash
# Redact a directory of raw files, write to pathfinding.cloud
python scripts/redact_transcripts.py /tmp/pathfinding-demos-raw/ \
  --output-dir ../pathfinding.cloud/docs/labs/demo-transcripts/

# Preview what would be redacted without writing
python scripts/redact_transcripts.py /tmp/pathfinding-demos-raw/ --dry-run

# Redact a single file in-place
python scripts/redact_transcripts.py /tmp/pathfinding-demos-raw/iam-001.txt
```

---

## After Capturing

```bash
# Regenerate the labs JSON so the frontend picks up new transcripts
cd pathfinding.cloud
python scripts/generate-labs-json.py --source-dir ../pathfinding-labs

# Verify locally
cd docs && python3 dev-server.py
# Open http://localhost:8888, navigate to a lab, open menu -> Run Simulated Demo
# Or press D while playing
```

---

## Transcript File Naming

Transcript filenames match pathfinding.cloud URL slugs, not plabs UniqueIDs:

| plabs UniqueID | Transcript filename |
|---|---|
| `iam-001-to-admin` | `iam-001.txt` |
| `sts-001-to-admin` | `sts-001.txt` |
| `iam-002-to-bucket` | `iam-002-to-bucket.txt` |

`to-admin` is dropped from the filename (it's the default target). `to-bucket` is kept because it disambiguates from the `to-admin` variant of the same lab.

---

## What Gets Redacted

The redaction script removes:
- AWS access key IDs (`AKIA...`, `ASIA...`)
- AWS secret access keys (matched by context)
- Session tokens (matched by context)
- Account IDs inside ARNs (`arn:aws:...:123456789012:...`)
- Bare account IDs adjacent to known AWS keywords
