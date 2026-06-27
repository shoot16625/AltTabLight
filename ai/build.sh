#!/bin/bash

# Build with adhoc-signing (no Apple Developer certificate needed).
# CURRENT_PROJECT_VERSION / MARKETING_VERSION must be passed explicitly
# because xcodebuild does not resolve Info.plist build-variables
# from the project file on all configurations.

xcodebuild \
  -project alt-tab-macos.xcodeproj \
  -scheme Debug \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  CURRENT_PROJECT_VERSION=1 \
  MARKETING_VERSION=6.0
