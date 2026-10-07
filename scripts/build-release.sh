#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export WEBGL_CI=1
version="${1:-1.0.0}"
build_number="${GITHUB_RUN_NUMBER:-1}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Version must have the form X.Y.Z' >&2
  exit 1
fi
mkdir -p dist
# Keep artifacts from a previous run from becoming part of a release.
if [[ -e dist/WebGLScreenSaver-arm64.zip ]]; then
  echo 'dist already contains a ZIP; move it elsewhere before building again.' >&2
  exit 1
fi
source_before="$(git diff HEAD --binary | shasum -a 256)"
xcodebuild -quiet -project WebGLScreenSaver.xcodeproj \
  -scheme AppexSaverMinimal -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath .build/ci \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= REGISTER_APP_GROUPS=NO WEBGL_CI=1 \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
  build 2>&1 | tee dist/build.log
if [[ "$source_before" != "$(git diff HEAD --binary | shasum -a 256)" ]]; then
  echo 'Build changed tracked source files.' >&2
  exit 1
fi
python3 scripts/package-release.py "$version" "$build_number"
ruby -c dist/webgl-screen-saver.rb
