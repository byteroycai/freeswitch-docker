# freeswitch-docker

A production-ready, source-built Docker image for [FreeSWITCH](https://github.com/signalwire/freeswitch) 1.10 with secure defaults, configurable modules, and an extensible startup.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![FreeSWITCH](https://img.shields.io/badge/FreeSWITCH-v1.10-orange)](https://github.com/signalwire/freeswitch)

[简体中文](README.zh-CN.md)

## Quick start

```bash
git clone https://github.com/byteroycai/freeswitch-docker.git
cd freeswitch-docker

./build.sh                    # ~3 min on Apple Silicon native, 30-60 min via QEMU
docker compose --profile host up -d

# Grab the auto-generated passwords from the first start
docker logs freeswitch | grep -E 'Generated (default SIP|ESL) password'
```

Verify:

```bash
docker exec -it freeswitch fs_cli -p '<ESL password>'
fs_cli> status
fs_cli> sofia status
```

## Configuration

All runtime config is via environment variables. See [`.env.example`](.env.example) for the full list; the essentials:

| Variable | Default | Purpose |
|---|---|---|
| `FS_DEFAULT_PASSWORD` | _(random)_ | SIP password for extensions 1000-1019 |
| `FS_DOMAIN` | `localhost` | SIP domain |
| `FS_EXTERNAL_IP` | `auto` | Public IP for SIP/RTP (`auto` = STUN, falls back to container interface IP if STUN fails) |
| `FS_ESL_PASSWORD` | _(random)_ | ESL password |
| `FS_ESL_LISTEN_IP` | `127.0.0.1` | ESL bind interface (loopback by default) |

## Images

A single source build produces three images:

| Tag | Purpose | Size (arm64) |
|---|---|---|
| `freeswitch:builder` | Compile environment, kept for adding modules later via `scripts/build-mod.sh` | ~2 GB |
| `freeswitch:1.10` | **Slim production runtime.** Trimmed module set, no fonts, 8/16 kHz MoH only. | **~290 MB** |
| `freeswitch:1.10-dev` | **Development runtime.** Every compiled module + debug tools (`vim`, `tcpdump`, `strace`, `ss`, `lsof`). | ~830 MB |

The slim image drops these by default:

| Dropped module | Reason |
|---|---|
| `mod_av` | Video / ffmpeg — drops ~300 MB of runtime libs |
| `mod_amr`, `mod_g723_1`, `mod_g729` | Patent-encumbered codecs, opt-in only |
| `mod_pgsql` | Postgres backend, opt-in |
| `mod_dialplan_asterisk` | Only useful when migrating from Asterisk |
| `mod_skinny` | Cisco SCCP, niche |
| `mod_cdr_sqlite` | Redundant with `mod_cdr_csv` |
| `mod_xml_rpc` | HTTP RPC endpoint, common attack target |
| `mod_test`, `mod_valet_parking`, `mod_png`, `mod_xml_scgi` | Niche or rarely used |

`mod_signalwire` and `mod_spandsp` are excluded entirely — they can't compile on the no-token path (the first needs a proprietary lib from SignalWire's gated apt repo, the second expects an older spandsp API than upstream HEAD ships).

The full set is still compiled into `freeswitch:builder`, so you can pull anything back in later via `scripts/build-mod.sh` (see below).

## Build options

```bash
# Enable extra modules at compile time
MODULES_ENABLE="event_handlers/mod_event_zmq" ./build.sh

# Replace the slim image's trim list
MODULES_DISABLE="applications/mod_test xml_int/mod_xml_rpc" ./build.sh

# Build a fat slim (no trimming) — same module set as :1.10-dev minus dev tools
MODULES_DISABLE="" ./build.sh

# Skip the dev image entirely
SKIP_DEV=1 ./build.sh

# Cross-build for x86 from Apple Silicon (or vice versa, via QEMU)
PLATFORM=linux/amd64 ./build.sh

# Enable SignalWire-gated modules (mod_signalwire, premium codecs/voices)
SIGNALWIRE_TOKEN=pat-xxx ./build.sh
```

## Network modes

```bash
# host: best RTP performance, requires no other FreeSWITCH on the host
docker compose --profile host up -d

# bridge: port-mapped, coexists with a host FreeSWITCH (port offsets in .env.example)
docker compose --profile bridge up -d
```

## Adding modules after build

The `freeswitch:builder` image is kept around precisely for this:

```bash
./scripts/build-mod.sh mod_shout freeswitch
# compiles mod_shout.so via the builder, copies it into the running container, loads it via fs_cli
```

## Extending startup without rebuilding

Drop `*.sh` files into the `entrypoint.d/` directory; they are sourced after config initialisation and before FreeSWITCH starts. See [`entrypoint.d/README.md`](entrypoint.d/README.md).

## Examples

- [`examples/callcenter/`](examples/callcenter/) — wire FreeSWITCH up to an external service for dynamic user directory and parked-call takeover via ESL.
- [`examples/webrtc/`](examples/webrtc/) — TLS / Verto / WebRTC notes.

## Security

Read [`SECURITY.md`](SECURITY.md) before exposing FreeSWITCH to the public internet. The defaults are safe for a local test but require hardening for production (TLS, ACLs, fail2ban, real domain certs).

## Contributing

PRs welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

Apache-2.0. FreeSWITCH itself is licensed under MPL-1.1 — see the [upstream repo](https://github.com/signalwire/freeswitch/blob/master/COPYING).
