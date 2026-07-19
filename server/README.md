# ArkDO 推送中继

把 linux.do(Discourse)的 Web Push 转成华为 Push Kit 通知,让 ArkDO 在**关闭状态**下也能收到回复 / @ / 私信提醒。

```
linux.do ──Web Push(RFC8291 加密)──▶ 本中继 ──解密──▶ 华为 Push Kit ──▶ 设备通知
                                        ▲
                                        └── ArkDO 注册订阅(/subscription/ensure)
```

**原理**:Discourse 的 Web Push 是标准协议,订阅时的 `endpoint`/`p256dh`/`auth` 全由订阅方提供。把 `endpoint` 填成本中继地址、密钥用中继自己生成的,Discourse 就会用**我们的公钥**加密并投递到**我们的地址**。linux.do 的 VAPID 密钥只用于签名,与中继无关。

---

## ⚠️ 先读这一段:隐私责任

**中继能看到经过它的每一条通知明文**——包括私信的标题与摘要。

- 只部署给**你自己和你信任的用户**用,别拿它替陌生人转发通知。
- 日志默认**不记录**通知内容(`RELAY_LOG_CONTENT` 关闭),排障时才临时打开,查完关掉。
- `subs.json` 里存着每条订阅的 Web Push **私钥**和设备 token,权限务必 600。
- 中继**不持有**任何人的 linux.do 账号密码或 session:订阅由 App 用自己的登录态完成,中继只负责收加密包。

---

## 依赖

- 一台有公网 IP 的 Linux 服务器(1 核 / 512M 足够,中继常驻内存约 16MB)
- Python 3.8+ 与 `cryptography` 库(Ubuntu 22.04 自带,无需 pip)
- 一个**独立域名**(见下方安全提示)+ 反向代理(推荐 Caddy,自动签证书)
- 华为 AGC 账号,应用已开通 Push Kit

> **域名安全提示**:中继地址会随开源 App 公开,而证书透明度日志(crt.sh)可按主域枚举出全部子域。
> 若中继与你其它服务共用主域,等于把同域下的一切(如自建 DoH)一并暴露。**请用独立域名。**

---

## 部署

### 1. 放置程序

```bash
sudo mkdir -p /opt/wp-relay
sudo cp relay.py /opt/wp-relay/
sudo chown -R <运行用户>:<运行用户> /opt/wp-relay
```

### 2. 配置

```bash
sudo cp wp-relay.env.example /etc/wp-relay.env
sudo chmod 640 /etc/wp-relay.env
sudo chown root:<运行用户> /etc/wp-relay.env
sudo vi /etc/wp-relay.env      # 至少填 RELAY_PUBLIC_BASE
```

`RELAY_PUBLIC_BASE` 是**必填**的:它会被拼进订阅 endpoint 交给 Discourse,漏填中继会拒绝启动。

### 3. 华为 Push Kit 凭据

AGC → 项目设置 → **服务账号密钥** → 下载 JSON:

```bash
sudo cp <下载的>.json /etc/wp-relay-service-account.json
sudo chmod 640 /etc/wp-relay-service-account.json
sudo chown root:<运行用户> /etc/wp-relay-service-account.json
```

把路径和项目 ID 填进 `/etc/wp-relay.env`。

> 不配 Push Kit 也能启动,此时中继只解密不下发——可用于先单独验证 "Discourse → 中继" 这一段是否打通。

### 4. 消息分类权益

华为对**每一条** `messages:send` 都校验 `category` 权益,需先在 AGC 申请并通过审核。

| 通知 | 分类 | 配置项 |
|---|---|---|
| 私信、邀请进私信 | 即时聊天(IM) | `PUSHKIT_CATEGORY` |
| 回复 / @ / 点赞等 | 订阅类 | `PUSHKIT_CATEGORY_DEFAULT` |

`PUSHKIT_CATEGORY_DEFAULT` 留空则全部回落到 `PUSHKIT_CATEGORY`。**建议按上表分流**——把"点赞"当即时聊天推属于滥用高权益分类,长期可能被收回权益。

### 5. 反向代理

参考 `Caddyfile.example`,把 `/wp/*`、`/subscription/*`、`/register` 转发到 `127.0.0.1:8787`,其余 404。

