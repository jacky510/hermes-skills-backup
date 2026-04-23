---
name: minimax-mcp-debug
description: MiniMax MCP 包调试笔记 - 如何诊断 API 层 vs MCP 客户端层的问题
category: devops
---

# MiniMax MCP Debug Guide

## ⚠️ 包名与功能对应（最重要）

| npm 包 | 功能 | 包含工具 |
|--------|------|----------|
| `minimax-mcp-js` | 图片/音乐/视频生成 | text_to_image, generate_video, text_to_audio, music_generation 等 |
| `minimax-coding-plan-mcp` | 编程增强（图片理解+网络搜索） | **understand_image**, **web_search** |

**症状**：如果配置的是 `minimax-mcp-js` 但期望 `understand_image` 和 `web_search`，工具列表里永远找不到这两个。MCP 服务器进程在跑，但工具不对。

**当前正确配置**（config.yaml mcp_servers.minimax）：
```yaml
mcp_servers:
  minimax:
    command: npx
    args: [-y, minimax-coding-plan-mcp]
    env:
      MINIMAX_API_KEY: ${MINIMAX_CN_API_KEY}
      MINIMAX_API_HOST: https://api.minimaxi.com
      MINIMAX_MCP_BASE_PATH: /tmp
      MINIMAX_API_RESOURCE_MODE: local   # 必须，用于支持本地文件路径
    timeout: 120
```

## 背景

## 核心诊断方法：直接 curl 测试 API

MCP 客户端会吞掉原始 API 错误响应，直接用 curl 调用 API 能快速定位根因。

### API Key 获取
从 hermes agent 的环境配置中读取 `MINIMAX_CN_API_KEY` 和 `MINIMAX_API_HOST`（通常是 `https://api.minimaxi.com`）

### 常用端点测试

**Image Generation** (支持 image-01):
```bash
curl -s --http1.1 "https://api.minimaxi.com/v1/image_generation" \
  -H "Authorization: Bearer $MINIMAX_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"image-01","prompt":"a cat"}' \
  --max-time 30
```

**TTS (Text-to-Speech)**:
```bash
curl -s --http1.1 "https://api.minimaxi.com/v1/t2a_v2" \
  -H "Authorization: Bearer $MINIMAX_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"speech-02-hd","text":"hello","voice_setting":{"voice_id":"male-qn-qingse"}}' \
  --max-time 20
```

**Music Generation**:
```bash
curl -s --http1.1 "https://api.minimaxi.com/v1/music_generation" \
  -H "Authorization: Bearer $MINIMAX_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"music-01","prompt":"happy pop music","lyrics":{"lyrics_text":"la la la"}}' \
  --max-time 20
```

## 图片理解（vision_analyze 失败时的备选方案）

当 `minimax-vl01` 模型报 400 错误时，直接调用 MiniMax 视觉 API 而非通过 MCP：

**API 端点：** `POST https://api.minimaxi.com/v1/coding_plan/vlm`

**请求体：**
```json
{
  "prompt": "请描述图中所有英文文字内容，原文照录",
  "image_url": "data:image/jpeg;base64,<base64编码内容>"
}
```

**认证：** `Authorization: Bearer <MINIMAX_CN_API_KEY>`

支持 JPEG/PNG/WebP，最大 20MB。返回 `result['content']` 为识别文本。

**两个 MCP 包的区别：**

| 包名 | 暴露工具 | 用途 |
|------|------|------|
| `minimax-mcp-js` | text_to_image, generate_video, text_to_audio | 媒体生成 |
| `minimax-coding-plan-mcp` | understand_image, web_search | 图片理解 + 网络搜索 |

Hermes Agent 配置中应使用 `minimax-coding-plan-mcp`，并设置 `MINIMAX_API_RESOURCE_MODE: local` 以支持本地文件路径。

## 常见 status_code 含义

- `0` = 成功
- `1004` = API Key 无效/未携带
- `2013` = 参数错误（通常是字段名不对或格式错误）
- `2061` = Token Plan 不支持该模型

