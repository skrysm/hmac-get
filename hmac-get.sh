#!/bin/bash

# Check that the URL parameter has been passed.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <url>" >&2
    exit 1
fi

URL="$1"

# Add "http://" if not specified.
case "$URL" in
    http://*|https://*)
        FINAL_URL="$URL"
        ;;
    *)
        FINAL_URL="http://$URL"
        ;;
esac

# Download .hmac file and parse its contents
EXPECTED_HMAC_CONTENTS=$(curl -fsSL "$FINAL_URL.hmac")
# Extract algorithm (everything before '(')
EXPECTED_ALGORITHM=$(echo "$EXPECTED_HMAC_CONTENTS" | sed 's/(.*//')
# Extract HMAC (everything after '= ')
EXPECTED_HMAC=$(echo "$EXPECTED_HMAC_CONTENTS" | sed 's/.*= //')

# Check expected algorithm
if [ "$EXPECTED_ALGORITHM" = "HMAC-SHA2-256" ]; then
    EXPECTED_ALGORITHM="-sha256"
else
    echo "Error: Unsupported HMAC algorithm: $EXPECTED_ALGORITHM" >&2
    exit 1
fi

case "$EXPECTED_HMAC" in
    [0-9a-f]*)
        # HMAC is ok
        ;;
    *)
        echo "Error: The expected HMAC format is invalid: $EXPECTED_HMAC" >&2
        exit 1
        ;;
esac

FILE_CONTENT=$(curl -fsSL "$FINAL_URL")

# Prompt for verification secret (visible input)
# IMPORTANT: We use /dev/tty (the actual terminal) so that the prompt and the key won't become part of
#   the output that's piped into the next command.
printf "Enter verification secret: " >/dev/tty
IFS= read -r VERIFICATION_SECRET </dev/tty

# Calculate actual HMAC
ACTUAL_HMAC=$(echo "$FILE_CONTENT" | openssl dgst $EXPECTED_ALGORITHM -hmac "$VERIFICATION_SECRET" | awk '{print $2}')

if [ "$ACTUAL_HMAC" != "$EXPECTED_HMAC" ]; then
    echo "Error: Integrity check FAILED. Either the verification secret was wrong or the file has been modified in transit." >&2
    exit 1
fi

# Print contents so that they can be piped to the next command.
echo "$FILE_CONTENT"
