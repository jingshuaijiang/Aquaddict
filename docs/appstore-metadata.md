# App Store 提审材料(草稿,提交前对照填入 App Store Connect)

## 基本信息

| 项 | 值 |
|---|---|
| 名称 | Aquaddict(备选名待定,若被占用) |
| 副标题 zh | Shearwater 潜水日志与技潜工具箱 |
| Subtitle en | Dive log & tech toolkit for Shearwater |
| Bundle ID | com.jjsbanana.divetrace |
| 类别 | 主:运动(Sports) 次:健康健美(Health & Fitness) |
| 价格 | 免费 |
| 年龄分级 | 4+ |
| 隐私政策 URL | https://jingshuaijiang.github.io/Aquaddict/privacy.html(需在 repo Settings → Pages 启用,branch master / docs 目录) |
| 技术支持 URL | https://github.com/jingshuaijiang/Aquaddict |
| App 隐私问卷 | 「不收集数据」(Data Not Collected)—— 全部本地存储,无第三方 SDK |

## 描述(中文)

直连你的 Shearwater 潜水电脑,蓝牙一键下载全部潜水日志——不需要
Shearwater Cloud,不需要账号,数据只属于你的手机。

为认真对待数据的潜水员打造:

- 完整曲线:深度、水温、NDL、ppO₂、SAC 多曲线叠加,横屏细看每一秒
- 技潜精度:GF、气体密度、END、CNS、平均深度线、上升速度违规标记
- 训练分析:平稳度、上升控制、停留质量、SAC 趋势,朝 GUE 标准看齐
- ZHL-16C 组织舱回放、完整减压计划器、Nitrox 充气计算器
- 潜点(GPS 自动落点)、潜伴、照片、物种、装备与干衣保养记录
- 配重换算(单瓶⇄双瓶、淡水⇄海水)、配平模拟器、卡路里估算
- 年度回顾、个人纪录、全球潜旅灵感(按月份/大物筛选)
- 中英双语,公制/英制一键切换,深海暗色主题

所有数据保存在本地,无广告,无跟踪。

## Description (English)

Talks straight to your Shearwater dive computer: download every log
over Bluetooth — no Shearwater Cloud, no account, your data stays on
your phone.

Built for divers who take their data seriously:

- Full profiles: depth, temp, NDL, ppO₂ and SAC overlays, landscape scrubbing
- Tech precision: GF, gas density, END, CNS, average-depth line, ascent-rate flags
- Training analytics: stability, ascent control, stop quality, SAC trends
- ZHL-16C tissue replay, full deco planner, nitrox blending calculator
- Sites (auto GPS pins), buddies, photos, species, gear & drysuit service log
- Weighting transfer (singles⇄doubles, fresh⇄salt), trim simulator, calorie estimate
- Year in review, personal records, worldwide destination inspiration
- Bilingual (中文/English), metric/imperial toggle, dark deep-ocean theme

Everything stays on-device. No ads, no tracking.

## 关键词(≤100 字符)

`scuba,dive log,shearwater,perdix,deco,nitrox,GUE,潜水,日志,技潜,减压,tech diving`

## 审核备注(Review Notes)

This app downloads dive logs from Shearwater dive computers over
Bluetooth LE. Reviewers will not have this hardware — the app ships
with sample dives that load automatically on first launch, so every
feature (charts, analytics, planner, sites, records) is fully
browsable without any device. The Bluetooth download flow can be
opened from the home screen; without a dive computer nearby it simply
scans and finds nothing. No account or login exists.

## 截图清单(6.9",模拟器出图,提交前生成)

1. 主页最近潜水多曲线图(深度+温度+SAC)
2. 潜水详情(GUE 精度区块)
3. 横屏全屏曲线
4. 地图潜点
5. 减压计划器
6. 年度回顾

## 提审前检查

- [ ] 用户已加入 Apple Developer Program
- [ ] GitHub Pages 已启用(privacy.html 可访问)
- [ ] 决定:公开版内置示例潜水(脱敏)还是真实日志
- [ ] App Store Connect 建 app、名字确认可用
- [ ] Archive 上传、TestFlight 自测一轮
