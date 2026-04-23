---
name: delegate-task-model-routing
description: 如何在 Hermes Agent 的 delegate_task 中实现多模型路由 — MiniMax + DeepSeek 双模型智能路由的正确配置方法。
version: 2.2.0  # 修复：run_agent.py 两处 delegate_task 调用均已补全 model/provider 参数
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [delegate_task, model-routing, multi-agent, deepseek]
---

# delegate_task 多模型路由配置

## 用户指定路由规则

| 任务类型 | 模型 | Provider | 触发条件 |
|----------|------|----------|----------|
| 文本/图片输入（默认） | MiniMax-M2.7 | minimax-cn | 默认，所有文本对话 |
| 视频输入 | 不支持 | — | 收到视频时提示"暂不支持视频输入" |
| minimax-cn 拥塞/失败 | deepseek-reasoner V3.2 | deepseek | 429 / 402 / 529 / 503 等错误触发 fallback_chain 自动切换 |
| **关键词触发** | deepseek-reasoner V3.2 | deepseek | 用户消息包含以下关键词之一 |

### 关键词触发规则

**触发关键词**（出现任意一个即路由到 deepseek-reasoner）：
- `深度调查`
- `深度研究`
- `调用deepseek`

**实现方式**：主agent在处理消息时，**检测到上述关键词，立即通过 `delegate_task(goal=..., model='deepseek-reasoner', provider='deepseek')` 委托给 deepseek 子agent处理**，不再继续用 minimax 处理。

**重要**：图片走 MiniMax 视觉，不用 Kimi。deepseek-reasoner = DeepSeek V3.2（思考型）。

## 已实现状态

| 功能 | 状态 | 位置 |
|------|------|------|
| 视频拦截 | ✅ 已实现 | `gateway/platforms/feishu.py` 入口处拦截 |
| 主agent默认minimax m2.7 | ✅ 已实现 | `config.yaml` model/provider 配置 |
| minimax拥塞→deepseek自动切换 | ✅ 已实现（529 bug 已修复） | error_classifier.py + run_agent.py |
| delegate_task model/provider 参数透传 | ✅ 已修复 | `run_agent.py` 两处调用均已补全 |
| 关键词触发→deepseek-reasoner | ✅ 已确定方案 | 出现"深度调查"/"深度研究"/"调用deepseek"立即delegate |

## ⚠️ 关键Bug：run_agent.py 两处 delegate_task 调用漏传 model/provider

`delegate_tool.py` 的 `DELEGATE_TASK_SCHEMA` 已正确定义 `model` 和 `provider` 参数，
但 `run_agent.py` 调用 `_delegate_task()` 时**两处都漏传了这两个参数**，导致子agent始终继承父级模型。

**修复已应用**（检查以下两处是否都有 model/provider）：

```python
# run_agent.py — 两处调用 delegate_task，均需包含：
model=function_args.get("model"),
provider=function_args.get("provider"),
acp_command=function_args.get("acp_command"),
acp_args=function_args.get("acp_args"),
```

**验证方法**：
```bash
grep -A 15 'function_name == "delegate_task":' /home/lighthouse/.hermes/hermes-agent/run_agent.py
```
确认输出包含 `model=function_args.get("model")` 和 `provider=function_args.get("provider")`。

## ⚠️ .pyc 缓存导致代码更新后仍跑旧版本

重启多次 gateway 仍使用旧代码 → 清理 `.pyc` 缓存：
```bash
find /home/lighthouse/.hermes/hermes-agent -path "*/venv" -prune -o -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
```
清理后需重启 gateway 进程使其重新编译。

## fallback_model 配置

```yaml
# config.yaml
fallback_model:
  provider: deepseek
  model: deepseek-reasoner
```
触发：minimax-cn 返回 429/402/529/503 等错误时，fallback_chain 自动切换到 deepseek-reasoner。

## ⚠️ 重要Bug：HTTP 529 不触发 failover（已修复）

**问题现象**：MiniMax 频繁返回 HTTP 529（"当前时段请求拥挤"），但 Hermes 始终重试 3 次后直接报错退出，从不切换到 DeepSeek。

**根因定位过程**：
1. 检查日志确认 529 重复出现：`grep 529 ~/.hermes/logs/agent.log`
2. 检查 `error_classifier.py` 第 509 行：`status_code in (503, 529)` → 分类为 `overloaded`，但 `should_fallback=True` **缺失**（默认为 False）
3. 检查 `run_agent.py` 第 10531 行：eager failover 条件只包含 `rate_limit` 和 `billing`，**不含 `overloaded`**

**两处修复**（已应用）：

```python
# 修复1: error_classifier.py — overloaded 添加 should_fallback=True
if status_code in (503, 529):
    return result_fn(FailoverReason.overloaded, retryable=True, should_fallback=True)
#                                                         ↑ 原本缺失

# 修复2: run_agent.py — overloaded 加入 eager failover 条件
is_rate_limited = classified.reason in (
    FailoverReason.rate_limit,
    FailoverReason.billing,
    FailoverReason.overloaded,   # ← 新增
)
```

**重启生效**：
```bash
systemctl --user restart hermes-gateway
# 或清理 pyc 缓存后重启
find ~/.hermes/hermes-agent -path "*/venv" -prune -o -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
```

## ⚠️ delegation.model 空字符串导致 boot-md 失败

config.yaml 中 `delegation.model: ''`（空字符串）会导致 boot-md hook 运行时 API 报 `invalid params, unknown model '' (2013)`。

**根因**：空字符串 `''` 被当作有效 model 传入，而不是 None（继承父级）。

**修复方案**：将 `delegation.model` 留空（不写）或明确写为 `null`：
```yaml
delegation:
  model: null   # 不要写 ''，会触发 unknown model 错误
  provider: ''
```

## Live 测试验证结果（2026-04-22）

通过 `delegate_task(goal='...', model='deepseek-reasoner', provider='deepseek')` 实际触发验证：

```
[DELEGATE_TOOL] FINAL CHECK: model='deepseek-reasoner' provider='deepseek'
[delegate_tool] _build_child_agent: model='deepseek-reasoner' override_provider='deepseek' 
    → effective_model='deepseek-reasoner' effective_provider='deepseek'
Auxiliary auto-detect: using main provider deepseek (deepseek-reasoner)
```

子 agent 返回确认：`deepseek-reasoner` + `deepseek` ✅

**结论**：代码层面的所有修复（run_agent.py 参数透传、.pyc 缓存清理）在 live 环境均已验证有效。

## 待实现项

1. **关键词触发路由**：在 `run_agent.py` 或 `delegate_tool.py` 中实现关键词检测逻辑——当用户消息包含"深度调查"、"深度研究"、"调用deepseek"时，自动调用 `delegate_task(..., model='deepseek-reasoner', provider='deepseek')`

## Provider 名称对照

| Provider 名 | 说明 |
|-------------|------|
| `deepseek` | DeepSeek 模型（deepseek-chat, deepseek-reasoner） |
| `minimax-cn` | MiniMax 中国版模型（MiniMax-M2.7） |

## API Key 状态

| Key | 状态 |
|-----|------|
| MINIMAX_CN_API_KEY | ✅ 正常 |
| DEEPSEEK_API_KEY | ✅ 正常 |
| DEEPSEEK_API_KEY | ✅ 正常（deepseek） |
