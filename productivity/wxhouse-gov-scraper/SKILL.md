---
name: wxhouse-gov-scraper
description: 抓取无锡市房地产信息公众发布平台（pub.wxhouse.com.cn）的官方房产数据，发现政府备案平台比商业平台（贝壳/链家）更容易抓取，数据更权威。
version: 1.0.0
author: Hermes Agent
license: MIT
tags: [房产, 无锡, 政府数据, web-scraping, curl]
---

# 无锡房产政府备案平台抓取

## 背景发现

国内商业房产平台（贝壳/链家/安居客）99%是JS渲染，curl直接抓取返回空壳。但**政府备案平台**通常是老式PHP/ASP直接输出HTML，反而可以直接抓取，且数据更权威。

无锡平台：`http://pub.wxhouse.com.cn`（无锡市房地产市场管理和监测中心官方数据）

---

## 核心URL结构

```
# 项目列表（商品房）
http://pub.wxhouse.com.cn/HTBA/SaleCert/pagelist

# 单个项目概况
http://pub.wxhouse.com.cn/HTBA/SaleCert/detail?idx={项目idx}

# 房屋明细（一房一价）
http://pub.wxhouse.com.cn/HTBA/SaleCert/frame_salecert_houselist?idx={项目idx}

# 单套房屋详情
http://pub.wxhouse.com.cn/HTBA/House/detail?idx={单套idx}

# 售楼说明书（PDF，可下载）
http://pub.wxhouse.com.cn/HTBA/SaleCert/frame_salecert_manual?idx={项目idx}
http://pub.wxhouse.com.cn/HTBA/SaleCert/downloadmanual?idx={项目idx}
```

---

## 房屋详情页独家字段（政府实测数据）

| 字段 | 说明 | 用途 |
|------|------|------|
| `公示单价` | 政府备案价，不会虚标 | 判断真实折扣力度 |
| `建筑面积` | 房本登记面积 | — |
| `套内面积` | 实测使用面积 | 计算实际得房率 |
| `分摊面积` | 公摊部分 | 核实公摊是否合理 |
| `面积状态` | 预测/实测 | 现房vs期房 |
| `房屋状态` | 待售/已售/抵押/查封/保留 | 识别抵押房风险 |

---

## 识别开发商套路

| 套路 | 在这个平台上怎么识别 |
|------|---------------------|
| 价外加价 | 公示单价 vs 实际报价对比 |
| 抵押房当卖 | 状态=抵押（开发商未解押就卖） |
| 捂盘惜售 | 一次只拿一栋销证，后期待涨 |
| 公摊虚报 | 套内÷建筑=得房率，自行验算 |

---

## curl 命令模板

```bash
# 伪装浏览器，抓取项目概况
curl -s --max-time 20 \
  -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
  "http://pub.wxhouse.com.cn/HTBA/SaleCert/frame_salecert_summary?idx={idx}"

# 抓取房屋明细（分页）
curl -s --max-time 20 \
  -A "Mozilla/5.0" \
  "http://pub.wxhouse.com.cn/HTBA/SaleCert/frame_salecert_houselist?idx={idx}"

# 抓取单套房屋详情（含公示单价）
curl -s --max-time 20 \
  -A "Mozilla/5.0" \
  "http://pub.wxhouse.com.cn/HTBA/House/detail?idx={单套idx}"
```

---

## 其他政府房产平台（可参考此方法）

思路：搜索 `城市名 + 房地产信息公众发布` 或 `城市名 + 房管局 + 商品房备案`

| 城市 | 平台 |
|------|------|
| 无锡 | pub.wxhouse.com.cn |
| 苏州 | 类似结构 |
| 南京 | 类似结构 |

通常路径是 `/HTBA/SaleCert/` 或类似命名规则。

---

## 局限

- 只覆盖单个城市（无锡）
- 部分页面可能需要登录
- 数据更新可能有延迟（通常1-7天）
- 其他城市需要单独搜索URL结构
