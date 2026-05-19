#!/bin/bash

# =========================================================
# CONFIGURATION
# =========================================================

TG_BOT_TOKEN="7302600160:AAFNxEr7Tma0zBgkMC2IIF39gcuT2F6ZT5Q"
TG_CHAT_ID="7305843184"

DEVICE="starlte"
ROM_NAME="LineageOS"
ANDROID_VERSION="23.0"

export TZ="Europe/London"
export BUILD_USERNAME="LW"
export BUILD_HOSTNAME="aura"

# =========================================================
# FUNCTIONS
# =========================================================

send_msg() {
    curl -s \
        -d "chat_id=${TG_CHAT_ID}" \
        --data-urlencode "text=$1" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" > /dev/null
}

gofile_upload() {
    local file="$1"
    local server
    local link

    if ! command -v jq &> /dev/null; then
        echo ">>>> jq not found, installing..."
        mkdir -p ~/bin
        curl -sL -o ~/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-amd64
        chmod +x ~/bin/jq
        export PATH="$HOME/bin:$PATH"
    fi

    server=$(curl -s https://api.gofile.io/servers | jq -r '.data.servers[0].name')

    if [ -z "$server" ] || [ "$server" = "null" ]; then
        echo "ERROR: Could not resolve GoFile server."
        send_msg "*Upload Failed* - Could not resolve GoFile server."
        return 1
    fi

    link=$(curl -s -F "file=@${file}" "https://${server}.gofile.io/uploadFile" | jq -r '.data.downloadPage')

    if [ -z "$link" ] || [ "$link" = "null" ]; then
        echo "ERROR: Upload to GoFile failed or returned no link."
        send_msg "*Upload Failed* - GoFile returned no download link."
        return 1
    fi

    echo "$link"
}

# =========================================================
# BUILD LOGIC
# =========================================================

start_build() {

    START_TIME=$(date +%s)

    send_msg "*Build Started*
ROM: ${ROM_NAME}
Device: ${DEVICE} (Galaxy S9)
Android: ${ANDROID_VERSION}
Config: userdebug"

    echo ">>>> Aggressive Cleanup..."
    rm -rf \
        device/samsung/starlte \
        device/samsung/exynos9810-common \
        device/samsung_slsi/sepolicy \
        kernel/samsung/exynos9810 \
        vendor/samsung/starlte \
        vendor/samsung/exynos9810-common \
        hardware/samsung \
        hardware/samsung_slsi-linaro \
        system/tools/mkbootimg \
        external/cronet \
        .repo/local_manifests

    echo ">>>> Clearing Soong bootstrap cache..."
    rm -rf out/soong/ out/host/linux-x86/bin/go/

    echo ">>>> Initializing repository..."
    repo init -q -u https://github.com/LineageOS/android.git -b lineage-23.0 --git-lfs

    echo ">>>> Writing local manifest (LineageOS 23.0 + ExyHyperBrick sources)..."
    mkdir -p .repo/local_manifests

    # Transcribed verbatim from ExyHyperBrick/local_manifests, starlte tree.
    # Only star2lte/crownlte device+vendor entries are omitted (not needed for starlte).
    cat > .repo/local_manifests/local_manifest.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>

  <!-- Kernel -->
  <project name="ExyHyperBrick/android_kernel_samsung_exynos9810"
           path="kernel/samsung/exynos9810"
           remote="github"
           revision="lineage-23.0-bpf-test6" />

  <!-- Device trees -->
  <project name="ExyHyperBrick/android_device_samsung_exynos9810-common"
           path="device/samsung/exynos9810-common"
           remote="github"
           revision="lineage-23.0" />

  <project name="ExyHyperBrick/android_device_samsung_starlte"
           path="device/samsung/starlte"
           remote="github"
           revision="lineage-23.0" />

  <!-- Vendor blobs -->
  <project name="ExyHyperBrick/proprietary_vendor_samsung_exynos9810-common"
           path="vendor/samsung/exynos9810-common"
           remote="github"
           revision="lineage-23.0" />

  <project name="ExyHyperBrick/proprietary_vendor_samsung_starlte"
           path="vendor/samsung/starlte"
           remote="github"
           revision="lineage-23.0" />

  <!-- Samsung SEPolicy (LineageOS upstream) -->
  <project name="LineageOS/android_device_samsung_slsi_sepolicy"
           path="device/samsung_slsi/sepolicy"
           remote="github"
           revision="lineage-23.0" />

  <!-- Samsung hardware (pinned commit — matches upstream manifest exactly) -->
  <project name="LineageOS/android_hardware_samsung"
           path="hardware/samsung"
           remote="github"
           revision="33f74940ad17587bacffcd40a353ba2c50c9ff30" />

  <!-- Samsung LSI / Linaro hardware stack (all from LineageOS upstream) -->
  <project name="LineageOS/android_hardware_samsung_slsi-linaro_config"
           path="hardware/samsung_slsi-linaro/config"
           remote="github"
           revision="lineage-23.0" />

  <project name="LineageOS/android_hardware_samsung_slsi-linaro_exynos"
           path="hardware/samsung_slsi-linaro/exynos"
           remote="github"
           revision="lineage-23.0" />

  <project name="LineageOS/android_hardware_samsung_slsi-linaro_exynos5"
           path="hardware/samsung_slsi-linaro/exynos5"
           remote="github"
           revision="lineage-23.0" />

  <project name="LineageOS/android_hardware_samsung_slsi-linaro_graphics"
           path="hardware/samsung_slsi-linaro/graphics"
           remote="github"
           revision="lineage-23.0" />

  <project name="LineageOS/android_hardware_samsung_slsi-linaro_interfaces"
           path="hardware/samsung_slsi-linaro/interfaces"
           remote="github"
           revision="lineage-23.0" />

  <project name="LineageOS/android_hardware_samsung_slsi-linaro_openmax"
           path="hardware/samsung_slsi-linaro/openmax"
           remote="github"
           revision="lineage-23.0" />

  <!-- Replace AOSP mkbootimg and cronet with LineageOS forks (required by device tree) -->
  <!-- repopick -f 433124 433126 433128 433103 433141 433143 433174 433320 433617 -->
  <remove-project name="platform/system/tools/mkbootimg" />
  <remove-project name="platform/external/cronet" />
  <project name="LineageOS/android_system_tools_mkbootimg"
           path="system/tools/mkbootimg"
           remote="github"
           revision="lineage-23.0" />
  <project name="LineageOS/android_external_cronet"
           path="external/cronet"
           remote="github"
           revision="lineage-23.0" />

</manifest>
EOF

    echo ">>>> Syncing repositories..."
    /opt/crave/resync.sh

    echo ">>>> Injecting kernel localversion (🇺🇦)..."
    # The kernel build system concatenates all localversion* files in the
    # source root into the version string, producing e.g. 4.9.337-🇺🇦-starlte.
    # This is non-invasive — no Makefile edits needed.
    printf -- '-🇺🇦-starlte' > kernel/samsung/exynos9810/localversion-custom

    echo ">>>> Verifying vendor tree exists..."
    if [ ! -f "vendor/samsung/starlte/starlte-vendor.mk" ]; then
        echo "CRITICAL ERROR: vendor/samsung/starlte/starlte-vendor.mk is missing!"
        send_msg "*Build Failed* - Vendor blobs did not sync."
        exit 1
    fi

    echo ">>>> Setting up build environment..."
    . build/envsetup.sh
    # Android 14 (lineage-23.0) uses the three-part lunch format:
    # <product>-<release>-<variant>. trunk_staging is the correct release
    # token for unofficial/in-development device trees.
    # installclean runs AFTER lunch so the product is registered before any
    # make call — otherwise make triggers roomservice trying to find starlte
    # in the official LineageOS org.
    lunch "lineage_${DEVICE}-trunk_staging-userdebug"

    echo ">>>> Cleaning previous output..."
    mka installclean

    echo ">>>> Compiling..."
    m bacon

    BUILD_STATUS=$?

    DURATION=$(( ($(date +%s) - START_TIME) / 60 ))

    if [[ $BUILD_STATUS -eq 0 ]]; then
        STATUS="Success ✅"
    else
        STATUS="Failure (Exit Code: ${BUILD_STATUS}) ❌"
    fi

    send_msg "*Build Finished*
Status: ${STATUS}
Duration: ${DURATION} minutes"

    if [[ $BUILD_STATUS -eq 0 ]]; then
        echo ">>>> Build successful, uploading to GoFile..."
        ROM_ZIP=$(ls -t "out/target/product/${DEVICE}/"*.zip 2>/dev/null | head -n 1)

        if [ -f "$ROM_ZIP" ]; then
            LINK=$(gofile_upload "$ROM_ZIP")
            send_msg "*Artifact Uploaded*
File: $(basename "$ROM_ZIP")
Link: ${LINK}"
        else
            echo "WARNING: No zip found in out/target/product/${DEVICE}/"
            send_msg "*Warning* - Build succeeded but no output zip was found."
        fi
    fi

    exit "$BUILD_STATUS"
}

start_build
