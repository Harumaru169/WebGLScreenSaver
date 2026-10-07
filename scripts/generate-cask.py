#!/usr/bin/env python3
"""Generate a Cask from the exact release ZIP (optionally into a local Tap)."""
import argparse
import hashlib
from pathlib import Path
import re


def generate(version, archive, output):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Version must have the form X.Y.Z")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    template = Path(__file__).resolve().parents[1] / "homebrew/webgl-screen-saver.rb.in"
    content = template.read_text().replace("@VERSION@", version).replace("@SHA256@", digest)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content)
    return digest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(generate(args.version, args.archive, args.output))
