#!/usr/bin/env bash
# Build helper for freeswitch-docker. Produces three images by default:
#
#   freeswitch:builder   — compile environment (large, keep for module rebuilds)
#   freeswitch:1.10      — slim production runtime, trimmed module set
#   freeswitch:1.10-dev  — full module set + debug tools (vim, tcpdump, strace, ...)
#
# Env vars:
#   IMAGE_NAME        target image name (default: freeswitch)
#   FS_TAG            FreeSWITCH version tag (default: 1.10)
#   PLATFORM          target platform, e.g. linux/amd64 (default: native)
#   SIGNALWIRE_TOKEN  optional, enables SignalWire-gated modules
#   MODULES_ENABLE    extra modules to enable at compile time
#   BUILDER_DISABLE   modules that can't compile (default: signalwire+spandsp)
#   MODULES_DISABLE   modules stripped from the slim runtime image
#   SKIP_DEV=1        skip building the -dev variant
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-freeswitch}"
FS_TAG="${FS_TAG:-1.10}"
PLATFORM="${PLATFORM:-}"

PLATFORM_ARG=()
TAG_SUFFIX=""
if [ -n "${PLATFORM}" ]; then
    PLATFORM_ARG=(--platform "${PLATFORM}")
    TAG_SUFFIX="-$(echo "${PLATFORM}" | sed 's|linux/||')"
fi

SECRET_ARG=()
if [ -n "${SIGNALWIRE_TOKEN:-}" ]; then
    TOKEN_FILE="$(mktemp)"
    trap 'rm -f "${TOKEN_FILE}"' EXIT
    printf '%s' "${SIGNALWIRE_TOKEN}" > "${TOKEN_FILE}"
    SECRET_ARG=(--secret "id=signalwire_token,src=${TOKEN_FILE}")
    echo "==> SignalWire token detected — enabling premium repo path"
fi

BUILD_ARGS=()
[ -n "${MODULES_ENABLE:-}" ]  && BUILD_ARGS+=(--build-arg "MODULES_ENABLE=${MODULES_ENABLE}")
[ -n "${BUILDER_DISABLE:-}" ] && BUILD_ARGS+=(--build-arg "BUILDER_DISABLE=${BUILDER_DISABLE}")
[ -n "${MODULES_DISABLE:-}" ] && BUILD_ARGS+=(--build-arg "MODULES_DISABLE=${MODULES_DISABLE}")

export DOCKER_BUILDKIT=1

echo "==> Building ${IMAGE_NAME}:builder${TAG_SUFFIX}"
docker build \
    ${SECRET_ARG[@]+"${SECRET_ARG[@]}"} \
    ${PLATFORM_ARG[@]+"${PLATFORM_ARG[@]}"} \
    ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} \
    --target builder \
    -t "${IMAGE_NAME}:builder${TAG_SUFFIX}" \
    .

echo "==> Building ${IMAGE_NAME}:${FS_TAG}${TAG_SUFFIX} (slim runtime)"
docker build \
    ${SECRET_ARG[@]+"${SECRET_ARG[@]}"} \
    ${PLATFORM_ARG[@]+"${PLATFORM_ARG[@]}"} \
    ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} \
    --target runtime \
    -t "${IMAGE_NAME}:${FS_TAG}${TAG_SUFFIX}" \
    -t "${IMAGE_NAME}:latest${TAG_SUFFIX}" \
    .

if [ "${SKIP_DEV:-0}" != "1" ]; then
    echo "==> Building ${IMAGE_NAME}:${FS_TAG}-dev${TAG_SUFFIX} (full + debug tools)"
    docker build \
        ${SECRET_ARG[@]+"${SECRET_ARG[@]}"} \
        ${PLATFORM_ARG[@]+"${PLATFORM_ARG[@]}"} \
        ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} \
        --target runtime-dev \
        -t "${IMAGE_NAME}:${FS_TAG}-dev${TAG_SUFFIX}" \
        .
fi

cat <<EOF

Build complete. Images:
  ${IMAGE_NAME}:builder${TAG_SUFFIX}        compile environment (~2 GB)
  ${IMAGE_NAME}:${FS_TAG}${TAG_SUFFIX}             slim runtime (production)
  ${IMAGE_NAME}:${FS_TAG}-dev${TAG_SUFFIX}         full + debug tools (development)

Run:    docker compose --profile host up -d
Inspect: docker run --rm ${IMAGE_NAME}:${FS_TAG}${TAG_SUFFIX} freeswitch -version
EOF
