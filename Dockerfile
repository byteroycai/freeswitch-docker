# syntax=docker/dockerfile:1.6

ARG DEBIAN_VERSION=bookworm
ARG FS_BRANCH=v1.10
ARG FS_PREFIX=/usr/local/freeswitch

# =============================================================================
# Stage 1: builder — full FS compile
# =============================================================================
# Compiles every module the upstream bootstrap enables, except the two
# that physically cannot compile without SignalWire's gated apt repo:
# mod_signalwire (needs signalwire-client-c2) and mod_spandsp (needs an
# older spandsp ABI than github.com/freeswitch/spandsp HEAD ships).
#
# Trimming the runtime module set happens later, in the prep-slim stage —
# this keeps the expensive layer reusable for both the slim and dev images
# and lets scripts/build-mod.sh pull any module from this image without
# rebuilding.
FROM debian:${DEBIAN_VERSION} AS builder
RUN echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4 \
 && sed -i 's|deb.debian.org|mirrors.tencentyun.com|g; s|security.debian.org|mirrors.tencentyun.com/debian-security|g' /etc/apt/sources.list.d/debian.sources \
 || true

ARG DEBIAN_VERSION
ARG FS_BRANCH
ARG FS_PREFIX
ARG MODULES_ENABLE="xml_int/mod_xml_curl applications/mod_curl"
ARG BUILDER_DISABLE="applications/mod_signalwire applications/mod_spandsp"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates gnupg2 wget curl git lsb-release apt-transport-https \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=secret,id=signalwire_token,required=false \
    set -eux; \
    if [ -s /run/secrets/signalwire_token ]; then \
        TOKEN=$(cat /run/secrets/signalwire_token); \
        wget --http-user=signalwire --http-password=${TOKEN} \
            -O /usr/share/keyrings/signalwire-freeswitch-repo.gpg \
            https://freeswitch.signalwire.com/repo/deb/debian-release/signalwire-freeswitch-repo.gpg; \
        echo "machine freeswitch.signalwire.com login signalwire password ${TOKEN}" > /etc/apt/auth.conf; \
        chmod 600 /etc/apt/auth.conf; \
        echo "deb [signed-by=/usr/share/keyrings/signalwire-freeswitch-repo.gpg] https://freeswitch.signalwire.com/repo/deb/debian-release/ ${DEBIAN_VERSION} main" \
            > /etc/apt/sources.list.d/freeswitch.list; \
        echo "deb-src [signed-by=/usr/share/keyrings/signalwire-freeswitch-repo.gpg] https://freeswitch.signalwire.com/repo/deb/debian-release/ ${DEBIAN_VERSION} main" \
            >> /etc/apt/sources.list.d/freeswitch.list; \
        apt-get update; \
        apt-get build-dep -y freeswitch; \
        rm -f /etc/apt/auth.conf /etc/apt/sources.list.d/freeswitch.list; \
    else \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            build-essential autoconf automake libtool libtool-bin pkg-config cmake \
            bison gawk yasm nasm uuid-dev \
            libssl-dev zlib1g-dev libdb-dev unixodbc-dev \
            libncurses-dev libexpat1-dev libgdbm-dev \
            libtiff-dev libjpeg-dev libperl-dev libgmp3-dev \
            libsnmp-dev libedit-dev libldns-dev libldap2-dev libpq-dev \
            libcurl4-openssl-dev libpcre3-dev libsndfile1-dev \
            libopus-dev libshout3-dev libmpg123-dev libmp3lame-dev \
            libspeex-dev libspeexdsp-dev libsqlite3-dev \
            libxml2-dev libpng-dev liblua5.3-dev libvpx-dev \
            libavformat-dev libswscale-dev libswresample-dev \
            python3-dev; \
    fi; \
    rm -rf /var/lib/apt/lists/*

# Pre-build deps that aren't in Debian main (or aren't current enough).
RUN git clone https://github.com/signalwire/libks.git /usr/src/libks \
    && cd /usr/src/libks \
    && cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release . \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig

RUN git clone --depth 1 https://github.com/freeswitch/spandsp.git /usr/src/spandsp \
    && cd /usr/src/spandsp \
    && ./bootstrap.sh \
    && ./configure --prefix=/usr \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig

# Pin sofia-sip to the v1.13.17 release tag, not HEAD. HEAD has
# changed the symmetric-RTP auto-adjust heuristics in ways that regress
# RTP routing for clients sitting behind Docker port-forwarding — outbound
# RTP gets rewritten to an unreachable bridge IP. The v1.13.17 tag matches
# what SignalWire's official packages ship with FS 1.10 and works with
# the rest of the FS 1.10 codebase.
ARG SOFIA_SIP_TAG=v1.13.17
RUN git clone --branch ${SOFIA_SIP_TAG} --depth 1 \
        https://github.com/freeswitch/sofia-sip.git /usr/src/sofia-sip \
    && cd /usr/src/sofia-sip \
    && ./bootstrap.sh \
    && ./configure --prefix=/usr \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig

RUN git clone --branch ${FS_BRANCH} --depth 1 \
        https://github.com/signalwire/freeswitch.git /usr/src/freeswitch

WORKDIR /usr/src/freeswitch

RUN ./bootstrap.sh -j

RUN set -eux; \
    for mod in ${MODULES_ENABLE}; do \
        sed -i "s|^#\s*${mod}\s*$|${mod}|" modules.conf; \
    done; \
    for mod in ${BUILDER_DISABLE}; do \
        sed -i "s|^${mod}\s*$|#${mod}|" modules.conf; \
    done; \
    echo "=== Enabled modules ==="; \
    grep -E '^[a-z]' modules.conf | sort

RUN ./configure --prefix=${FS_PREFIX} --disable-fhs --without-erlang \
    && make -j"$(nproc)" \
    && make install

# Strip <load module="..."/> entries for modules that didn't compile, so
# FreeSWITCH doesn't log CRIT errors at startup trying to dlopen missing
# .so files. We check all three XML files that can pre/post-load modules.
RUN for path in ${BUILDER_DISABLE}; do \
        mod=$(basename "${path}"); \
        for f in ${FS_PREFIX}/conf/autoload_configs/modules.conf.xml \
                 ${FS_PREFIX}/conf/autoload_configs/pre_load_modules.conf.xml \
                 ${FS_PREFIX}/conf/autoload_configs/post_load_modules.conf.xml; do \
            [ -f "$f" ] && sed -i "/<load module=\"${mod}\"/d" "$f"; \
        done; \
    done

RUN find ${FS_PREFIX} -type f \( -name "*.so*" -o -name "freeswitch" -o -name "fs_cli" \) \
        -exec strip --strip-unneeded {} + 2>/dev/null || true

# =============================================================================
# Stage 2: prep-slim — derived from builder, removes trimmed modules
# =============================================================================
# Drops .so files for modules we don't ship in the production runtime, then
# re-runs ldd against the slimmer set so the next stage only pulls in libs
# that the kept modules actually need. The .la archives are gone too —
# they're libtool dev artifacts not needed at runtime.
FROM builder AS prep-slim

ARG FS_PREFIX
# Modules removed from the slim runtime image. Override at build time with
# --build-arg MODULES_DISABLE="..." (pass "" to ship the full set in slim).
# These were all compiled in the builder stage, so they're available to
# `scripts/build-mod.sh` for later opt-in.
ARG MODULES_DISABLE="\
applications/mod_av \
applications/mod_test \
applications/mod_valet_parking \
codecs/mod_amr \
codecs/mod_g723_1 \
codecs/mod_g729 \
databases/mod_pgsql \
dialplans/mod_dialplan_asterisk \
endpoints/mod_skinny \
event_handlers/mod_cdr_sqlite \
formats/mod_png \
xml_int/mod_xml_rpc \
xml_int/mod_xml_scgi"

RUN set -eux; \
    for path in ${MODULES_DISABLE}; do \
        mod=$(basename "${path}"); \
        rm -f ${FS_PREFIX}/mod/${mod}.so ${FS_PREFIX}/mod/${mod}.la; \
        for f in ${FS_PREFIX}/conf/autoload_configs/modules.conf.xml \
                 ${FS_PREFIX}/conf/autoload_configs/pre_load_modules.conf.xml \
                 ${FS_PREFIX}/conf/autoload_configs/post_load_modules.conf.xml; do \
            [ -f "$f" ] && sed -i "/<load module=\"${mod}\"/d" "$f"; \
        done; \
    done; \
    find ${FS_PREFIX}/mod -name "*.la" -delete

# Trim defaults that voice-only production deployments rarely need.
# 32kHz and 48kHz MoH together weigh ~150 MB; keep 8kHz (G.711) and
# 16kHz (G.722/Opus HD). Fonts are only used by mod_av's video text
# overlay, which we drop in this image.
RUN rm -rf ${FS_PREFIX}/sounds/music/32000 \
           ${FS_PREFIX}/sounds/music/48000 \
           ${FS_PREFIX}/fonts

RUN mkdir -p /runtime-libs \
    && find ${FS_PREFIX} -type f \( -name "*.so*" -o -name "freeswitch" -o -name "fs_cli" \) \
         -exec ldd {} \; 2>/dev/null \
       | awk '/=> \//{print $3}' | sort -u \
       | xargs -I{} cp -L {} /runtime-libs/

# =============================================================================
# Stage 3: prep-dev — derived from builder, keeps everything
# =============================================================================
FROM builder AS prep-dev

ARG FS_PREFIX

RUN mkdir -p /runtime-libs \
    && find ${FS_PREFIX} -type f \( -name "*.so*" -o -name "freeswitch" -o -name "fs_cli" \) \
         -exec ldd {} \; 2>/dev/null \
       | awk '/=> \//{print $3}' | sort -u \
       | xargs -I{} cp -L {} /runtime-libs/

# =============================================================================
# Stage 4: runtime — production image (default target)
# =============================================================================
FROM debian:${DEBIAN_VERSION}-slim AS runtime
RUN echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4 \
 && sed -i 's|deb.debian.org|mirrors.tencentyun.com|g; s|security.debian.org|mirrors.tencentyun.com/debian-security|g' /etc/apt/sources.list.d/debian.sources \
 || true

ARG FS_PREFIX
ENV DEBIAN_FRONTEND=noninteractive \
    FS_PREFIX=${FS_PREFIX} \
    PATH="${FS_PREFIX}/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        gosu ca-certificates libcurl4 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=prep-slim /runtime-libs/ /usr/lib/
RUN ldconfig

COPY --from=prep-slim ${FS_PREFIX} ${FS_PREFIX}

RUN groupadd -r freeswitch && useradd -r -g freeswitch -d ${FS_PREFIX} freeswitch \
    && chown -R freeswitch:freeswitch ${FS_PREFIX}

COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY entrypoint.d /docker-entrypoint.d
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/healthcheck.sh

# SIP
EXPOSE 5060/tcp 5060/udp 5061/tcp
EXPOSE 5080/tcp 5080/udp
# ESL
EXPOSE 8021/tcp
# WebRTC / Verto
EXPOSE 5066/tcp 7443/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["freeswitch", "-nonat", "-nf"]

# =============================================================================
# Stage 5: audiofork-builder — compile out-of-tree mod_audio_fork
# =============================================================================
# Optional. mod_audio_fork is a third-party module (cmake project) that
# streams call audio over a WebSocket. Built here against the same FS
# headers/lib as the rest of the runtime so the .so is ABI-compatible.
# Sources pulled from github.com/byteroycai/mod_audio_fork; pin a tag or
# commit via MOD_AUDIO_FORK_REF for reproducible builds.
FROM builder AS audiofork-builder

ARG FS_PREFIX
ARG MOD_AUDIO_FORK_REPO=https://github.com/byteroycai/mod_audio_fork.git
ARG MOD_AUDIO_FORK_REF=main

RUN apt-get update && apt-get install -y --no-install-recommends \
        libwebsockets-dev libspeexdsp-dev \
        libboost-dev libboost-system-dev libboost-thread-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone ${MOD_AUDIO_FORK_REPO} /usr/src/mod_audio_fork \
    && cd /usr/src/mod_audio_fork \
    && git checkout ${MOD_AUDIO_FORK_REF} \
    && cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DFREESWITCH_INCLUDE_DIR=${FS_PREFIX}/include/freeswitch \
        -DFREESWITCH_LIBRARY=${FS_PREFIX}/lib/libfreeswitch.so \
        -DFREESWITCH_MOD_DIR=${FS_PREFIX}/mod \
    && cmake --build build --parallel \
    && cmake --install build \
    && test -f ${FS_PREFIX}/mod/mod_audio_fork.so \
    && strip --strip-unneeded ${FS_PREFIX}/mod/mod_audio_fork.so

# =============================================================================
# Stage 6: runtime-audiofork — slim runtime + mod_audio_fork pre-baked
# =============================================================================
# Same trim list as `runtime`, plus mod_audio_fork.so and its single extra
# runtime dep (libwebsockets17). Everything else mod_audio_fork links to
# (libspeexdsp, libboost-system/thread loaded transitively via FS itself,
# libsofia-sip-ua, libcurl) is already present in the slim base.
FROM runtime AS runtime-audiofork

ARG FS_PREFIX

RUN apt-get update && apt-get install -y --no-install-recommends \
        libwebsockets17 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=audiofork-builder ${FS_PREFIX}/mod/mod_audio_fork.so ${FS_PREFIX}/mod/mod_audio_fork.so
RUN chown freeswitch:freeswitch ${FS_PREFIX}/mod/mod_audio_fork.so

# =============================================================================
# Stage 7: runtime-dev — development image
# =============================================================================
# Same base + the full module set + a handful of debugging utilities. Use
# this when you're iterating on configuration, capturing pcaps, or want
# any module without going through scripts/build-mod.sh.
FROM debian:${DEBIAN_VERSION}-slim AS runtime-dev

ARG FS_PREFIX
ENV DEBIAN_FRONTEND=noninteractive \
    FS_PREFIX=${FS_PREFIX} \
    PATH="${FS_PREFIX}/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        gosu ca-certificates libcurl4 \
        vim-tiny less procps iproute2 net-tools tcpdump strace lsof file \
    && rm -rf /var/lib/apt/lists/*

COPY --from=prep-dev /runtime-libs/ /usr/lib/
RUN ldconfig

COPY --from=prep-dev ${FS_PREFIX} ${FS_PREFIX}

RUN groupadd -r freeswitch && useradd -r -g freeswitch -d ${FS_PREFIX} freeswitch \
    && chown -R freeswitch:freeswitch ${FS_PREFIX}

COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY entrypoint.d /docker-entrypoint.d
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/healthcheck.sh

EXPOSE 5060/tcp 5060/udp 5061/tcp
EXPOSE 5080/tcp 5080/udp
EXPOSE 8021/tcp
EXPOSE 5066/tcp 7443/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["freeswitch", "-nonat", "-nf"]
