# Cloudflare Challenge Debug Notes

## 背景

ArkDO 的 Linux.do API 请求统一走 ArkWeb 环境内的 `fetch`。当任意 API 返回 Cloudflare challenge、403、429 或非预期 HTML 时，`ArkWebNetworkBridge` 会发布全局 challenge 事件，`RootTabPage` 统一弹出 `CfChallengePage` 可见验证 sheet。

这个场景还没有完全验证稳定性。曾出现过一次：

- 首页进入后触发 Cloudflare challenge。
- Root 只弹出了一次 challenge sheet。
- sheet 内部的 ArkWeb 内容停留在 Linux.do / Cloudflare 验证视觉页。
- 用户勾选验证后，页面内部过一段时间又重新显示验证内容。
- 从用户观察看，不是 sheet 重复打开，而是 sheet 内 Web 内容反复进入 challenge。
- 随后再次复现时，App 又能直接进入，不再触发 challenge。

因此目前判断：该问题可能依赖 Cloudflare 临时风控状态、IP、设备证明、会话 Cookie 写入时序或 ArkWeb Cookie 可见性，尚未稳定复现。

## 已加诊断日志

统一关键字：

```text
ARKDO_CF_DIAG
```

过滤这个关键字即可看到 challenge 关键链路。日志不会输出 Cookie 明文，也不会输出 Cloudflare challenge token 的完整 URL。

关键阶段：

- `eventBusNotify`：`ArkWebNetworkBridge` 检测到 challenge，并发布全局事件。
- `rootChallengeRequired`：`RootTabPage` 收到 challenge 事件。
- `rootChallengeOpen`：Root 打开 challenge sheet。
- `appear`：`CfChallengePage` 出现。
- `pageBegin` / `pageEnd`：验证页 ArkWeb 页面开始/结束加载。
- `httpError`：验证页 ArkWeb 收到 HTTP 错误。
- `loadError`：验证页 ArkWeb 收到加载错误。
- `pollStart`：开始轮询 `cf_clearance` 可见性。
- `pollPending`：轮询中，记录轮询次数和 Cookie header 长度。
- `resolvedByCookie`：当前实现通过可见 `cf_clearance` 判断验证完成。
- `rootChallengeResolved`：Root 收到验证完成，关闭 sheet，并广播会话变化。

## 下次复现时需要复制的日志

复现时在日志里过滤：

```text
ARKDO_CF_DIAG
```

复制范围：

1. 从第一次出现 `stage=eventBusNotify` 开始。
2. 包含 `stage=rootChallengeOpen`。
3. 包含进入验证页后的全部 `pageBegin`、`pageEnd`、`httpError`、`pollPending`。
4. 包含用户勾选验证之后 20 到 40 秒内的所有 `ARKDO_CF_DIAG` 日志。
5. 如果出现 `resolvedByCookie` 或 `rootChallengeResolved`，也一起复制。

重点看这些字段：

- `hasCfClearance` 是否从 `false` 变成 `true`。
- `cookieHeaderLength` 是否变化。
- `pageBegin/pageEnd url` 是否从 `linuxdo_challenge` 变成 `linuxdo_home` 或 `linuxdo_other`。
- 是否持续出现 `httpError url=cloudflare_challenge_resource status=401`。
- Root 是否只出现一次 `rootChallengeOpen`，还是多次出现。

## 当前待验证假设

1. `cf_clearance` 可能已经写入 WebView 内部，但 `fetchCookieSync(AppConstants.BASE_URL, false)` 没有立刻读到，导致 `CfChallengePage` 不关闭。
2. Cloudflare challenge 页面验证后没有跳转离开 `/challenge`，视觉上停留在盾牌页；当前只靠 cookie 可见性判断完成，所以可能卡住。
3. Cloudflare 的 PAT / 设备证明资源可能持续返回 401，页面内部周期性重试，导致用户看到反复验证。
4. 隐藏 `ArkWebHost` 或首页刷新在验证期间继续发请求，返回 challenge 后发布新的事件；Root 当前会防止重复开 sheet，但 Web 内容仍可能被 Cloudflare 自身循环刷新。

## 后续可能的修复方向

如果日志证明 `cf_clearance` 读不到，但验证后 API 已经可访问，应改为“API 探测成功”作为最终完成条件：

```text
CfChallengePage 可见验证中
  -> 定时通过共享 ArkWebNetworkBridge 请求 /latest.json
  -> 如果返回 JSON 200，认为验证完成
  -> 关闭 challenge sheet
  -> SessionEventBus.notifySessionChanged()
```

这样不只依赖 Cookie 可见性，而是用“真实 API 已可访问”判断 Cloudflare 是否通过。

如果日志证明 Cloudflare challenge 资源持续 401 且 API 也不可访问，则暂不做自动绕过；继续保留可见验证页，让用户完成真实验证，并根据日志判断是否需要调整加载 URL，例如从 `https://linux.do/challenge` 改为 `https://linux.do/`。

## 约束

- 不打印 Cookie、Token、`cf_clearance` 明文。
- 不实现 Cloudflare 私有 `/cdn-cgi/challenge-platform/.../rc/...` 拦截。
- 不做隐藏自动绕过人机验证。
- 所有 Linux.do API 触发的 challenge 仍由全局 challenge 事件统一处理。
