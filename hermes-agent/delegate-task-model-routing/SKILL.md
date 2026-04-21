---
name: delegate-task-model-routing
description: 如何在 Hermes Agent 的 delegate_task 中实现多模型路由 — MiniMax + DeepSeek 双模型智能路由的正确配置方法。
version: 2.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [delegate_task, model-routing, multi-agent, deepseek]
---

# delegate_task 多模型路由配置

## 路由架构

| 任务类型 | 模型 | Provider | 触发条件 |
|----------|------|----------|----------|
| 简单文本 | MiniMax-M2.7 | minimax-cn | 默认，简单对话/文本 |
| 复杂问题 | deepseek-reasoner | deepseek | 深度推理、复杂调试、算法分析（思考模式） |
| 普通问题 | deepseek-chat | deepseek | 一般问答（非思考模式） |

## 正确用法

### 复杂推理 → DeepSeek Reasoner（思考模式）
```json
{
  "goal": "解释动态规划和贪心算法的核心区别",
  "context": "需要深度算法分析",
  "model": "deepseek-reasoner",
  "provider": "deepseek",
  "toolsets": ["terminal"]
}
```

### 普通问答 → DeepSeek Chat（非思考模式）
```json
{
  "goal": "解释什么是 HTTP 缓存",
  "context": "一般技术问答",
  "model": "deepseek-chat",
  "provider": "deepseek"
}
```

## 常见错误

### ❌ acp_args 不能切换模型
```json
{
  "goal": "任务",
  "acp_args": ["--model", "deepseek-reasoner"]  // 不生效！
}
```
**原因**：模型在 AIAgent 构造时确定，早于 acp_args 处理时机。

### ✅ 正确方式：用 model + provider 字段
```json
{
  "goal": "任务",
  "model": "deepseek-reasoner",
  "provider": "deepseek"
}
```

## Provider 名称对照

| 实际 Provider 名 | 用于 |
|-----------------|------|
| `deepseek` | DeepSeek 模型 |
| `minimax-cn` | MiniMax 模型（默认） |

## 关键发现

1. **.env 不自动继承**：子进程运行时不继承父进程的 .env，需要在 credential 解析时显式加载
2. **Per-task model**：`tasks` 数组中的每个任务可以独立指定不同的 model 和 provider
3. **默认走父级**：如果不指定 model/provider，子代理继承父级的模型配置
4. **DeepSeek 模型区别**：`deepseek-chat` = 非思考模式，`deepseek-reasoner` = 思考模式

## API Key 状态

| Key | 状态 |
|-----|------|
| DEEPSEEK_API_KEY | ✅ 正常 |
| KIMI_API_KEY | ❌ 已删除 |
| MINIMAX_CN_API_KEY | ❌ Connection Error，Key 可能有误 |
