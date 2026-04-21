---
name: wuxi-weekly-cron
description: 无锡楼市周报定时任务运行笔记 - 实测经验汇总
category: devops
---

# 无锡楼市周报 Cron 任务实测笔记

## 任务信息
- 任务名：无锡楼市周报
- Cron ID: 4b81cb2965ac
- 调度：每周一 09:30（北京时间）
- 超时：300秒
- Skills: wxhouse-gov-scraper, storage-server-workflow

## 关键实测经验

### 1. 路径问题
- **正确路径**：`~/.hermes/wx_reports/wuxi_weekly_data.json`
- 错误路径：`/workspace/reports`（无权限，不存在）

### 2. 网络环境问题
- 当前执行环境（腾讯轻量云）无法直接访问 `open.feishu.cn`，send_message 会报错 230001
- **但 cron 自动投递（auto-deliver）可以成功发送飞书**，因为走不同通道
- 手动触发 action=run 返回成功，但 last_run_at 始终为 null，实际执行为异步，不要反复查询状态

### 3. 备站
- 主站慢时用内网备站：`http://218.90.169.58/newslist?con.clsIcon=7bfc38d217981305aab84c70f11b152c`
- 外网不可达的服务器直接可访问

### 4. Cron 任务修复记录（2026-04-20）
- 初次创建时 cron 表达式 `0 30 9 * * 1` 报错，改为 `30 9 * * 1`（省略0秒）成功
- 超时从 120s 改为 300s

### 5. 飞书文档集成（2026-04-20 更新）
- **不再使用1Panel存储服务器**作为用户可见链接
- 改用飞书文档 API：创建文档 → 写入内容 → 发链接给用户
- 目标文件夹：`https://jackyyun.feishu.cn/drive/folder/QC0qfKeeLl03q7dCvSOcfhBanZm`
- 文件夹 token：`QC0qfKeeLl03q7dCvSOcfhBanZm`
- 文档创建 API：POST https://open.feishu.cn/open-apis/docx/v1/documents
- 详见 skill: feishu-doc-api

### 6. Cron 执行机制说明
- action=run 只是发出触发信号，实际执行为异步后台进程
- 不要反复查询 last_run_at 状态，以 cron 实际投递结果为准
- 定时触发（每天08:30/每周一09:30）比手动 run 更可靠
