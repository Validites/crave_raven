#!/bin/bash

# =========================================================
# CONFIGURATION
# =========================================================

TG_BOT_TOKEN="7302600160:AAFNxEr7Tma0zBgkMC2IIF39gcuT2F6ZT5Q"
TG_CHAT_ID="7305843184"

# virtio target — pick one:
#   virtio_arm64       ARM 32+64-bit (most compatible, default)
#   virtio_arm64only   ARM 64-bit only (smaller, no 32-bit apps)
#   virtio_x86_64      x86-64
#   virtio_x86_64_tv   x86-64 (Android TV)
#   virtio_x86_64_car  x86-64 (Automotive)
DEVICE="virtio_x86_64"

ROM_NAME="LineageOS"
LINEAGE_BRANCH="lineage-23.2"
ANDROID_VERSION="23.2"

# Virtual A/B is default (requires 13 GiB disk).
# Set to "false" to build A-only (requires 5 GiB disk, smaller image).
AB_OTA_UPDATER="${AB_OTA_UPDATER:-false}"

# Output format: "img" (default) or "iso" (x86_64 targets only).
BUILD_FORMAT="${BUILD_FORMAT:-iso}"

export TZ="Europe/London"
export BUILD_USERNAME="LW"
export BUILD_HOSTNAME="aura"

# Fix: mtools (mcopy) fails with "Error converting to codepage 850" in minimal
# build environments because the host locale doesn't supply the codepage tables.
# LC_ALL=C forces POSIX/ASCII behaviour; MTOOLS_NO_VFAT=1 disables the VFAT
# long-name path that triggers the conversion.  Both are needed for x86_64
# targets where GRUB embeds a persist.img FAT image during espimage-install.
export LC_ALL=C
export MTOOLS_NO_VFAT=1

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
# VALIDATION
# =========================================================

validate_config() {
    # Warn if ISO format is requested for an ARM target (unsupported by wiki).
    if [[ "$BUILD_FORMAT" == "iso" ]] && [[ "$DEVICE" != virtio_x86_64* ]]; then
        echo "ERROR: ISO format is only supported for x86_64 targets. Got: ${DEVICE}"
        send_msg "*Config Error* - ISO format requires an x86_64 target (got \`${DEVICE}\`)."
        exit 1
    fi

    # Warn about the ARM Cortex-A510 limitation for virtio_arm64.
    if [[ "$DEVICE" == "virtio_arm64" ]]; then
        echo "NOTE: virtio_arm64 requires a host CPU with 32-bit mode support."
        echo "      If your host is Cortex-A510 / -A520 / -X925 (ARM64-only), use virtio_arm64only."
    fi
}

# =========================================================
# BUILD LOGIC
# =========================================================

start_build() {

    validate_config

    START_TIME=$(date +%s)

    # Human-readable partition scheme label for TG message.
    if [[ "$AB_OTA_UPDATER" == "false" ]]; then
        PARTITION_SCHEME="A-only (5 GiB)"
    else
        PARTITION_SCHEME="Virtual A/B (13 GiB)"
    fi

    send_msg "*Build Started*
ROM: ${ROM_NAME} ${ANDROID_VERSION} (${LINEAGE_BRANCH})
Target: \`${DEVICE}\`
Partitions: ${PARTITION_SCHEME}
Format: ${BUILD_FORMAT}"

    echo ">>>> Aggressive Cleanup..."
    rm -rf \
        .repo/local_manifests

    # virtio targets ship no device/vendor tree in AOSP; no extra dirs to wipe.
    # Turns out clearing the dirs below break Crave rules.. skipping!
    # echo ">>>> Clearing Soong bootstrap cache..."
    # rm -rf out/soong/ out/host/linux-x86/bin/go/

    echo ">>>> Initializing repository (${LINEAGE_BRANCH})..."
    # --git-lfs is required — several virtio repos use LFS.
    repo init -q \
        -u https://github.com/LineageOS/android.git \
        -b "${LINEAGE_BRANCH}" \
        --git-lfs

    # virtio targets are fully in-tree; no local_manifests needed.
    # If you want to overlay something (e.g. GApps prep, custom packages),
    # add a local_manifest block here.

    echo ">>>> Syncing repositories..."
    /opt/crave/resync.sh

    echo ">>>> Setting up build environment..."
    . build/envsetup.sh

    # Apply A-only partition scheme override if requested.
    if [[ "$AB_OTA_UPDATER" == "false" ]]; then
        echo ">>>> Disabling Virtual A/B (A-only build)..."
        export AB_OTA_UPDATER=false
    fi

    echo ">>>> Running breakfast for ${DEVICE}..."
    breakfast "${DEVICE}"

    echo ">>>> Cleaning previous output..."
    mka installclean

    # Select the correct make target based on the requested output format.
    if [[ "$BUILD_FORMAT" == "iso" ]]; then
        MAKE_TARGET="isoimage-install"
        ARTIFACT_EXT="iso"
    else
        MAKE_TARGET="espimage-install"
        ARTIFACT_EXT="img"
    fi

    echo ">>>> Compiling (make ${MAKE_TARGET})..."
    # The prebuilt mtools binary in prebuilts/bootmgr/ is launched through its
    # own ld-linux-x86-64.so.2, so exported env vars (LC_ALL, MTOOLS_NO_VFAT)
    # are ignored.  The binary still reads ~/.mtoolsrc at runtime, so write
    # the flag there instead to suppress the "codepage 850" error on FAT image
    # creation (persist.img / grubenv step for x86_64 targets).
    echo 'MTOOLS_NO_VFAT=1' > ~/.mtoolsrc
    m "${MAKE_TARGET}"

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
        echo ">>>> Build successful, locating artifact..."

        ARTIFACT=$(ls -t "out/target/product/${DEVICE}/lineage-"*"-UNOFFICIAL-${DEVICE}.${ARTIFACT_EXT}" 2>/dev/null | head -n 1)

        if [ -f "$ARTIFACT" ]; then
            echo ">>>> Uploading $(basename "$ARTIFACT") to GoFile..."
            LINK=$(gofile_upload "$ARTIFACT")
            send_msg "*Artifact Uploaded*
Target: \`${DEVICE}\`
File: \`$(basename "$ARTIFACT")\`
Format: ${ARTIFACT_EXT^^}
Link: ${LINK}"
        else
            echo "WARNING: No .${ARTIFACT_EXT} found in out/target/product/${DEVICE}/"
            echo "         Files present:"
            ls "out/target/product/${DEVICE}/" 2>/dev/null | head -20
            send_msg "*Warning* - Build succeeded but no output .${ARTIFACT_EXT} was found."
        fi
    fi

    exit "$BUILD_STATUS"
}

start_build