## startsWith 错误的真正来源

当 API 返回错误响应（如 status_code: 2061）时：
1. `MiniMaxAPI.makeRequest()` 会抛出 `MinimaxRequestError`
2. 但 MCP 工具的处理链中，如果错误在某个异步回调里被重新抛出
3. 错误对象可能缺少预期的 `message` 或 `code` 字段
4. 下游代码假设 `error.someField.startsWith(...)` 存在 → `startsWith on undefined`

**解法**：修复方案在 API 端（升级 Token Plan 或修正参数），而不是 MCP 代码端。

## MCP 配置验证

检查 MCP 服务器进程的环境变量和实际配置：
- MCP 进程命令：`ps aux | grep minimax-coding-plan-mcp`
- 环境变量路径：`/proc/<pid>/environ`
- 配置文件位置：hermes agent 的 config.yaml 中的 `mcp_servers.minimax` 段

## API Host 选择

| Host | 用途 |
|------|------|
| `api.minimaxi.com` | 中国区 API（minimax-coding-plan-mcp 默认） |
| `api.minimax.chat` | 国际区 API |

代码中 fallback 为 `api.minimax.chat`，但 env `MINIMAX_API_HOST` 优先。

## ClosedResourceError：Session 失效问题

### 症状
```
MCP call failed: ClosedResourceError:
```
或
```
MCP server 'minimax' is not connected
```

### 根因
Hermes 内存中缓存了 MCP session 句柄。当 MCP 服务器进程被 `pkill` 或手动杀掉后：
1. npx 子进程退出
2. Hermes 的 session 句柄变成 stale（失效）
3. 后续所有 `call_tool` 调用都报 `ClosedResourceError`
4. **Hermes 不会自动检测并重建 session**

### 解法：必须重启 Hermes
```bash
pkill -f hermes && sleep 2 && hermes-agent start
```

### 触发场景
- 切换了 npm 包（从 `minimax-mcp-js` 换到 `minimax-coding-plan-mcp`）后没有重启 Hermes
- 手动 `pkill` 了 MCP 进程
- MCP 进程因任何原因崩溃退出

### Circuit Breaker
Hermes MCP 客户端有熔断机制：连续 3 次失败后，不再重试该工具，返回：
```
MCP server 'minimax' is unreachable after 3 consecutive failures.
Do NOT retry this tool — use alternative approaches or ask the user to check the MCP server.
```
需要重启 Hermes 才能恢复。

## 图片理解：MCP 兜底方案（直接 API）

当 MCP `understand_image` 不可用时，通过 curl 直接调用 MiniMax VLM API：

```bash
curl -X POST "https://api.minimaxi.com/v1/coding_plan/vlm" \
  -H "Authorization: Bearer $MINIMAX_CN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "",
    "image_url": "data:image/jpeg;base64,<base64编码的图片内容>"
  }'
```

- 端点：`https://api.minimaxi.com/v1/coding_plan/vlm`
- 图片：base64 编码，格式 `data:image/jpeg;base64,...`
- 已知成功返回图片内容描述

## 调试命令汇总

```bash
# 检查 MCP 包是否在运行
ps aux | grep minimax

# 查看 Hermes 进程
ps aux | grep hermes

# 重启 Hermes（同时重建 MCP session）
pkill -f hermes && sleep 2 && hermes-agent start
```

## 注意事项

1. **HTTP/2 vs HTTP/1.1**: `curl` 默认尝试 HTTP/2，某些 MiniMax 端点对 HTTP/2 支持不完整。用 `--http1.1` 强制 HTTP/1.1
2. **key 提取**: 从配置文件读取的 API key 值可能有前导空格，需要 trim
3. **npx 缓存**: `minimax-coding-plan-mcp` 由 npx 缓存，路径在 `~/.npm/_npx/<hash>/node_modules/minimax-coding-plan-mcp/`
4. **Session 不自动重建**: MCP session 失效后 Hermes 不会自动重连，必须手动重启 Hermes
