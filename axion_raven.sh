#!/bin/bash

# =========================================================
# CONFIGURATION
# =========================================================
# Ensure .env is sourced to load BOT and CHAT variables
[ -f .env ] && source .env

TG_BOT_TOKEN="${BOT}"
TG_CHAT_ID="${CHAT}"
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
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=$1" \
    -d "parse_mode=Markdown" \
    -d "disable_web_page_preview=true" > /dev/null
}

gofile_upload() {
    local file="$1"
    local server
    server=$(curl -s https://api.gofile.io/servers | jq -r '.data.servers[0].name')
    curl -s -F "file=@${file}" "https://${server}.gofile.io/uploadFile" | jq -r '.data.downloadPage'
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
Start Time: $(date +'%Y-%m-%d %H:%M:%S %Z')"
    
    # Cleanup
    rm -rf .repo/local_manifests {device,vendor,kernel}/google/{raven,gs101} hardware/google/pixel

    # Repo Init & Sync
    repo init -q -u https://github.com/AxionAOSP/android.git -b lineage-23.2 --git-lfs
    git clone -q https://github.com/AxionAOSP/roomservice_pixels.git -b lineage-23.2 .repo/local_manifests
    
    /opt/crave/resync.sh
    repo sync -c --force-sync --no-tags --no-clone-bundle -j$(nproc) -q

    # Git LFS
    [ -d vendor/google/raven ] && (cd vendor/google/raven && git lfs fetch --all && git lfs checkout)

    # Build Setup
    . build/envsetup.sh
    axion ${DEVICE} user core
    mka installclean

    # Compile
    m bacon
    BUILD_STATUS=$?

    # Duration Calculation
    END_TIME=$(date +%s)
    DURATION=$(( (END_TIME - START_TIME) / 60 ))
    
    if [[ $BUILD_STATUS -eq 0 ]]; then
        STATUS="Success"
    else
        STATUS="Failure (Exit Code: $BUILD_STATUS)"
    fi

    send_msg "*Build Finished*
Status: ${STATUS}
Duration: ${DURATION} minutes"
    
    # Upload on Success
    if [[ $BUILD_STATUS -eq 0 ]]; then
        ROM_ZIP=$(ls -t out/target/product/${DEVICE}/*.zip | head -n 1)
        if [ -f "$ROM_ZIP" ]; then
            LINK=$(gofile_upload "$ROM_ZIP")
            send_msg "*Artifact Uploaded*
File: $(basename "$ROM_ZIP")
Link: $LINK"
        fi
    fi
}

start_build
