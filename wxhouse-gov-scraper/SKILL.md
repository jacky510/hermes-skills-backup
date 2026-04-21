---
name: wxhouse-gov-scraper
description: 抓取无锡市住建局每周商品房备案成交数据，分析新房/二手房/区域/价格/成交量趋势
triggers:
  - 每周无锡商品房数据
  - 无锡房管局数据
  - 无锡新房备案
  - js.wuxi.gov.cn 房产数据
---

# 无锡市住建局房产数据抓取

每周自动抓取无锡市住建局 (js.wuxi.gov.cn) 发布的商品房一周备案成交数据，分析新房、二手房、区域、价格、成交量趋势。

## 数据源

**列表页（主要数据来源）:** `https://js.wuxi.gov.cn/zfxxgk/xxgkml/fdcsc/index.shtml`
- 每周三/周四发布上周数据（如4.06~4.12的数据在4月14日发布）
- **备案面积数字直接嵌在文章标题里**，如"4.06～4.12无锡商品房一周备案成交1.77万平方米"
- 用正则 `(\d+\.\d+|\d+)万平方米` 直接提取，无需访问详情页

**详情页（补充数据）:** `https://js.wuxi.gov.cn/doc/{YYYY}/{MM}/{DD}/{ID}.shtml`
- 包含配套图表 PNG，图表 URL: `https://js.wuxi.gov.cn/uploadfiles/{YYYYMM}/{DD}/{ID}.png`
- 图表内容包括：备案面积走势、成交均价走势、面积段占比（90-120㎡等）、区域成交量分布
- **图表 OCR 识别率仅 60-70%，是补充数据，主要数据从列表页提取即可**

## 抓取流程

### Step 1: 获取最新报告列表（主要数据）

```bash
curl -s "https://js.wuxi.gov.cn/zfxxgk/xxgkml/fdcsc/index.shtml" | python3 -c "
import sys, re
html = sys.stdin.read()
entries = re.findall(r'<a[^>]+href=[\"\'](/doc/[^\"\']+)[\"\']\s*[^>]*>\s*([^<]*?(?:\d+\.\d+[～~]\d+\.\d+)[^<]*)\s*</a>', html)
for url, title in entries:
    if '无锡商品房一周备案成交' in title:
        m2 = re.search(r'(\d+\.\d+|\d+)万平方米', title)
        area = m2.group(1) if m2 else ''
        print(f'{title.strip()} | {area}万㎡ | {url}')
"
```

输出: `4.06～4.12无锡商品房一周备案成交1.77万平方米 | 1.77万㎡ | /doc/2026/04/14/4759516.shtml`

### Step 2: 详情页图表（可选，补充区域/价格细分数据）

1. 下载图表: `curl -s -o /tmp/chart.png "{图表URL}"`
2. 图像增强 (PIL): 对比度×2.5，锐度×1.5，灰度转换，保存为 enhanced.png
3. OCR: `tesseract enhanced.png stdout -l chi_sim+eng --psm 6`
4. 人工核对关键数字（OCR 误差较大，不可全信）

**图表内容:**
- 备案面积走势折线图 (万㎡)
- 成交价格走势图 (元/㎡)
- 面积段占比柱/饼图 (90-120㎡等)
- 区域成交量柱状图

## 历史数据积累

每周数据保存为 JSON:
```json
{
  "report_date": "2026-04-06 ~ 2026-04-12",
  "new_home": {"备案面积_万㎡": 1.77, "较上周变化": -0.61},
  "weekly_history": [
    {"date": "12.15~12.21", "area": 5.89},
    ...
  ]
}
```

保存路径: `~/.hermes/wx_housing/weekly_{date}.json`

## 分析维度

1. **新房备案面积趋势**: 每周环比、同比（春节前后数据异常需标注）
2. **价格走势**: 均价区间变化
3. **面积段占比**: 90-120㎡刚需 vs 144㎡+改善结构变化
4. **区域成交分布**: 经开/滨湖/梁溪等区占比（从图表OCR提取）
5. **较上周/较上月变化**: 具体数字和百分比

## 关键经验

- **列表页标题直接含面积数据**，正则 `(\d+\.\d+|\d+)万平方米` 提取即可，是主要数据源
- **图表 OCR 识别率仅 60-70%**，字体扭曲，不可靠；仅作区域分布/面积段占比的辅助参考
- 图表 URL 从详情页 HTML 的 `<img>` 标签提取，路径规律为 `/uploadfiles/{YYYYMM}/{DD}/{ID}.png`
- Tesseract: `apt install tesseract-ocr`；图像增强: `pip install Pillow`
- 发布规律：每周三/周四发上周数据（如4.06~4.12数据在4月14日发布）

## 定时任务

每周四上午9点执行（如遇节假日顺延）：
- 抓取最新一期周报
- 更新历史数据库
- 输出趋势分析摘要
- 若发现数据异常（环比变化>30%），触发告警
