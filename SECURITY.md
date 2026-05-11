# Security

## Reporting a vulnerability

Open a [security advisory](https://github.com/byteroycai/freeswitch-docker/security/advisories/new) — do not file a public issue. A maintainer will respond within 7 days.

## Default posture

| Aspect | Default behaviour | Notes |
|---|---|---|
| SIP password (`1000-1019`) | Randomised on first start | Override with `FS_DEFAULT_PASSWORD` |
| ESL password | Randomised on first start | Override with `FS_ESL_PASSWORD` |
| ESL bind | `127.0.0.1` (loopback only) | Override with `FS_ESL_LISTEN_IP` |
| Process user | `freeswitch` (non-root) | Enforced by `gosu` in entrypoint |
| Image base | `debian:bookworm-slim` | Minimal runtime libs only |
| Healthcheck | `fs_cli status` | Exits non-zero if FS is not `UP` |

The generated passwords are printed to container stdout **once** on first
start. Save them or set the env vars explicitly before the first run.

## Production hardening checklist

### 1. Network exposure

- **Never expose ESL (`8021`) to the public internet.** Keep
  `FS_ESL_LISTEN_IP=127.0.0.1` or use a private overlay network.
- Open only the SIP / RTP / WS ports you actually use. The image `EXPOSE`s
  the full set for convenience; restrict at the firewall layer.
- Prefer `--profile host` on dedicated hosts so RTP doesn't traverse the
  Docker bridge NAT.

### 2. Authentication

- SIP profiles default to `auth-calls=true` — keep it that way for any
  internet-facing profile.
- Rotate the generated default password before going live. The
  `1000-1019` extensions are demo accounts; create your own and disable
  the vanilla set.

### 3. Module surface

The default module set is intentionally small. Avoid enabling these unless
you actually need them:

| Module | Risk |
|---|---|
| `mod_xml_rpc` | Exposes an HTTP API on `8080/tcp`, often left open by mistake |
| `mod_event_socket` (public bind) | Full ESL = full RCE if the password leaks |
| `mod_shell_stream` | Executes shell commands from dialplan |
| `mod_lua` / `mod_python3` | Scripting languages — only enable if you write the scripts |

### 4. The `system` API

FreeSWITCH ships `system` and `bg_system` API commands as part of
`mod_commands`. There is **no compile-time or runtime toggle** to disable
them in vanilla 1.10 — anyone with ESL access (or who can submit chat /
event messages that reach `mod_commands`) can run arbitrary shell commands
as the `freeswitch` user.

Mitigation:

1. Keep ESL on loopback (default).
2. Use a strong (or generated) ESL password.
3. Place `mod_commands` behind a tight `acl.conf.xml` if you expose any
   API surface to the network.
4. Run the container as a non-root user (we already do).

### 5. TLS

- Generate real certs for `wss.pem` and `agent.pem` — the bundled
  self-signed cert is a placeholder.
- Use modern ciphers; the upstream defaults are reasonable as of
  FreeSWITCH 1.10.11+.

### 6. Fail2ban

The bundled image does not include fail2ban. Run it on the host (or in a
sidecar) and point its FreeSWITCH filter at the mounted log directory
(`fs-logs` volume → `/var/log/freeswitch/freeswitch.log`).

A sample filter targeting registration brute-force is in the FreeSWITCH
wiki: <https://developer.signalwire.com/freeswitch/FreeSWITCH-Explained/Introduction/Securing-FreeSWITCH_5832479/>.

### 7. SignalWire token (build-time)

If you build with `SIGNALWIRE_TOKEN=...`, the token is mounted as a
BuildKit secret and never persisted in any image layer. Don't commit
`.signalwire_token` — it's gitignored, but worth verifying.
