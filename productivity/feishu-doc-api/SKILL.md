---
name: feishu-doc-api
description: 通过飞书开放平台 API 创建文档、写入内容、管理文件夹
triggers:
  - 飞书文档 API
  - 创建飞书文档
  - feishu docx API
  - 写入飞书文档
---

# 飞书文档 API 完整指南

## 环境凭证
已在环境变量中配置：
- `FEISHU_APP_ID` = `cli_a954a72b9a389cbd`
- `FEISHU_APP_SECRET` = 已配置（见下方读取方式）
- Token 获取地址：`https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal`

**⚠️ 重要：在 execute_code/cron 环境中读取凭证的正确方式**

`os.environ.get('FEISHU_APP_SECRET')` 在 execute_code 沙盒中会返回空值！正确方式是**直接从文件读取**：

```python
# ✅ 正确：从 ~/.hermes/.env 文件读取（cron/execute_code 通用）
with open('/home/lighthouse/.hermes/.env', 'r') as f:
    for line in f:
        if line.startswith('FEISHU_APP_SECRET='):
            feishu_secret = line.split('=', 1)[1].strip()
        elif line.startswith('FEISHU_APP_ID='):
            feishu_id = line.split('=', 1)[1].strip()

# ❌ 错误：os.environ.get('FEISHU_APP_SECRET') 在沙盒中返回空字符串
```

**注意**：cron 任务中如果用 terminal() 工具调用 bash 环境变量则无此问题，`$FEISHU_APP_SECRET` 在 shell 中是正常的。

## 核心 API 端点

### 1. 获取 tenant_access_token
```bash
curl -s -X POST "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
  -H "Content-Type: application/json" \
  -d '{"app_id":"'"$FEISHU_APP_ID"'","app_secret":"'"$FEISHU_APP_SECRET"'"}'
```
返回：`{"code":0,"tenant_access_token":"t-xxx","msg":"ok"}`

### 2. 在指定文件夹创建文档
```bash
curl -s -X POST "https://open.feishu.cn/open-apis/docx/v1/documents" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "文档标题",
    "parent_token": "文件夹folder_token"
  }'
```
返回：`{"code":0,"data":{"document":{"document_id":"xxx","title":"..."}}}`

**文件夹 URL 格式**：`https://jackyyun.feishu.cn/drive/folder/QC0qfKeeLl03q7dCvSOcfhBanZm`
- 文件夹 token = `QC0qfKeeLl03q7dCvSOcfhBanZm`

**文档链接格式**：`https://jackyyun.feishu.cn/docx/{document_id}`

### 3. 写入内容块
```bash
curl -s -X POST "https://open.feishu.cn/open-apis/docx/v1/documents/{DOC_ID}/blocks/{DOC_ID}/children" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "children": [
      {
        "block_type": 2,
        "text": {
          "elements": [{"text_run": {"content": "文本内容", "text_element_style": {"bold": true}}}],
          "style": {}
        }
      }
    ],
    "index": -1
  }'
```

**block_type 类型**（经验证）：
- `2` = 普通文本段落（✅ 唯一在此环境可用的块类型）
- `4` = 标题1（H1）（❌ 返回 1770001 invalid param）
- `5` = 标题2（H2）（❌ 返回 1770001 invalid param）
- `6` = 标题3（H3）（❌ 返回 1770001 invalid param）

**替代方案**：用 `block_type: 2` 配合 `text_element_style.bold: true` 实现加粗标题效果。

**text_element_style**：
- `bold`: true/false — 加粗
- `italic`: true/false — 斜体
- `inline_code`: true/false — 行内代码
- `strikethrough`: true/false — 删除线
- `underline`: true/false — 下划线

### 4. 获取文档元信息
```bash
curl -s "https://open.feishu.cn/open-apis/docx/v1/documents/{DOC_ID}" \
  -H "Authorization: Bearer {TOKEN}"
```

## 重要限制

1. **Token 有效期**：tenant_access_token 有效期约 2 小时，需定期刷新
2. **文件夹 token**：必须对应用有分享权限才能创建文档到其中
3. **API 限流**：注意批量操作时的限流问题
4. **不可直接创建 HTML**：飞书文档是块结构，需逐块写入，不支持直接渲染 HTML

## 定时任务中的使用方式

cron 任务中调用飞书文档 API 的标准流程：
1. 获取 token（或在任务开始时刷新）
2. 在用户指定文件夹创建文档（使用 parent_token）
3. 逐批写入内容块（每批不超过 20 块）
4. 获取文档 URL
5. send_message 发送链接（只发链接，不发完整内容）

## cron 任务标准代码模板

```python
import subprocess, json
from datetime import datetime

# 1. 读取凭证（execute_code 沙盒必须用此方式）
with open('/home/lighthouse/.hermes/.env', 'r') as f:
    for line in f:
        if line.startswith('FEISHU_APP_SECRET='):
            feishu_secret = line.split('=', 1)[1].strip()
        elif line.startswith('FEISHU_APP_ID='):
            feishu_id = line.split('=', 1)[1].strip()

# 2. 获取 token
r = subprocess.run(
    ['curl', '-s', '-X', 'POST', 
     'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal',
     '-H', 'Content-Type: application/json',
     '-d', json.dumps({"app_id": feishu_id, "app_secret": feishu_secret})],
    capture_output=True, text=True, timeout=15
)
token = json.loads(r.stdout)['tenant_access_token']

# 3. 创建文档
r = subprocess.run(
    ['curl', '-s', '-X', 'POST', 
     'https://open.feishu.cn/open-apis/docx/v1/documents',
     '-H', f'Authorization: Bearer {token}',
     '-H', 'Content-Type: application/json',
     '-d', json.dumps({"title": "标题", "parent_token": "QC0qfKeeLl03q7dCvSOcfhBanZm"})],
    capture_output=True, text=True, timeout=15
)
doc_id = json.loads(r.stdout)['data']['document']['document_id']

# 4. 写入内容块（block_type:2 普通段落，bold 实现标题）
def add_block(token, doc_id, text, bold=False):
    payload = {
        "children": [{"block_type": 2, "text": {
            "elements": [{"text_run": {"content": text, "text_element_style": {"bold": bold}}}],
            "style": {}
        }}],
        "index": -1
    }
    r = subprocess.run(
        ['curl', '-s', '-X', 'POST', 
         f'https://open.feishu.cn/open-apis/docx/v1/documents/{doc_id}/blocks/{doc_id}/children',
         '-H', f'Authorization: Bearer {token}',
         '-H', 'Content-Type: application/json',
         '-d', json.dumps(payload, ensure_ascii=False)],
        capture_output=True, text=True, timeout=15
    )
    return json.loads(r.stdout)

# 示例
add_block(token, doc_id, "标题", bold=True)
add_block(token, doc_id, "正文内容", bold=False)
# 注意：写入间隔 >0.25秒/条，避免 429 限流
```

## 常见错误
- `230001` — ext=invalid receive_id：发送消息时 target 参数错误
- `99991663` — API 权限不足：检查应用是否已获得对应权限
- Token 失效：重新获取 tenant_access_token
- `10014 app secret invalid`：凭证读取方式错误，使用上面的文件读取方式
