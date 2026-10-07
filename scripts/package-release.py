#!/usr/bin/env python3
"""Sign inside out, verify the unpacked ZIP, and record build provenance."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

from importlib.util import spec_from_file_location, module_from_spec

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
APP = ROOT / ".build/ci/Build/Products/Release/WebGLScreenSaver.app"
EXTENSION = "Contents/PlugIns/WebGLScreenSaverExtension.appex"
ENTITLEMENTS = {
    "": ROOT / "WebGLScreenSaver/WebGLScreenSaver.entitlements",
    EXTENSION: ROOT / "WebGLScreenSaverExtension/WebGLScreenSaverExtension.entitlements",
}


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], stderr=subprocess.STDOUT).decode()


def verify(app, version, build_number):
    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", app)
    if list(app.rglob("*.provisionprofile")) or list(app.rglob("*.mobileprovision")):
        raise RuntimeError("Provisioning profile found in distribution bundle")
    for relative, entitlement_path in ENTITLEMENTS.items():
        bundle = app / relative
        info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
        expected_id = "kosei.haruyama.WebGLScreenSaver" + (".Extension" if relative else "")
        assert info["CFBundleIdentifier"] == expected_id
        assert info["CFBundleShortVersionString"] == version
        assert info["CFBundleVersion"] == build_number
        assert info["LSMinimumSystemVersion"] == "26.0"
        if relative:
            assert info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.screensaver"
        arch = run("lipo", "-archs", bundle / "Contents/MacOS" / info["CFBundleExecutable"])
        assert arch.strip() == "arm64", arch
        signature = run("codesign", "-dv", "--verbose=4", bundle)
        assert "Signature=adhoc" in signature and "TeamIdentifier=not set" in signature
        if not relative:
            assert "runtime" in signature
        result = subprocess.run(
            ["codesign", "-d", "--entitlements", "-", "--xml", str(bundle)],
            capture_output=True, check=True,
        )
        assert plistlib.loads(result.stdout) == plistlib.loads(entitlement_path.read_bytes())
        for resource in ("ShaderRuntime.html", "DefaultShader.glsl"):
            assert (bundle / "Contents/Resources" / resource).is_file()


def main():
    version, build_number = sys.argv[1:]
    assert APP.is_dir(), APP
    nested = [p for p in APP.rglob("*") if not p.is_symlink() and (
        p.suffix in (".framework", ".appex", ".xpc", ".app", ".dylib")
    )]
    for bundle in sorted(nested, key=lambda p: len(p.parts), reverse=True) + [APP]:
        command = ["codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der"]
        relative = str(bundle.relative_to(APP)) if bundle != APP else ""
        if relative in ENTITLEMENTS:
            command += ["--entitlements", str(ENTITLEMENTS[relative])]
        if bundle == APP:
            command += ["--options", "runtime"]
        print(run(*command, bundle), end="")
    verify(APP, version, build_number)
    archive = DIST / "WebGLScreenSaver-arm64.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", APP, archive)
    with tempfile.TemporaryDirectory(prefix="webgl-verify-") as temporary:
        run("ditto", "-x", "-k", archive, temporary)
        verify(Path(temporary) / APP.name, version, build_number)
    spec = spec_from_file_location("generate_cask", ROOT / "scripts/generate-cask.py")
    generator = module_from_spec(spec)
    spec.loader.exec_module(generator)
    digest = generator.generate(version, archive, DIST / "webgl-screen-saver.rb")
    (DIST / "SHA256SUMS").write_text(f"{digest}  {archive.name}\n")
    metadata = {
        "version": version, "build_number": build_number, "sha256": digest,
        "commit": run("git", "rev-parse", "HEAD").strip(),
        "source_dirty": bool(run("git", "status", "--porcelain", "--untracked-files=normal").strip()),
        "xcode": run("xcodebuild", "-version").strip(),
        "sdk": run("xcrun", "--show-sdk-version").splitlines()[-1],
        "os": run("sw_vers").strip(),
        "runner_image": os.environ.get("ImageVersion"),
        "run_url": (f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/"
                    f"{os.environ['GITHUB_RUN_ID']}" if "GITHUB_RUN_ID" in os.environ else None),
        "dependencies": json.loads((ROOT / "WebGLScreenSaver.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text()),
    }
    (DIST / "build-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Verified {archive.name}: {digest}")


if __name__ == "__main__":
    main()
