# Entrypoint hooks

Any `*.sh` file in this directory is sourced by `docker-entrypoint.sh` after
config has been initialised but **before** FreeSWITCH starts. Use this to
inject custom configuration without rebuilding the image.

Mount this directory at `/docker-entrypoint.d` in the container (the bundled
`docker-compose.yml` already does this).

## Example

```bash
# entrypoint.d/10-set-recording-dir.sh
echo "[hook] Pointing recording dir at /usr/local/freeswitch/recordings/$(date +%Y%m)"
mkdir -p "/usr/local/freeswitch/recordings/$(date +%Y%m)"
```

Hooks run as root (the entrypoint drops to the `freeswitch` user only when
finally exec'ing FreeSWITCH), so they can `chown`/`chmod` or write anywhere
under `/usr/local/freeswitch`.

Hooks are sourced (`. file`), not executed — they share the parent shell's
environment and can set new env vars that FreeSWITCH will inherit.
