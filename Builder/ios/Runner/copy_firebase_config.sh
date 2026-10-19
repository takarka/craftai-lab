#!/bin/sh
set -eu
# Optional public Firebase configuration, supplied by the deployment environment.
config_path="$SRCROOT/Runner/GoogleService-Info.plist"
if [ -f "$config_path" ]; then
  install -m 644 "$config_path" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/GoogleService-Info.plist"
fi
