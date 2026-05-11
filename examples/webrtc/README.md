# WebRTC / Verto example

The image already enables `mod_sofia` and the `internal` profile listens on
`5066/tcp` (WS) and `7443/tcp` (WSS) for WebRTC clients. To make this work
in production:

1. Provision a TLS cert/key (Let's Encrypt is the usual choice) and write
   them to `${FS_DATA_DIR}/conf/tls/wss.pem`.
2. Set `FS_EXTERNAL_IP` to the public address that browsers will reach (no
   STUN — browsers don't accept SRFLX from FS for WSS).
3. Open the RTP range (`20000-30000/udp` by default) and `7443/tcp` on
   your firewall.

See the FreeSWITCH docs for full Verto / WebRTC configuration:
<https://developer.signalwire.com/freeswitch/FreeSWITCH-Explained/Modules/mod-verto-1048948/>.

(A complete worked example will land here in a future release. PRs welcome.)
