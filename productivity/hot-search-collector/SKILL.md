---
name: hot-search-collector
description: 热点热搜数据采集 - 各平台可用性实测总结
category: productivity
---

# 热点热搜数据采集

## 核心经验

**服务端 curl 能稳定访问的平台极少**。大部分社交媒体平台都需要登录或JS渲染，热点聚合站也大量关门。实际可用的数据源需要实测确认。

---

## 实测可用数据源

### ✅ 稳定可用（API或静态页面）

| 平台 | 类型 | 命令/地址 | 备注 |
|------|------|---------|------|
| **B站** | API | `https://api.bilibili.com/x/web-interface/ranking?rid=0&day=3&type=all` | 返回 JSON，可直接解析 |
| **百度实时热搜** | 网页抓取 | `https://top.baidu.com/board?tab=realtime` | 正则：`class="c-single-text-ellipsis">([^<]+)</div>` |
| **凤凰网** | 网页抓取 | `https://news.ifeng.com/` | 正则：`<a[^>]+href=[^>]+>([^<]{5,30})</a>` |
| **国家统计局** | 静态页面 | `https://www.stats.gov.cn/sj/zxfb/` | 正则：`title='([^']+)'`，筛选含数字的标题 |
| **教育部** | 静态页面 | `http://www.moe.gov.cn/` | 正则：`title="([^"]{8,40})"` |
| **新华网(国际)** | 静态页面 | `http://www.xinhuanet.com/world/` | 同凤凰网正则 |
| **凤凰网财经** | 静态页面 | `https://finance.ifeng.com/` | 同凤凰网正则 |

### ❌ 已验证不可用

| 平台 | 原因 | 尝试过的地址 |
|------|------|------------|
| 微博 | API 403 Forbidden / 需要登录 | `weibo.com/ajax/side/hotSearch` |
| 知乎 | 需要登录 401 | `zhihu.com/api/v3/feed/topstory/hot-lists/total` |
| 抖音 | JS渲染，数据为空 | `douyin.com/aweme/v1/web/general/search/single/` |
| 快手 | JS渲染+反爬 | `kuaishou.com/short-video/feed` |
| 小红书 | JS渲染，页面需登录 | `xiaohongshu.com/explore` |
| 36kr | JS渲染 | `36kr.com/` |
| 虎嗅 | JS渲染 | `huxiu.com/` |
| 网易新闻 | 403 Forbidden | `news.163.com/special/rank_guonei.js` |
| 百度热搜(API) | 404 Not Found | `top.baidu.com/api?sa=hotapi_apps` |

### ❌ 热点聚合站（大量关门或JS渲染）

以下聚合站均无法获取数据：AnyKnew、36duiedu、派观点、牛媒指数、热点搜藏家、热榜116、今日热榜(tophub.today)、热搜神器、今日热闻 等。

---

## 推荐采集方案

### 社媒热搜（服务器端curl）
```
B站热搜:    curl -s "https://api.bilibili.com/x/web-interface/ranking?rid=0&day=3&type=all"
百度实时:   curl -s "https://top.baidu.com/board?tab=realtime"
凤凰网:     curl -s "https://news.ifeng.com/"
```

### 百度实时热搜正则
```python
import re
html = curl("https://top.baidu.com/board?tab=realtime")
items = re.findall(r'class="c-single-text-ellipsis">([^<]+)</div>', html)
items = [x.strip() for x in items if len(x.strip())>3][:10]
```

### 凤凰网正则
```python
titles = re.findall(r'<a[^>]+href=[^>]+>([^<]{5,30})</a>', html)
seen = set()
for t in titles:
    t = t.strip()
    if t and t not in seen and len(t)>5:
        seen.add(t); print(t)
```

### 统计局正则
```python
titles = re.findall(r"title='([^']+)'", html)
for t in titles:
    if len(t) > 10 and any(c.isdigit() for c in t):
        print(t)
```

---

## 替代思路

如果需要更多平台热搜，可考虑：
1. **browser 工具**：用 Selenium/Playwright 方案，让浏览器渲染后再抓（速度慢，但可抓JS内容）
2. **RSS 订阅**：部分平台支持RSS，如 `zhihurss.miantiao.me/`（已失效）
3. **接受现实**：大部分平台无法服务端抓取，改用新闻门户（凤凰网、新华网）的分类内容代替社交媒体
