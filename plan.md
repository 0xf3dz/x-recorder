# X Spaces recorder plan

## Objective

Run an unattended monitor from one VPS directory. Record each live X Space that the target account hosts.

The recorder must not use the official X API. It will use `twspace-dl`, X web endpoints, and authenticated browser cookies.

## Target layout

Use one directory for the service and its data:

```text
xspaces-recorder/
├── .env
├── cookies.txt
├── docker-compose.yml
├── monitor.sh
└── recordings/
```

Run all Docker Compose commands from this directory.

## Prerequisites

- Use a Linux VPS that stays online during each Space.
- Install Docker Engine and the Docker Compose plug-in.
- Keep at least 10 GB of free disk space.
- Export an active X session to a Netscape-format `cookies.txt` file.
- Prefer a separate X account for the recorder.
- Confirm that local law and the applicable platform rules permit the recording.

## Implementation steps

### 1. Create the service directory

Choose a directory that the VPS user owns:

```bash
mkdir -p "$HOME/xspaces-recorder/recordings"
cd "$HOME/xspaces-recorder"
```

Do not run the service from a temporary directory.

### 2. Record the VPS user identifiers

Get the user and group identifiers:

```bash
id -u
id -g
```

Use these values for `PUID` and `PGID` in `.env`. This setting gives the container access to `cookies.txt` and `recordings/`.

### 3. Create `.env`

Create `.env` with these values:

```dotenv
TWITTER_ID=account_name_without_at
INTERVAL=10
PUID=1000
PGID=1000
```

Replace `account_name_without_at` with the X account name. Replace `1000` values when `id -u` or `id -g` gives different values.

Use an interval of 10 seconds for the first deployment. Do not use an interval below 5 seconds.

### 4. Add the X session cookies

Export cookies from a browser that has an active X session. Use the Netscape cookie-file format.

Copy the file into the service directory:

```bash
cp /path/to/exported/cookies.txt ./cookies.txt
chmod 600 ./cookies.txt
```

Do not put `cookies.txt` in source control. A stolen cookie file can give another person access to the X session.

### 5. Create `monitor.sh`

Create `monitor.sh` with this content:

```sh
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
```

Set the file mode:

```bash
chmod 750 ./monitor.sh
```

The Space identifier in each file name prevents two Spaces from using the same path. The metadata file keeps the title and host details.

### 6. Create `docker-compose.yml`

Create `docker-compose.yml` with this content:

```yaml
services:
  xspaces-recorder:
    image: ghcr.io/0xf3dz/twspace-dl@sha256:54f661ade6a16a8ba9f54703e4c43f8c18b1e4a0ee59870f737cd81a54cb9fe2
    container_name: xspaces-recorder
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    env_file:
      - .env
    working_dir: /output
    volumes:
      - .:/output
    entrypoint:
      - dumb-init
      - --
      - sh
    command:
      - ./monitor.sh
    security_opt:
      - no-new-privileges:true
    logging:
      driver: json-file
      options:
        max-size: 10m
        max-file: "3"
```

The restart rule starts the monitor again after a VPS restart or an unexpected process exit. The log limits prevent Docker logs from using all disk space.

### 7. Validate the configuration

Check the required files and permissions:

```bash
pwd
stat .env cookies.txt monitor.sh docker-compose.yml recordings
```

Validate the Compose file:

```bash
docker compose config
```

Do not continue if Compose reports an invalid variable or file.

### 8. Start the monitor

Pull the container image and start the service:

```bash
docker compose pull
docker compose up -d
```

Read the first log entries:

```bash
docker compose logs --tail=50 xspaces-recorder
```

Expected evidence:

- The container stays in the `Up` state.
- The log shows `Monitor started`.
- The log shows one account check approximately every 10 seconds.
- The log does not show a cookie permission error.

Check the container state:

```bash
docker compose ps
```

### 9. Verify a live recording

Wait until the target account hosts a Space. Follow the service log:

```bash
docker compose logs -f xspaces-recorder
```

During the Space, confirm that a file appears and grows:

```bash
watch -n 5 'du -h tmp*/*_new.m4a recordings/*.json 2>/dev/null'
```

`TwspaceDL.download` writes active audio to `tmp*/<base-name>_new.m4a`.
The final `recordings/<base-name>.m4a` appears after the Space ends.

After the Space ends, inspect the result:

```bash
find recordings -maxdepth 1 -type f -print
docker compose exec xspaces-recorder \
  ffmpeg -v error \
  -i "/output/recordings/<recorded-file>.m4a" \
  -f null -
```

Acceptance criteria:

- The monitor detects the Space without a Space URL.
- A `tmp*/<base-name>_new.m4a` file appears and grows while the Space is live.
- A final decodable `.m4a` file appears after the Space ends.
- The matching JSON metadata contains the Space identifier and host data.
- Completed files remain after a container restart.

## Operations

### Read logs

```bash
cd "$HOME/xspaces-recorder"
docker compose logs -f xspaces-recorder
```

### Stop the monitor

```bash
docker compose stop
```

### Start the monitor

```bash
docker compose start
```

### Update the recorder

```bash
docker compose pull
docker compose up -d
```

Run the live-recording verification again after an update. The image uses an undocumented X web interface, which can change without notice.

### Replace expired cookies

Export a new Netscape-format cookie file. Replace the old file without changing its owner:

```bash
install -m 600 /path/to/new/cookies.txt ./cookies.txt
```

Restart the service:

```bash
docker compose restart xspaces-recorder
```

### Check disk use

```bash
du -sh recordings
df -h .
```

Do not add automatic deletion until you define a retention period. Copy required recordings to separate storage before you remove local files.

## Failure checks

| Symptom | Check | Action |
|---|---|---|
| `cookies.txt` is not readable | Run `id`, `stat cookies.txt`, and inspect `PUID` and `PGID` | Correct `.env`, file ownership, or file mode |
| The service restarts many times | Run `docker compose logs --tail=200` | Correct the first reported configuration or command error |
| The account is live but no file appears | Confirm the account hosts the Space and the cookies can view it | Refresh the cookies, restart the service, and inspect the next account check |
| The output file stays empty | Check the VPS network and the service log | Retry with fresh cookies and the current container image |
| The disk becomes full | Run `du -sh recordings` and `df -h .` | Move old recordings to archive storage |

## Source references

- Recorder source: https://github.com/0xf3dz/twspace-dl
- Monitor source: https://github.com/0xf3dz/twspace-dl/blob/main/monitor.sh
- Container source: https://github.com/0xf3dz/twspace-dl/blob/main/Dockerfile
