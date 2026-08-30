#!/bin/sh

set -u

: "${TWITTER_ID:?Set TWITTER_ID in .env}"

INTERVAL="${INTERVAL:-10}"
COOKIE_FILE="/output/cookies.txt"
OUTPUT_FORMAT="recordings/%(start_date)s_%(creator_screen_name)s_%(id)s"

mkdir -p /output/recordings

echo "Monitor started for @${TWITTER_ID}. Poll interval: ${INTERVAL} seconds."

while true; do
    if [ ! -r "$COOKIE_FILE" ]; then
        echo "Cannot read ${COOKIE_FILE}. Retry in 60 seconds."
        sleep 60
        continue
    fi

    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') Check @${TWITTER_ID}."

    /venv/bin/twspace_dl \
        --user-url "https://x.com/${TWITTER_ID}" \
        --input-cookie-file "$COOKIE_FILE" \
        --output "$OUTPUT_FORMAT" \
        --write-metadata

    RESULT=$?
    if [ "$RESULT" -ne 0 ]; then
        echo "twspace-dl returned code ${RESULT}."
    fi

    sleep "$INTERVAL"
done
