#!/bin/bash

# Makes the script fail on errors and unset variables.
set -euo pipefail

#
# Check that required commands are available.
#
REQUIRED_CMDS="curl awk sed openssl"
for cmd in $REQUIRED_CMDS; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' not found in PATH" >&2
        exit 1
    fi
done

#
# Check that the URL parameter has been passed.
#
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <url>" >&2
    exit 1
fi

#
# Determine target url
#
TARGET_URL="$1"
case "$TARGET_URL" in
    http://*|https://*)
        # Keep URL as is.
        ;;
    *)
        # Add "http://" if not specified.
        TARGET_URL="http://$TARGET_URL"
        ;;
esac

#
# Download .hmac file and parse its contents
#
EXPECTED_HMAC_CONTENTS=$(curl -fsSL "$TARGET_URL.hmac") || {
    echo "Error: Failed to download HMAC file from: $TARGET_URL.hmac" >&2
    exit 1
}
# Extract algorithm (everything before '(')
EXPECTED_ALGORITHM=$(echo "$EXPECTED_HMAC_CONTENTS" | sed 's/(.*//')
# Extract HMAC (everything after '= ')
EXPECTED_HMAC=$(echo "$EXPECTED_HMAC_CONTENTS" | sed 's/.*= //')

#
# Check expected algorithm
#
if [ "$EXPECTED_ALGORITHM" = "HMAC-SHA2-256" ]; then
    EXPECTED_ALGORITHM="-sha256"
else
    echo "Error: Unsupported HMAC algorithm: $EXPECTED_ALGORITHM" >&2
    exit 1
fi

#
# Check expected HMAC
#
case "$EXPECTED_HMAC" in
    [0-9a-f]*)
        # HMAC is ok
        ;;
    *)
        echo "Error: The expected HMAC format is invalid: $EXPECTED_HMAC" >&2
        exit 1
        ;;
esac

#
# Download actual file
#
FILE_CONTENT=$(curl -fsSL "$TARGET_URL") || {
    echo "Error: Failed to download file from: $TARGET_URL" >&2
    exit 1
}

#
# Prompt for verification secret (visible input)
# IMPORTANT: We use /dev/tty (the actual terminal) so that the prompt and the key won't become part of
#   the output that's piped into the next command.
#
printf "Enter verification secret: " >/dev/tty
IFS= read -r VERIFICATION_SECRET </dev/tty

#
# Calculate actual HMAC and verify it.
#
ACTUAL_HMAC=$(echo "$FILE_CONTENT" | openssl dgst $EXPECTED_ALGORITHM -hmac "$VERIFICATION_SECRET" | awk '{print $2}')

if [ "$ACTUAL_HMAC" != "$EXPECTED_HMAC" ]; then
    if [[ "$VERIFICATION_SECRET" =~ ^(.+)_([0-9]{2})$ ]]; then
        #
        # Verification secret with mod97 checksum.
        # This way we can differentiate between "secret is wrong" and "file has been modified in transit".
        #
        # NOTE: We use a "_" to separate the checksum (instead of "-") so that terminals mark the secret
        #   including the checksum when double clicking it.
        #
        VERIFICATION_SECRET_BASE="${BASH_REMATCH[1]}"
        EXPECTED_VERIFICATION_SECRET_MOD97_CHECKSUM="${BASH_REMATCH[2]}"

        ACTUAL_VERIFICATION_SECRET_MOD97_CHECKSUM=$(printf '%02d' $(( 0x$(echo -n "$VERIFICATION_SECRET_BASE" | openssl dgst -sha256 | awk '{print $2}' | head -c8) % 97 )))

        if [[ "$ACTUAL_VERIFICATION_SECRET_MOD97_CHECKSUM" == "$EXPECTED_VERIFICATION_SECRET_MOD97_CHECKSUM" ]]; then
            echo "Error: Integrity check FAILED. The file has been modified in transit!!!" >&2
        else
            echo "Error: Integrity check FAILED. You entered the wrong verification secret." >&2
        fi
    else
        #
        # Verification secret without checksum.
        #
        echo "Error: Integrity check FAILED. Either you entered the wrong verification secret or the file has been modified in transit." >&2
    fi
    exit 1
fi

#
# Print contents so that they can be piped to the next command.
#
echo "$FILE_CONTENT"
