#!/bin/bash

# Somnia Installer for macOS

ARCH=$(uname -m)
VERSION="0.1.0"
APP_NAME="Somnia"
REPO="8Sleeps/Somnia"

if [[ "$ARCH" == "arm64" ]]; then
  FILENAME="Somnia_${VERSION}_aarch64.dmg"
elif [[ "$ARCH" == "x86_64" ]]; then
  FILENAME="Somnia_${VERSION}_x64.dmg"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

BASE_URL="https://github.com/${REPO}/releases/download/v${VERSION}"
DOWNLOAD_URL="${BASE_URL}/${FILENAME}"

mkdir -p "/tmp/SomniaInstall"

if [ -d "/Applications/${APP_NAME}.app" ]; then
  echo "Somnia is already installed. Removing old version..."
  rm -rf "/Applications/${APP_NAME}.app"
  echo "Old version removed."
else
  echo "Somnia is not installed. Proceeding with installation."
fi

clear
echo "Downloading Somnia v${VERSION} for ${ARCH}..."
echo "From: $DOWNLOAD_URL"
curl -L --progress-bar -o "/tmp/SomniaInstall/somnia.dmg" "$DOWNLOAD_URL"

if [ $? -ne 0 ]; then
  echo "Download failed. Please check your internet connection and try again."
  rm -rf "/tmp/SomniaInstall"
  exit 1
fi

echo "Mounting DMG..."
MOUNT_OUTPUT=$(hdiutil attach "/tmp/SomniaInstall/somnia.dmg" -nobrowse 2>/dev/null)
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep "Apple_HFS" | awk '{print $3}')

if [ -z "$MOUNT_POINT" ]; then
  echo "Failed to mount DMG. Exiting."
  rm -rf "/tmp/SomniaInstall"
  exit 1
fi

echo "Installing Somnia..."
ditto "${MOUNT_POINT}/${APP_NAME}.app" "/Applications/${APP_NAME}.app"

echo "Unmounting DMG..."
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true

rm -rf "/tmp/SomniaInstall"
clear
echo "✓ Somnia has been successfully installed!"
echo "You can now launch it from Applications or Spotlight."

