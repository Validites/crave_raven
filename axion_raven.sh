#!/bin/bash
# =========================================================
# CONFIGURATION
# =========================================================
TG_BOT_TOKEN="7302600160:AAFNxEr7Tma0zBgkMC2IIF39gcuT2F6ZT5Q"
TG_CHAT_ID="7305843184"
DEVICE="raven"
ROM_NAME="AxionAOSP"
ANDROID_VERSION="16"
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
Device: ${DEVICE}
Android: ${ANDROID_VERSION}
Config: userdebug | gms"

    echo ">>>> Aggressive Cleanup..."
    rm -rf \
        device/google/raven device/google/raviole device/google/gs101 hardware/google/pixel \
        vendor/google/raven vendor/google/raviole vendor/lineage-priv vendor/google/camera \
        kernel/google/raviole kernel/google/gs101 \
        .repo/local_manifests
    mkdir -p vendor/lineage-priv/keys

    echo ">>>> Initializing repository..."
    repo init -q -u https://github.com/AxionAOSP/android.git -b lineage-23.2 --git-lfs

    echo ">>>> Cloning Pixel manifests (Branch 23.0)..."
    git clone -q https://github.com/AxionAOSP/roomservice_pixels.git -b lineage-23.0 .repo/local_manifests

    echo ">>>> Applying GCam LFS fix..."
    sed -i '/vendor\/google\/camera/d' .repo/local_manifests/*.xml

    echo ">>>> Syncing repositories..."
    repo sync -c --force-sync --force-remove-dirty --no-tags --no-clone-bundle -j"$(nproc)"

    echo ">>>> Fetching Git LFS..."
    if [ -d vendor/google/raven ]; then
        ( cd vendor/google/raven && git lfs fetch --all && git lfs checkout )
    fi

    echo ">>>> Verifying vendor tree exists..."
    if [ ! -f "vendor/google/raven/raven-vendor.mk" ]; then
        echo "CRITICAL ERROR: vendor/google/raven/raven-vendor.mk is missing!"
        send_msg "*Build Failed* - Vendor blobs did not sync."
        exit 1
    fi

    echo ">>>> Setting up build environment..."
    # set -e needs to be suspended across envsetup.sh as it deliberately uses
    # functions that return non-zero during setup
    set +e
    . build/envsetup.sh
    axion "${DEVICE}" userdebug gms
    set -e

    mka installclean

    echo ">>>> Compiling..."
    set +e
    m bacon
    BUILD_STATUS=$?
    set -e

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
