# freeswitch-docker

源码构建的 [FreeSWITCH](https://github.com/signalwire/freeswitch) 1.10 Docker 镜像，默认安全、模块可裁剪、启动可扩展。

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![FreeSWITCH](https://img.shields.io/badge/FreeSWITCH-v1.10-orange)](https://github.com/signalwire/freeswitch)

[English](README.md)

## 快速开始

```bash
git clone https://github.com/byteroycai/freeswitch-docker.git
cd freeswitch-docker

./build.sh                    # Apple Silicon 原生 ~3 分钟，跨架构 QEMU 30-60 分钟
docker compose --profile host up -d

# 首次启动会生成随机的 SIP / ESL 密码，从日志里捞一下
docker logs freeswitch | grep -E 'Generated (default SIP|ESL) password'
```

验证：

```bash
docker exec -it freeswitch fs_cli -p '<ESL password>'
fs_cli> status
fs_cli> sofia status
```

## 配置

所有运行时配置走环境变量，完整列表见 [`.env.example`](.env.example)。常用的几个：

| 变量 | 默认值 | 用途 |
|---|---|---|
| `FS_DEFAULT_PASSWORD` | _(随机)_ | 分机 1000-1019 的 SIP 密码 |
| `FS_DOMAIN` | `localhost` | SIP 域名 |
| `FS_EXTERNAL_IP` | `auto` | SIP/RTP 公网地址（`auto` 走 STUN；STUN 不通时退化到容器接口地址）|
| `FS_ESL_PASSWORD` | _(随机)_ | ESL 密码 |
| `FS_ESL_LISTEN_IP` | `127.0.0.1` | ESL 绑定地址（默认仅本机）|

## 镜像

一次编译产出三个镜像：

| Tag | 用途 | 大小（arm64） |
|---|---|---|
| `freeswitch:builder` | 编译环境，保留下来可以通过 `scripts/build-mod.sh` 增量编译模块 | ~2 GB |
| `freeswitch:1.10` | **生产精简版**。裁剪过的模块集、无字体、保留 8/16 kHz MoH。 | **~290 MB** |
| `freeswitch:1.10-dev` | **开发版**。全模块 + 调试工具（`vim`、`tcpdump`、`strace`、`ss`、`lsof`）。 | ~830 MB |

精简版默认去掉的模块：

| 模块 | 原因 |
|---|---|
| `mod_av` | 视频 / ffmpeg —— 减少 ~300 MB 运行时库 |
| `mod_amr`, `mod_g723_1`, `mod_g729` | 专利受限编解码，按需启用 |
| `mod_pgsql` | Postgres 后端，按需启用 |
| `mod_dialplan_asterisk` | 仅 Asterisk 迁移场景需要 |
| `mod_skinny` | Cisco SCCP，小众 |
| `mod_cdr_sqlite` | 跟 `mod_cdr_csv` 功能重叠 |
| `mod_xml_rpc` | HTTP RPC，常见攻击面 |
| `mod_test`, `mod_valet_parking`, `mod_png`, `mod_xml_scgi` | 小众或极少使用 |

`mod_signalwire` 和 `mod_spandsp` 直接不编译——前者依赖 SignalWire 私仓的专有库，后者跟 `freeswitch/spandsp` HEAD API 不兼容（FS 1.10 的源码还在用旧 API）。

全集模块都编进了 `freeswitch:builder` 里，需要把哪个拉回来用 `scripts/build-mod.sh` 后处理就行。

## 构建选项

```bash
# 编译时启用额外模块
MODULES_ENABLE="event_handlers/mod_event_zmq" ./build.sh

# 改写精简镜像的裁剪清单
MODULES_DISABLE="applications/mod_test xml_int/mod_xml_rpc" ./build.sh

# 全量精简（不裁剪）——和 :1.10-dev 模块一致但没调试工具
MODULES_DISABLE="" ./build.sh

# 跳过 dev 镜像
SKIP_DEV=1 ./build.sh

# 跨架构构建（QEMU）
PLATFORM=linux/amd64 ./build.sh

# 启用 SignalWire 私仓的模块（mod_signalwire、付费 codec / 语音包）
SIGNALWIRE_TOKEN=pat-xxx ./build.sh
```

## 网络模式

```bash
# host: 独占宿主机，RTP 性能最好
docker compose --profile host up -d

# bridge: 端口映射，可以和宿主机已有 FreeSWITCH 共存（端口偏移见 .env.example）
docker compose --profile bridge up -d
```

## 编译额外模块

`freeswitch:builder` 留着就是干这个用的：

```bash
./scripts/build-mod.sh mod_shout freeswitch
# 在 builder 镜像里编出 mod_shout.so，拷进运行中容器，fs_cli 加载
```

## 启动钩子（不用重建镜像）

把 `*.sh` 文件丢到 `entrypoint.d/` 目录，配置初始化之后、FreeSWITCH 启动之前会被 source 进来。详见 [`entrypoint.d/README.md`](entrypoint.d/README.md)。

## 示例

- [`examples/callcenter/`](examples/callcenter/) —— FreeSWITCH 接外部服务做动态用户目录 + 通过 ESL 接管 parked 通话。
- [`examples/webrtc/`](examples/webrtc/) —— TLS / Verto / WebRTC 配置参考。

## 安全

把 FreeSWITCH 暴露到公网前请读一下 [`SECURITY.md`](SECURITY.md)。默认配置只适合本地测试，生产环境还需要做 TLS、ACL、fail2ban、正式域名证书等加固。

## 贡献

欢迎 PR，参见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## License

Apache-2.0。FreeSWITCH 本体走 MPL-1.1 —— 详见[上游仓库](https://github.com/signalwire/freeswitch/blob/master/COPYING)。
