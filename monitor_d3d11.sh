#!/bin/bash

# URL for the DLL file
URL="https://www.deltaconnected.com/arcdps/x64/"
# Where we wanna save the files
TARGET_DIR="${HOME}/arcdps"

# Check when the remote file was last modified
LAST_MODIFIED=$(wget --server-response --spider "${URL}d3d11.dll" 2>&1 | grep -i "Last-Modified" | cut -d: -f2-)

# Format that date into something usable
FORMATTED_DATE_TIME=$(date -d "${LAST_MODIFIED}" +%Y-%m-%d_%H:%M:%S)

# Grab the MD5 sum file to check later
if wget -q -O /tmp/d3d11.dll.md5sum "${URL}d3d11.dll.md5sum"; then
    # Get just the MD5 sum
    MD5SUM=$(cat /tmp/d3d11.dll.md5sum | awk '{print $1}')
else
    echo "Failed to download MD5 sum file"
    exit 1
fi

# Create a new directory for this version of the DLL
NEW_DIR="${TARGET_DIR}/${FORMATTED_DATE_TIME}_${MD5SUM}"

# Check if the directory exists
if [ ! -d "${NEW_DIR}" ]; then
    # Make it if it doesn't
    mkdir -p "${NEW_DIR}"
fi

# Set paths for the local files
LOCAL_DLL="${NEW_DIR}/d3d11.dll"
LOCAL_MD5="${NEW_DIR}/d3d11.dll.md5sum"

# Check if we already have the DLL
if [ ! -f "${LOCAL_DLL}" ]; then
    # If we don't have it, let's download the new DLL
    if wget -O "${LOCAL_DLL}" "${URL}d3d11.dll"; then
        # Check if the MD5 matches
        LOCAL_MD5SUM=$(md5sum "${LOCAL_DLL}" | awk '{print $1}')
        if [ "${LOCAL_MD5SUM}" != "${MD5SUM}" ]; then
            echo "MD5 sum mismatch"
            rm -f "${LOCAL_DLL}"  # Remove the bad file
            exit 1
        fi
    else
        echo "Failed to download file"
        exit 1
    fi

    # Now let's download the MD5 sum file again just to be sure
    if wget -O "${LOCAL_MD5}" "${URL}d3d11.dll.md5sum"; then
        # Check the MD5 sum of the downloaded MD5 sum file
        LOCAL_MD5SUM=$(cat "${LOCAL_MD5}" | awk '{print $1}')
        if [ "${LOCAL_MD5SUM}" != "${MD5SUM}" ]; then
            echo "MD5 sum mismatch"
            rm -f "${LOCAL_DLL}" "${LOCAL_MD5}"  # Clean up
            exit 1
        fi
    else
        echo "Failed to download MD5 sum file"
        rm -f "${LOCAL_DLL}"  # Clean up the DLL
        exit 1
    fi
fi
