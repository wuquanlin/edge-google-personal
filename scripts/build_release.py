#!/usr/bin/env python3
"""Build source and Windows ZIPs from explicit allowlists, using only stdlib."""

import argparse
import base64
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "scripts/release-files.json"


def safe_name(name):
    parts = PurePosixPath(name).parts
    if not parts or PurePosixPath(name).is_absolute() or ".." in parts or "\\" in name or ":" in name:
        raise ValueError(f"Unsafe release path: {name}")
    return name


def validate(config):
    version = config["version"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Expected a numeric semantic version")
    manifest = json.loads((ROOT / "EdgeGooglePersonal/Extension/manifest.json").read_text(encoding="utf-8-sig"))
    if version != manifest["version"]:
        raise ValueError("Release and extension versions differ")
    key_hash = hashlib.sha256(base64.b64decode(manifest["key"], validate=True)).hexdigest()[:32]
    extension_id = "".join(chr(ord("a") + int(n, 16)) for n in key_hash)
    if extension_id != "fnbpglchnbbhcmjcoapbafejooijecah":
        raise ValueError("Fixed extension identity changed")
    if (ROOT / "EdgeGooglePersonal/extension-id.txt").read_text(encoding="utf-8-sig").strip() != extension_id:
        raise ValueError("extension-id.txt does not match the public key")
    baseline = json.loads((ROOT / "docs/runtime-sha256.json").read_text(encoding="utf-8"))
    if baseline["version"] != version or set(baseline["files"]) != set(config["runtimeFiles"]):
        raise ValueError("Runtime baseline and release list differ")
    for name, expected in baseline["files"].items():
        file = ROOT / "EdgeGooglePersonal" / safe_name(name)
        if file.is_symlink() or hashlib.sha256(file.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Verified runtime file changed: {name}")


def archive(destination, entries, timestamp):
    names = [name for name, _ in entries]
    if len(set(names)) != len(names):
        raise ValueError("Duplicate archive paths")
    pending = destination.with_suffix(".zip.tmp")
    try:
        with zipfile.ZipFile(pending, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for name, source in sorted(entries):
                safe_name(name)
                if source.is_symlink() or not source.is_file():
                    raise ValueError(f"Release input is not a regular file: {source.name}")
                info = zipfile.ZipInfo(name, date_time=tuple(timestamp))
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, source.read_bytes(), compresslevel=9)
        with zipfile.ZipFile(pending) as z:
            bad = z.testzip()
            if bad:
                raise ValueError(f"Archive CRC failed: {bad}")
        pending.replace(destination)
    finally:
        if pending.exists():
            pending.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    validate(config)
    args.output.mkdir(parents=True, exist_ok=True)

    runtime = ["EdgeGooglePersonal/" + safe_name(name) for name in config["runtimeFiles"]]
    runtime.append("EdgeGooglePersonal/" + safe_name(config["runtimeGuide"]))
    shared = [safe_name(name) for name in config["sharedFiles"]]
    source_only = [safe_name(name) for name in config["sourceOnlyFiles"]]
    source_entries = [("edge-google-personal/" + name, ROOT / name) for name in runtime + shared + source_only]
    windows_entries = [(name, ROOT / name) for name in runtime]
    windows_entries.extend(("EdgeGooglePersonal/" + name, ROOT / name) for name in shared)
    version = config["version"]
    artifacts = []
    for flavor, entries in [("source", source_entries), ("windows", windows_entries)]:
        target = args.output / f"EdgeGooglePersonal-{version}-{flavor}.zip"
        archive(target, entries, config["archiveTimestamp"])
        artifacts.append(target)
        print(f"Built {target.name}: {target.stat().st_size} bytes, {len(entries)} files")
    checksums = "".join(
        f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in sorted(artifacts)
    )
    (args.output / "SHA256SUMS.txt").write_text(checksums, encoding="ascii")
    print("Wrote SHA256SUMS.txt; no installed state was collected.")


if __name__ == "__main__":
    main()
