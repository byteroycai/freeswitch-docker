# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial project scaffold.
- Multi-stage Dockerfile (Debian bookworm) building FreeSWITCH 1.10 from
  source, producing a `builder` and a slim `runtime` image.
- Optional SignalWire token path via BuildKit secret; default build uses
  Debian main-repo packages only (no token required). Pre-builds
  `libks`, `spandsp`, and `sofia-sip` from upstream sources for the
  no-token path.
- Configurable module set via `MODULES_ENABLE` / `MODULES_DISABLE` build
  args. `mod_signalwire` and `mod_spandsp` are disabled at compile time
  in the no-token path: the former needs SignalWire's proprietary
  `signalwire-client-c2`, and the latter expects an older spandsp API
  than upstream HEAD ships.
- Two runtime image variants from a single FreeSWITCH compile:
    - `freeswitch:1.10` (slim, ~290 MB on arm64) ships a trimmed module
      set — drops `mod_av`, patent-encumbered codecs, mod_pgsql, mod_skinny,
      mod_xml_rpc/scgi, etc. Also drops 32/48 kHz MoH and the video font
      pack. Production default.
    - `freeswitch:1.10-dev` (~830 MB) keeps the full compiled module set
      plus `vim`, `tcpdump`, `strace`, `ss`, `lsof`. Use for iteration
      and debugging.
- Disabled-module `<load/>` entries are stripped from `modules.conf.xml`,
  `pre_load_modules.conf.xml`, and `post_load_modules.conf.xml` so
  FreeSWITCH doesn't log CRIT errors trying to load missing `.so` files.
- Entrypoint:
    - Randomises `FS_DEFAULT_PASSWORD` and `FS_ESL_PASSWORD` if left at
      defaults; prints generated values to stdout on first start.
    - Detects when STUN is unreachable on `FS_EXTERNAL_IP=auto` and
      falls back to the container's primary interface address, so
      `mod_sofia` can still start in offline / firewalled environments.
    - Binds ESL to `127.0.0.1` by default (`FS_ESL_LISTEN_IP`).
    - Snapshots and restores default config to handle empty volumes.
    - Sources `*.sh` hooks from `/docker-entrypoint.d/` for runtime
      extension without rebuilds.
    - Drops to the `freeswitch` user via `gosu`.
- `docker-compose.yml` (dev), `docker-compose.prod.yml` (named volumes),
  `docker-compose.prod.bind.yml` (bind-mount), each with `host` and
  `bridge` profiles.
- `scripts/build-mod.sh` to compile and inject extra modules using the
  retained `builder` image.
- Example: callcenter integration (`mod_xml_curl` directory + park-based
  ESL takeover).
- GitHub Actions: lint (hadolint + shellcheck), build verification, and
  multi-arch release.
