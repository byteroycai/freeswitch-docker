# Callcenter integration example

Wire FreeSWITCH up to an external service that:

1. Serves the SIP user directory dynamically via `mod_xml_curl`.
2. Receives inbound calls parked by the dialplan, then takes them over via
   ESL (IVR, queueing, agent routing).

## Files

- `dialplan.xml` — drop into `conf/dialplan/` (or mount over it). Routes
  4-digit inbound numbers in the `10xx` range to `park`, where your ESL
  client subscribes to `CHANNEL_PARK` and takes over.
- `xml_curl.conf.xml` — drop into `conf/autoload_configs/`. Tells
  `mod_xml_curl` where to fetch directory entries from.

## Usage with bind-mounted config

```bash
cp examples/callcenter/dialplan.xml       ${FS_DATA_DIR}/conf/dialplan/callcenter.xml
cp examples/callcenter/xml_curl.conf.xml  ${FS_DATA_DIR}/conf/autoload_configs/
# Then edit xml_curl.conf.xml to point at your service URL.
```

## Usage with entrypoint hook (no bind mount)

Drop `99-callcenter.sh` into `entrypoint.d/`:

```bash
#!/usr/bin/env bash
: "${CALLCENTER_URL:?CALLCENTER_URL must be set}"

cat > "${FS_PREFIX}/conf/autoload_configs/xml_curl.conf.xml" <<XML
<configuration name="xml_curl.conf" description="cURL XML Gateway">
  <bindings>
    <binding name="directory">
      <param name="gateway-url" value="${CALLCENTER_URL}/api/v1/freeswitch/directory"/>
      <param name="bindings" value="directory"/>
    </binding>
  </bindings>
</configuration>
XML

cp /examples/callcenter/dialplan.xml "${FS_PREFIX}/conf/dialplan/callcenter.xml"
```

(Mount `examples/` into the container if you go this route.)
