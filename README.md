# Darling File（闪传）

局域网 + 跨网文件传输工具：桌面端（Linux / Windows）支持局域网自动发现与 IP 直连，网页版走官方中转 WS 管道跨网闪传。桌面端与网页版协议互通（同一会话口令）。

## 在线地址

| 入口 | 地址 |
|---|---|
| 网页版（免安装，浏览器直开） | https://file.darling02.de5.net/ |
| 中转服务 | https://relay.darling02.de5.net/ |
| 账号服务 | https://api.darling02.de5.net/ |

## 目录结构

```
Darling-File/
├── app/                 Flutter 客户端
│   ├── lib/web_main.dart    网页版 UI（发送/接收/网页分享/历史/账号）
│   ├── lib/core_web.dart    网页版传输核心（RelayFile、relayStartSend/Recv）
│   ├── lib/main.dart        桌面版（Linux/Windows）
│   ├── lib/pages.dart       桌面端文件页
│   ├── lib/mobile.dart      移动端（未发布）
│   └── build/web/           web release 产物
├── backend/             Python 传输核心（darl_file.py 等）
├── deploy-web/          Cloudflare Workers assets 部署目录
├── tools/               构建日志与验证脚本
```

## 网页版构建与部署

```bash
# 构建（在 app/ 下）
~/flutter/bin/flutter build web -t lib/web_main.dart --release

# 部署（项目根）
rm -rf deploy-web/web && cp -r app/build/web deploy-web/web
cd deploy-web && CLOUDFLARE_API_TOKEN=<cfat-token> npx wrangler deploy
# 自定义域 file.darling02.de5.net，wrangler.toml: assets={directory="./web"}（无 binding）

# 验证（注意：本机 curl 默认走代理会大文件断连，必须绕过）
curl --noproxy '*' --max-time 60 -o /tmp/w.js https://file.darling02.de5.net/main.dart.js
# 大小应与本地 build/web/main.dart.js 一致（约 2.6MB）
```

## 中转协议（网页版 ↔ 桌面版互通）

- POST `$relay/api/session`（Bearer 登录 token）→ `{ok, code(6位大写), wsUrl, sessionId, url}`
- GET `$relay/api/session/{code}` 免登录查口令 → `{wsUrl}`
- WS 连接 `{wsUrl}?role=send|recv`
  - 发送端：等 `ready` → 逐文件发 `meta{id,name,size}` → 按 32768B 切片发二进制 → `done{id}` → 收 `ack{id}` → 结束发 `end`
  - 接收端：连上后发 `{"ready":true}` → 收 `meta` 建 `Uint8List(size)` → 二进制块 `setRange` → 收 `done` 回 `ack` → 全部完成后可下载

## 桌面端构建（Linux）

依赖：`clang cmake ninja-build libgtk-3-dev pkg-config`。在 app/ 下 `~/flutter/bin/flutter build linux --release`，产物打包 tar.gz（PyInstaller 打包 Python 核心时禁 exclude `email`）。

## 浏览器限制说明

网页版运行在浏览器里，无法监听端口 / 扫描局域网 / 开 UDP，所以统一走官方中转（数据不落服务器）。局域网扫描 / IP 直连只在桌面端支持。
