#!/usr/bin/env bash
# Build an additional FreeSWITCH module via the builder image and inject it
# into a running runtime container.
#
# Usage: ./scripts/build-mod.sh <mod_name> [container_name]
# Example: ./scripts/build-mod.sh mod_shout freeswitch
set -euo pipefail

MOD_NAME="${1:?usage: build-mod.sh <mod_name> [container_name]}"
CONTAINER="${2:-freeswitch}"
BUILDER_IMAGE="${BUILDER_IMAGE:-freeswitch:builder}"
FS_PREFIX="${FS_PREFIX:-/usr/local/freeswitch}"

if ! docker image inspect "${BUILDER_IMAGE}" >/dev/null 2>&1; then
    echo "Builder image '${BUILDER_IMAGE}' not found. Run ./build.sh first." >&2
    exit 1
fi

TMP_VOL="fs-mod-$(date +%s)"
docker volume create "${TMP_VOL}" >/dev/null

cleanup() { docker volume rm "${TMP_VOL}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> Compiling ${MOD_NAME} in ${BUILDER_IMAGE}"
docker run --rm -v "${TMP_VOL}:/output" "${BUILDER_IMAGE}" bash -c "
    cd /usr/src/freeswitch &&
    make ${MOD_NAME}-install &&
    cp ${FS_PREFIX}/mod/${MOD_NAME}.so /output/
"

echo "==> Copying ${MOD_NAME}.so into ${CONTAINER}"
MOUNTPOINT=$(docker volume inspect "${TMP_VOL}" --format '{{ .Mountpoint }}')
docker cp "${MOUNTPOINT}/${MOD_NAME}.so" "${CONTAINER}:${FS_PREFIX}/mod/"

echo "==> Loading ${MOD_NAME} in ${CONTAINER}"
docker exec "${CONTAINER}" fs_cli -x "load ${MOD_NAME}"
echo "Done."
