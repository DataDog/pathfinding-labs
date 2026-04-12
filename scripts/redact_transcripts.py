#!/usr/bin/env python3
"""
Redact sensitive data from demo transcript files before committing them.

Removes or replaces:
  - AWS access key IDs (AKIA...)
  - AWS secret access keys (by context: key=value patterns)
  - AWS session tokens (by context)
  - AWS account IDs (12-digit numbers in ARNs or adjacent to known keywords)

Usage:
    # Redact a single file in-place:
    python redact_transcripts.py transcript.txt

    # Redact a directory of .txt files in-place:
    python redact_transcripts.py /tmp/demos-raw/

    # Write redacted files to a different directory:
    python redact_transcripts.py /tmp/demos-raw/ --output-dir pathfinding.cloud/docs/labs/demo-transcripts/

    # Preview changes without writing:
    python redact_transcripts.py transcript.txt --dry-run
"""

import argparse
import difflib
import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Redaction patterns
# ---------------------------------------------------------------------------

# AWS access key IDs: AKIA[A-Z0-9]{16}  (also ASIA... for session credentials)
PATTERN_ACCESS_KEY_ID = re.compile(
    r'\b(AKIA|ASIA|AROA|AIDA|ANPA|ANVA|APKA)[A-Z0-9]{16}\b'
)
REPLACEMENT_ACCESS_KEY_ID = "AKIAXXXXXXXXXXXXXXXXXX"

# Secret access key: 40-char base64-ish string following known context keywords.
# Matches lines like:  AWS_SECRET_ACCESS_KEY=xxxx  or  "SecretAccessKey": "xxxx"
PATTERN_SECRET_KEY = re.compile(
    r'(?i)(aws_secret_access_key\s*[=:]\s*["\']?)([A-Za-z0-9/+]{40})(["\']?)'
)
PATTERN_SECRET_KEY_JSON = re.compile(
    r'(?i)("SecretAccessKey"\s*:\s*")([A-Za-z0-9/+]{40})(")'
)
REPLACEMENT_SECRET_KEY = r'\g<1>XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\g<3>'

# Session token: long base64 string (100+ chars) following context keywords.
PATTERN_SESSION_TOKEN = re.compile(
    r'(?i)(aws_session_token\s*[=:]\s*["\']?)([A-Za-z0-9/+=]{100,})(["\']?)'
)
PATTERN_SESSION_TOKEN_JSON = re.compile(
    r'(?i)("SessionToken"\s*:\s*")([A-Za-z0-9/+=]{100,})(")'
)
REPLACEMENT_SESSION_TOKEN = r'\g<1>[SESSION_TOKEN_REDACTED]\g<3>'

# Account IDs in ARNs: arn:aws:...:123456789012:...
PATTERN_ARN_ACCOUNT_ID = re.compile(
    r'(arn:aws(?:-cn|-us-gov)?:[a-z0-9\-]*:[a-z0-9\-]*:)(\d{12})(:)'
)
REPLACEMENT_ARN_ACCOUNT_ID = r'\g<1>123456789012\g<3>'

# Bare 12-digit account IDs adjacent to AWS-context keywords.
# This is intentionally conservative — 12-digit numbers are common, so we
# only replace them when preceded by known AWS terms.
PATTERN_BARE_ACCOUNT_ID = re.compile(
    r'(?i)(?:account.id|account_id|accountid|aws.account)["\s:=]+(\d{12})\b'
)
REPLACEMENT_BARE_ACCOUNT_ID_PREFIX = lambda m: m.group(0).replace(m.group(1), "123456789012")

# All patterns in order (most-specific first to avoid double-replacement)
PATTERNS = [
    # Access key IDs (simple replacement)
    (PATTERN_ACCESS_KEY_ID, REPLACEMENT_ACCESS_KEY_ID, 'access_key_id'),
    # Secret keys
    (PATTERN_SECRET_KEY, REPLACEMENT_SECRET_KEY, 'secret_key'),
    (PATTERN_SECRET_KEY_JSON, REPLACEMENT_SECRET_KEY, 'secret_key_json'),
    # Session tokens
    (PATTERN_SESSION_TOKEN, REPLACEMENT_SESSION_TOKEN, 'session_token'),
    (PATTERN_SESSION_TOKEN_JSON, REPLACEMENT_SESSION_TOKEN, 'session_token_json'),
    # Account IDs in ARNs
    (PATTERN_ARN_ACCOUNT_ID, REPLACEMENT_ARN_ACCOUNT_ID, 'arn_account_id'),
]


def redact_text(text: str) -> tuple[str, dict[str, int]]:
    """Apply all redaction patterns to text.

    Returns (redacted_text, counts) where counts maps pattern name -> match count.
    """
    counts: dict[str, int] = {}
    result = text

    for pattern, replacement, name in PATTERNS:
        new_result, n = pattern.subn(replacement, result)
        if n:
            counts[name] = counts.get(name, 0) + n
        result = new_result

    # Bare account IDs need a callable replacement
    new_result, n = PATTERN_BARE_ACCOUNT_ID.subn(REPLACEMENT_BARE_ACCOUNT_ID_PREFIX, result)
    if n:
        counts['bare_account_id'] = n
    result = new_result

    return result, counts


def redact_file(input_path: Path, output_path: Path, dry_run: bool = False) -> bool:
    """Redact a single transcript file.

    Returns True if any changes were made.
    """
    try:
        original = input_path.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        print(f"  ERROR reading {input_path}: {e}", file=sys.stderr)
        return False

    redacted, counts = redact_text(original)
    changed = redacted != original

    if not changed:
        print(f"  {input_path.name}: clean (no sensitive data found)")
        return False

    print(f"  {input_path.name}: redacted {sum(counts.values())} item(s): {counts}")

    if dry_run:
        # Show a unified diff of the changes
        diff = difflib.unified_diff(
            original.splitlines(keepends=True),
            redacted.splitlines(keepends=True),
            fromfile=f"a/{input_path.name}",
            tofile=f"b/{input_path.name}",
            n=2,
        )
        diff_text = "".join(diff)
        if diff_text:
            print(diff_text)
        return True

    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(redacted, encoding="utf-8")
        print(f"    Written to: {output_path}")
    except Exception as e:
        print(f"  ERROR writing {output_path}: {e}", file=sys.stderr)
        return False

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Redact sensitive AWS credentials from demo transcript files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "input", metavar="PATH",
        help="File or directory of .txt transcript files to redact",
    )
    parser.add_argument(
        "--output-dir", metavar="DIR",
        help="Write redacted files here instead of modifying in-place. "
             "When redacting a directory, filenames are preserved.",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print what would be changed without writing any files",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    output_dir = Path(args.output_dir) if args.output_dir else None

    if not input_path.exists():
        print(f"ERROR: {input_path} does not exist", file=sys.stderr)
        sys.exit(1)

    if input_path.is_file():
        files = [input_path]
    else:
        files = sorted(input_path.glob("*.txt"))
        if not files:
            print(f"No .txt files found in {input_path}", file=sys.stderr)
            sys.exit(1)

    print(f"Redacting {len(files)} file(s)" + (" (dry-run)" if args.dry_run else "") + "...")

    changed = 0
    for f in files:
        if output_dir:
            dest = output_dir / f.name
        else:
            dest = f  # in-place
        if redact_file(f, dest, dry_run=args.dry_run):
            changed += 1

    print(f"\nDone: {changed}/{len(files)} file(s) had sensitive data redacted.")
    if args.dry_run and changed:
        print("(dry-run: no files written)")


if __name__ == "__main__":
    main()
