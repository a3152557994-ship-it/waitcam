# WaitCam 商业实战 5 问自检与 ASO / 上架备忘包

> 依据 `commercial-playbook` 实抓美/中区 App Store 同行样本（`2AM CAM`、`OldRoll`、`Dazz Cam`、`Dispo`、`Lapse`、`Poka Cam`、`FOMO相机`）整理，非拍脑袋结论。

## 一、开工前 5 问实盘核对卡

1. **怎么找到我们（ASO 流量入口）**：
   - 美区标题 `WaitCam: 12h Film Camera`（24/30 字符）+ 副标题 `2AM Disposable Film Darkroom`（28/30 字符）+ 关键词 `film camera,disposable camera,2am cam,vintage camera,retro flash,darkroom,live activity,party cam`（97/100 字符），精准覆盖美区付费榜飙升词 `film camera`、`disposable camera`、`2am cam`。
   - 中区标题 `WaitCam - 12小时延迟显影胶片相机`（22/30 字符）+ 副标题 `2AM派对闪光灯相机 · 灵动岛暗房倒计时`（22/30 字符）+ 关键词 `胶片相机,延迟显影,闪光灯相机,一次性相机,复古相机,CCD相机,2am cam,film camera,灵动岛,暗房,买断无订阅,派对相机`（78/100 字符）。
2. **为什么选我们不选免费巨头与头部同行**：
   - **过巨头免费替代红线**：系统原生相机与豆包/即梦无法做到「拍完强制锁入沙盒 12 小时不可偷看 + 灵动岛倒计时 + 次日统一仪式感批量冲印」。
   - **打掉竞品实盘差评**：
     - 破 `Dazz Cam`（118k 评价痛点 `Everything costs money` + $4.99/周）：免费无水印基础卷 + 彻底零订阅；
     - 破 `2AM CAM`（$0.99 预付费门槛 + `bottom left gallery doesn't show any pictures` 1★ 差评）：免费下载降门槛 + 左下角暗房保险箱跳动精确倒计时与张数反馈；
     - 破 `Dispo` / `OldRoll`（`MY PHOTOS DISAPPEARED` 掉电丢片 1-2★ 差评）：写入 `Application Support` + `atomic` AES-256 原子落盘；
     - 破 `极影相机` / `FOMO相机`（连拍闪退 / 换机恢复购买转圈 1★ 差评）：单 `CIContext` 限宽 3024px + `autoreleasepool` + StoreKit 2 `AppStore.sync()` 显式结果反馈。
3. **怎么让用户冲动付钱**：
   - 免费 `2AM 派对闪光卷` 无水印拉满派对现场信任，拍完第 1 卷后在派对中段想**封卷开第 2 卷**、切 **6h/24h 自定义显影**、或选 **800T 霓虹红橙光晕卷** / **35mm 接触印相单** 时，精准弹出零订阅一次性买断卡片（¥6 / $0.99 与 ¥12 / $1.99）。
4. **售前与售后怎么省心不踩坑**：
   - 100% 本地 CoreImage + CryptoKit + StoreKit 2，零人工售前、零服务器成本；StoreKit 2 买断支持家人共享与一键「恢复购买」，隐私政策与 FAQ 支持页已在 `docs/` 就绪。
5. **价格从哪抄的**：
   - 对标美区付费榜 Top 23 `2AM CAM ($0.99)` 与用户许愿高转化买断带，采用「免费引流（消除 $0.99 预付费冷启动阻力）+ $0.99 / ¥6 暗房扩容 + $1.99 / ¥12 全能买断」双阶梯，吃满苹果 15% 小微抽成。
