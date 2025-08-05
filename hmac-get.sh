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

# Prompt for verification secret (visible input)
printf "Enter verification secret: "
IFS= read -r VERIFICATION_SECRET

ACTUAL=$(curl -fsSL "$FINAL_URL" | openssl dgst -sha256 -hmac "$VERIFICATION_SECRET" | awk '{print $2}')
EXPECTED=$(curl -fsSL "$FINAL_URL.hmac" | awk '{print $2}')

if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo "Integrity check PASSED"
else
    echo "Integrity check FAILED"
fi