### 6. 启动

```bash
sudo cp wp-relay.service /etc/systemd/system/
sudo vi /etc/systemd/system/wp-relay.service   # 改 User 为你的运行用户
sudo systemctl daemon-reload
sudo systemctl enable --now wp-relay
curl https://push.example.com/wp/health         # 应返回 {"ok": true}
```

### 7. 配置 App

在 App 仓库建 `entry/src/main/resources/rawfile/relay-config.json`(该文件已被 gitignore,不会入库):

```json
{ "baseUrl": "https://push.example.com", "apiKey": "<与 RELAY_API_KEY 相同>" }
```

模板见 `entry/src/main/resources/rawfile/relay-config.example.json`。用户也可在 App 设置里手动填中继地址,此时**不会**发送随包的 apiKey(密钥只属于随包配置的中继,绝不发往用户自填的第三方地址)。

---

## 接口

| 路由 | 用途 | 鉴权 |
|---|---|---|
| `POST /subscription/ensure` | 上报设备 token,幂等地取回订阅参数 | API Key + 限流 |
| `POST /subscription/disable` | 停用订阅 | 同上 |
| `POST /subscription/test` | 直接向该设备发一条测试通知 | 同上 |
| `POST /wp/:subId` | **Discourse 投递入口** | **无**(见下) |
| `GET /wp/health` | 健康检查 | 无 |
| `GET /wp/probe` | 可预览探针,用于验证 Discourse 能否出站访问本中继 | 无 |

### `/wp/:subId` 为什么不能加鉴权和限流

它是 Discourse 主动来投递的入口——对方**不会**带我们的 API Key,也不该被限流拦下。更关键的是它的响应码直接决定订阅存亡:

| 情况 | 返回 | Discourse 行为 |
|---|---|---|
| 正常 | **201**(立即 ack,再异步解密转发) | 保留订阅 |
| 订阅已停用 | **410 Gone** | **自动删除**该订阅 |
| 未知 subId | **404** | 同上 |
| 连续报错超 1 天 | — | 达到 `MAX_ERRORS` 后删除订阅 |

所以中继必须**先回 201 再干活**,把 Push Kit 的失败在内部消化,绝不暴露给 Discourse。
反过来也可利用:想注销一条订阅,只要让它返回 410/404,Discourse 下次投递时会自行清理。

---

## 运维

```bash
# 日志(关键行:PUSH ... OK / PUSHKIT ... sent code=80000000)
tail -f /opt/wp-relay/relay.log

# 订阅库。中继每次请求都重读该文件,改完无需重启;改前先备份。
cp /opt/wp-relay/subs.json /opt/wp-relay/subs.json.bak.$(date +%Y%m%d_%H%M%S)
```

- **清理某条订阅**:把它的 `enabled` 置 `false`(下次投递返回 410,Discourse 自行删除),或直接删掉该条(返回 404,同样效果)。
- **`code=80000000`** 表示 Push Kit 下发成功;其它码见华为文档。
- 中继宕机超过一天,Discourse 会因连续投递失败删掉订阅。App 侧有启动保活会重新注册,但仍建议加健康监控。

---

## 已知行为(不是 bug)

1. **10 分钟在线抑制**:Discourse 的 `push_notification_time_window_mins`(默认 10)——用户最近活跃过就不推。ArkDO 是 webview 壳,前台刷接口即算"在线",因此系统推送定位为「App 不在用时的召回」,在用时由应用内红点负责。这是服务端设置,改不了。
2. **推送总闸**:用户偏好设置里的「实时通知」(`push_notification_level`)若为"已禁用",服务端**源头就不发**,中继再完美也收不到。排查"收不到推送"请先查这一项。
3. **`send_confirmation` 不可靠**:部分站点(含 linux.do)不投递订阅确认推送,别拿它判断链路是否打通,以真实通知为准。
4. **payload 不含 `notification_id`**:Discourse 发来的只有 `{title, body, badge, icon, tag, base_url, url}`。中继按 `icon` 文件名反推通知类型来分流消息分类;App 侧则用 `topic_id`+`post_number` 反查通知 id 来标记已读。
