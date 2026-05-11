#!/usr/bin/env bash
set -euo pipefail

FS_PREFIX="${FS_PREFIX:-/usr/local/freeswitch}"
FS_CONF_DIR="${FS_PREFIX}/conf"
FS_DEFAULT_CONF_DIR="${FS_PREFIX}/conf.default"

log() { printf '[entrypoint] %s\n' "$*"; }

gen_password() {
    head -c 32 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 20
}

is_default_sip_password() {
    case "${1:-}" in
        ""|changeme|1234) return 0 ;;
        *) return 1 ;;
    esac
}

is_default_esl_password() {
    case "${1:-}" in
        ""|ClueCon|changeme) return 0 ;;
        *) return 1 ;;
    esac
}

# On first run, snapshot the shipped config so we can repopulate empty volumes.
if [ ! -d "${FS_DEFAULT_CONF_DIR}" ] && [ -d "${FS_CONF_DIR}" ]; then
    log "Snapshotting default config to ${FS_DEFAULT_CONF_DIR}"
    cp -a "${FS_CONF_DIR}" "${FS_DEFAULT_CONF_DIR}"
fi

if [ -d "${FS_CONF_DIR}" ] && [ -z "$(ls -A "${FS_CONF_DIR}" 2>/dev/null)" ]; then
    log "Config dir is empty (fresh volume) — restoring defaults"
    cp -a "${FS_DEFAULT_CONF_DIR}/." "${FS_CONF_DIR}/"
fi

VARS_XML="${FS_CONF_DIR}/vars.xml"
ESL_CONF="${FS_CONF_DIR}/autoload_configs/event_socket.conf.xml"

# Pick the SIP default password:
#   1. If FS_DEFAULT_PASSWORD is set (even to a weak value), trust the user
#      — they explicitly chose it. This matters for setups that hard-code
#      a known dev password.
#   2. Otherwise, if the file still has FreeSWITCH's upstream default
#      ("1234"), randomize so we never ship with that.
#   3. Otherwise, keep the value already in the file (a previous run
#      already randomized or a user-supplied value is persisted on disk).
if [ -f "${VARS_XML}" ]; then
    current_sip=$(sed -n 's|.*data="default_password=\([^"]*\)".*|\1|p' "${VARS_XML}" | head -1)

    if [ -n "${FS_DEFAULT_PASSWORD:-}" ]; then
        new_sip="${FS_DEFAULT_PASSWORD}"
    elif is_default_sip_password "${current_sip}"; then
        new_sip="$(gen_password)"
        cat <<-BANNER

			================================================================
			  Generated default SIP password (extensions 1000-1019):
			      ${new_sip}
			  This is shown ONCE. Save it now.
			  Override by setting FS_DEFAULT_PASSWORD before first start.
			================================================================

		BANNER
    else
        new_sip="${current_sip}"
    fi

    sed -i "s|\(<X-PRE-PROCESS cmd=\"set\" data=\"default_password=\)[^\"]*\"|\1${new_sip}\"|" "${VARS_XML}"
    export FS_DEFAULT_PASSWORD="${new_sip}"

    if [ -n "${FS_DOMAIN:-}" ]; then
        sed -i "s|\(<X-PRE-PROCESS cmd=\"set\" data=\"domain=\)[^\"]*\"|\1${FS_DOMAIN}\"|" "${VARS_XML}"
    fi

    # FS_EXTERNAL_IP=auto leaves the upstream `stun-set` directives in place
    # so FreeSWITCH discovers the address itself. When STUN is unreachable
    # (offline build, restrictive firewall) the variable ends up as the
    # literal "stun:..." string and mod_sofia refuses to load. To avoid a
    # broken default on first boot we probe STUN here; if it fails, fall
    # back to the container's primary interface address.
    if [ "${FS_EXTERNAL_IP:-auto}" = "auto" ]; then
        if ! getent hosts stun.freeswitch.org >/dev/null 2>&1; then
            FALLBACK_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
            if [ -n "${FALLBACK_IP}" ]; then
                log "STUN unreachable; falling back to ${FALLBACK_IP} for external IP"
                FS_EXTERNAL_IP="${FALLBACK_IP}"
            fi
        fi
    fi

    if [ -n "${FS_EXTERNAL_IP:-}" ] && [ "${FS_EXTERNAL_IP}" != "auto" ]; then
        # Handle both the initial 'stun-set' form and a previously rewritten 'set' form.
        sed -i "s|<X-PRE-PROCESS cmd=\"\(stun-set\|set\)\" data=\"external_rtp_ip=[^\"]*\"|<X-PRE-PROCESS cmd=\"set\" data=\"external_rtp_ip=${FS_EXTERNAL_IP}\"|" "${VARS_XML}"
        sed -i "s|<X-PRE-PROCESS cmd=\"\(stun-set\|set\)\" data=\"external_sip_ip=[^\"]*\"|<X-PRE-PROCESS cmd=\"set\" data=\"external_sip_ip=${FS_EXTERNAL_IP}\"|" "${VARS_XML}"
    fi
fi

if [ -f "${ESL_CONF}" ]; then
    current_esl=$(sed -n 's|.*<param name="password" value="\([^"]*\)".*|\1|p' "${ESL_CONF}" | head -1)

    if [ -n "${FS_ESL_PASSWORD:-}" ]; then
        new_esl="${FS_ESL_PASSWORD}"
    elif is_default_esl_password "${current_esl}"; then
        new_esl="$(gen_password)"
        cat <<-BANNER

			================================================================
			  Generated ESL password:
			      ${new_esl}
			  Use with: fs_cli -p ${new_esl}
			  Override by setting FS_ESL_PASSWORD before first start.
			================================================================

		BANNER
    else
        new_esl="${current_esl}"
    fi

    sed -i "s|\(<param name=\"password\" value=\"\)[^\"]*\"|\1${new_esl}\"|" "${ESL_CONF}"
    export FS_ESL_PASSWORD="${new_esl}"

    FS_ESL_LISTEN_IP="${FS_ESL_LISTEN_IP:-127.0.0.1}"
    sed -i "s|\(<param name=\"listen-ip\" value=\"\)[^\"]*\"|\1${FS_ESL_LISTEN_IP}\"|" "${ESL_CONF}"
    export FS_ESL_LISTEN_IP
fi

export FS_DOMAIN FS_EXTERNAL_IP

# User hooks: any *.sh under /docker-entrypoint.d is sourced before FS starts.
if [ -d /docker-entrypoint.d ]; then
    shopt -s nullglob
    for f in /docker-entrypoint.d/*.sh; do
        [ -r "$f" ] || continue
        log "Running hook: $f"
        # shellcheck disable=SC1090
        . "$f"
    done
    shopt -u nullglob
fi

chown -R freeswitch:freeswitch "${FS_PREFIX}"

if [ "$1" = "freeswitch" ]; then
    shift
    exec gosu freeswitch "${FS_PREFIX}/bin/freeswitch" "$@"
fi

exec "$@"
