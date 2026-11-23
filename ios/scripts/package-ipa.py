#!/usr/bin/env python3
"""Package real device builds. These files intentionally need user re-signing."""
import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile

app = pathlib.Path(sys.argv[1]).resolve()
output = pathlib.Path(sys.argv[2]).resolve()
build = sys.argv[3] if len(sys.argv) > 3 else "1"
output.mkdir(parents=True, exist_ok=True)
with (app / "Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
binary = app / info["CFBundleExecutable"]
details = subprocess.check_output(["file", str(binary)], text=True).strip()
if "arm64" not in details or "Mach-O" not in details:
    raise SystemExit("Not an arm64 device application: " + details)
if info.get("DTPlatformName") != "iphoneos":
    raise SystemExit("Refusing to package a simulator build as an IPA")
report = {"build": build, "version": info["CFBundleShortVersionString"],
          "source_commit": os.environ.get("GITHUB_SHA"), "repository": os.environ.get("GITHUB_REPOSITORY"),
          "sdk": info.get("DTSDKName"), "xcode": info.get("DTXcode"),
          "minimum_ios": info.get("MinimumOSVersion"), "binary": details,
          "signed": False, "physical_device_tested": False, "artifacts": []}
for widget in (False, True):
    suffix = "with-widget" if widget else "self-sign"
    name = f"FluidMusic-iOS-{info['CFBundleShortVersionString']}-build{build}-{suffix}-unsigned.ipa"
    with tempfile.TemporaryDirectory() as temp:
        payload = pathlib.Path(temp) / "Payload"
        payload.mkdir()
        copied = payload / app.name
        shutil.copytree(app, copied, symlinks=True)
        for signature in copied.rglob("_CodeSignature"):
            if signature.is_dir(): shutil.rmtree(signature)
        for profile in copied.rglob("embedded.mobileprovision"): profile.unlink()
        if not widget:
            shutil.rmtree(copied / "PlugIns", ignore_errors=True)
            path = copied / "Info.plist"
            with path.open("rb") as stream: configuration = plistlib.load(stream)
            configuration["FluidMusicAppGroup"] = ""
            with path.open("wb") as stream: plistlib.dump(configuration, stream)
        artifact = output / name
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(payload), str(artifact)], check=True)
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        report["artifacts"].append({"name": name, "sha256": digest, "bytes": artifact.stat().st_size, "widget": widget})
(output / "build-info.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
(output / "SHA256SUMS.txt").write_text("".join(f"{x['sha256']}  {x['name']}\n" for x in report["artifacts"]))
print(json.dumps(report, ensure_ascii=False, indent=2))
