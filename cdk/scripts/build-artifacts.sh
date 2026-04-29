#!/usr/bin/env bash
# Baut alle drei Lambda-Artefakte und legt sie unter <runtime>/dist/ ab,
# damit die CDK-App stabile Pfade hat. Wird von "npm run build:artifacts"
# aus dem cdk/ Verzeichnis aufgerufen.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
JAVA_DIR="$ROOT/runtimes/java"
NODE_DIR="$ROOT/runtimes/node"

DIST_JVM="$JAVA_DIR/dist/jvm"
DIST_NATIVE="$JAVA_DIR/dist/native"
DIST_NODE="$NODE_DIR/dist"

# Selektive Builds via Env-Var, default: alle
TARGETS="${TARGETS:-jvm native node}"

mkdir -p "$DIST_JVM" "$DIST_NATIVE" "$DIST_NODE"

if [[ " $TARGETS " == *" jvm "* ]]; then
  echo "[jvm] mvn package" >&2
  ( cd "$JAVA_DIR" && mvn -B -q package -DskipTests )
  cp "$JAVA_DIR/target/function.zip" "$DIST_JVM/function.zip"
fi

if [[ " $TARGETS " == *" native "* ]]; then
  echo "[native] mvn package -Dnative" >&2
  ( cd "$JAVA_DIR" && mvn -B -q package -Dnative -DskipTests )
  cp "$JAVA_DIR/target/function.zip" "$DIST_NATIVE/function.zip"
fi

if [[ " $TARGETS " == *" node "* ]]; then
  echo "[node] zip src + package.json" >&2
  rm -f "$DIST_NODE/node.zip"
  ( cd "$NODE_DIR" && zip -qr "$DIST_NODE/node.zip" src package.json )
fi

echo "" >&2
echo "Artefakte:" >&2
ls -lh "$DIST_JVM/function.zip" "$DIST_NATIVE/function.zip" "$DIST_NODE/node.zip" 2>/dev/null | awk '{print "  " $9, $5}'
