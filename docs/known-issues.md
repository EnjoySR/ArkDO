# 待解决问题记录

> 本文件记录已发现、待后续专门处理的问题。图标相关改动不在此列（已单独处理）。

## 问题 1：首页加载帖子列表时出现两个 loading

**现象**
「正在准备 ArkWeb 请求环境」提示结束、进入首页加载帖子列表阶段后，界面上同时出现两个转圈动画：一个在标题栏下方居中偏上，一个在页面垂直居中位置（带「正在加载最新帖子」文字）。

**根因**
`entry/src/main/ets/views/pages/HomePage.ets` 的 `refreshLatestTopics()` 中，首次加载时同时把两个状态置真：
- `this.isRefreshing = true`（约 `HomePage.ets:208`）→ 驱动顶部 `Refresh` 组件的转圈指示器；
- `this.isInitialLoading = this.topics.length === 0`（约 `HomePage.ets:209`）→ 列表为空时驱动中间的 `LoadingProgress`。

两者同时为 true，导致上下各出现一个 loading。

**期望**
首次加载（列表为空）只显示中间的主 loading，不触发顶部刷新指示器；下拉刷新（已有数据）时才用顶部 `Refresh` 指示器。两者互斥，任何时刻只出现一个 loading。

---

## 问题 2：加载失败文案不友好，且缺少明显的重试入口

**现象**
- 加载失败时界面显示「ArkWeb 请求失败」等技术文案，对用户不友好。
- 失败后没有明显的重试按钮，只能通过下拉刷新重试，入口不明显。

**根因**
- `HomePage.ets` 约 229 行直接把底层 `result.error.message` 透传到界面，而该文案来自 `ArkWebNetworkBridge.ets:171` 的 `'ArkWeb 请求失败。'`，属于底层技术错误文案泄漏到 UI。
- 空态区域只有一段文字，没有任何操作按钮。

**期望**
- 失败时展示对用户友好的提示文案（隐藏「ArkWeb」等内部实现词）。
- 在空态区域提供一个明显的「重试」按钮，点击后重新发起加载。
