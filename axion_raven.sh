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
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=$1" \
    -d "parse_mode=Markdown" \
    -d "disable_web_page_preview=true" > /dev/null
}

gofile_upload() {
    local file="$1"
    local server
    
    # Ensure jq is installed (Crave containers might lack it)
    if ! command -v jq &> /dev/null; then
        mkdir -p ~/bin
        curl -sL -o ~/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux64
        chmod +x ~/bin/jq
        export PATH=$HOME/bin:$PATH
    fi
    
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
    
    echo ">>>> Cleaning up workspace..."
    # Included raviole in cleanup to prevent conflicts
    rm -rf .repo/local_manifests {device,vendor,kernel}/google/{raven,raviole,gs101} hardware/google/pixel
    
    # FIX 1: Create the keys directory so the build doesn't throw a Permission Denied error
    mkdir -p vendor/lineage-priv/keys

    echo ">>>> Initializing repository..."
    repo init -q -u https://github.com/AxionAOSP/android.git -b lineage-23.2 --git-lfs
    git clone -q https://github.com/AxionAOSP/roomservice_pixels.git -b lineage-23.2 .repo/local_manifests
    
    # FIX 2: Inject TheMuppets so we actually get the vendor blobs!
    echo ">>>> Injecting proprietary vendor manifests..."
    cat <<EOF > .repo/local_manifests/raven_vendor.xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="muppets" fetch="https://gitlab.com/the-muppets" />
  <project name="proprietary_vendor_google_raven" path="vendor/google/raven" remote="muppets" clone-depth="1" />
  <project name="proprietary_vendor_google_raviole" path="vendor/google/raviole" remote="muppets" clone-depth="1" />
</manifest>
EOF
    
    echo ">>>> Syncing repositories..."
    /opt/crave/resync.sh
    repo sync -c --force-sync --no-tags --no-clone-bundle -j$(nproc) -q

    echo ">>>> Fetching Git LFS..."[ -d vendor/google/raven ] && (cd vendor/google/raven && git lfs fetch --all && git lfs checkout)

    echo ">>>> Setting up build environment..."
    . build/envsetup.sh
    axion ${DEVICE} user core
    mka installclean

    echo ">>>> Compiling..."
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
        echo ">>>> Build successful, uploading to GoFile..."
        ROM_ZIP=$(ls -t out/target/product/${DEVICE}/*.zip 2>/dev/null | head -n 1)
        if [ -f "$ROM_ZIP" ]; then
            LINK=$(gofile_upload "$ROM_ZIP")
            send_msg "*Artifact Uploaded*
File: $(basename "$ROM_ZIP")
Link: $LINK"
        fi
    fi
}

start_build
