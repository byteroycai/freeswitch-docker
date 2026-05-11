#!/usr/bin/env bash
FS_PREFIX="${FS_PREFIX:-/usr/local/freeswitch}"
ESL_PASSWORD="${FS_ESL_PASSWORD:-ClueCon}"

"${FS_PREFIX}/bin/fs_cli" -p "${ESL_PASSWORD}" -x "status" 2>/dev/null | grep -q "^UP "
