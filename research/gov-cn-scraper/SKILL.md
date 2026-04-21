---
name: gov-cn-scraper
description: 抓取中国政府和公共机构网站（统计局、发改委、住建局等）的文章列表和数据
triggers:
  - stats.gov.cn 统计局
  - 国家统计局
  - 政府网站抓取
  - js.wuxi.gov.cn 无锡住建局
---

# 中国政府网站数据抓取

## 核心经验

**大多数政府网站是静态 HTML，不需要 JS 渲染**，直接 curl 即可抓取。
**不要被"JS 渲染"吓到**——先用 curl 测试，能抓到 HTML 就说明可以抓。

## stats.gov.cn 国家统计局

### 列表页
URL: https://www.stats.gov.cn/sj/zxfb/

### 正确抓取方法

先用 curl 抓取并保存：
```bash
curl -s "https://www.stats.gov.cn/sj/zxfb/" -o /tmp/stats.html
```

然后用 Python 提取文章标题：
```python
import re
with open('/tmp/stats.html') as f:
    html = f.read()
titles = re.findall(r"title='([^']+)'", html)
seen = set()
for t in titles:
    if len(t) > 10 and t not in seen and any(c.isdigit() for c in t):
        seen.add(t)
        print(t)
```

**注意**：不能用 href 匹配的老思路，统计局页面的结构是 title='文章标题' 形式。

### 验证方法
```bash
# 确认有内容
wc -c /tmp/stats.html
# 找文章列表区域（包含2026的行）
grep -n '2026' /tmp/stats.html | head
```

## js.wuxi.gov.cn 无锡住建局

详见 wxhouse-gov-scraper skill。

## 通用政府网站抓取流程

1. curl 测试：curl -s URL -o /tmp/test.html && wc -c
2. 检查 HTML 结构：静态内容还是 JS 渲染
3. 找文章列表模式：搜索日期格式 2026- 或数字
4. 确定正则：从实际 HTML 中提取 title/href
5. 过滤噪音：用长度、数字、关键词等过滤

## 常见问题

- curl 返回空白：可能是 JS 动态加载，尝试加 User-Agent
- 正则匹配为空：先 grep 定位实际 HTML 结构
- 反爬：加 -H "User-Agent: Mozilla/5.0" 或 -H "Referer: ..."
