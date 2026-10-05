# Motion Trace 工作紀錄(給後續接手的人 / agent)

最後更新:2026-10-05(git 狀態截至 `137d3c7`)。專案:`/Users/yujuchen/www/motion-trace`(repo:`github.com/qscgy5713/motion-trace`,分支 `master`)。

## 1. 專案是什麼

仿 `dartspropower.com/tool/motion-trace-app/` 的工具:上傳投擲影片 → 偵測人體骨架 → 畫出手腕/手肘/肩膀/食指的移動軌跡 → 慢動作播放、匯出疊圖影片 → 用 Gemini 給「白話教練式」修改建議。

- **整個專案只有一個 `index.html`**(HTML + CSS + `<script type="module">`),沒有 build、沒有後端、沒有 package.json。
- 全部在瀏覽器本機處理,影片不上傳。唯一對外呼叫:MediaPipe 模型/WASM(CDN)、Gemini API(使用者自填 key)。
- 啟動:`cd motion-trace && python3 -m http.server 8000`,開 `http://localhost:8000`。不要用 `file://`(模組載入/相機等會有問題)。

## 2. 使用者偏好與工作規則(重要)

- **一律用繁體中文回覆**。
- **未經使用者明確同意,不要 `git commit` / `git push`**。同意動工 ≠ 同意推送,每次都要另外問。
- 寫完程式後主動做一次 code review(使用者會打 `cr` 觸發 code-review skill),抓到的問題直接修再回報。
- 使用者是一般玩家,**要的是「能照著調整」的建議,不要專業術語**(見 §6)。
- 不要主動讀 `node_modules`、lock 檔、log 等(見使用者全域 CLAUDE.md)。

## 3. 檔案與目前 git 狀態

| 檔案 | 說明 |
|---|---|
| `index.html` | 全部程式碼 |
| `README.md` | 使用說明 |
| `doc/worklog.md` | 本檔 |

- 目前所有改動都已 commit 並推到 `origin/master`;最後一次 commit:`137d3c7`。
- commit 歷史:
  - `073324b`:第一版(姿勢+手部追蹤、軌跡、慢動作、匯出、Gemini)
  - `52d8694`:骨長過濾、軌跡長度選項、120fps/幀率偵測、模型選項、品質提醒、背景分頁不卡住
  - `137d3c7`:逐幀骨長檢查、軌跡不整條消失、追蹤過濾(嚴格/寬鬆/關閉)、Gemini LaTeX 轉換與白話教練提示詞、README、本檔
- 之後若再有修改,請先問使用者再 commit / push(見 §2)。

## 4. 程式架構(`index.html`)

資料流:

```
選影片 → estimateFps(實際幀率) → 按「開始分析」
  → 逐幀 seek + MediaPipe PoseLandmarker(+HandLandmarker) → samples[]
  → buildTrails(): 骨長閘門 → Hampel 離群 → 補小缺口 → One Euro 平滑(前後各一次取平均) → dropShortRuns
  → buildMetrics(): 手肘角度/手腕速度/出手時間等量化數據 + diagnose() 品質警告
  → draw(): canvas 疊畫骨架、軌跡、網格、參考線
  → 匯出疊圖影片(MediaRecorder 錄 canvas)
  → Gemini: 關鍵幀 JPEG + 量化數據 + 白話教練提示詞 → delatex() → md() 顯示
```

重要的函式/常數(用 `grep -n` 找位置):

- `ensureModels()`:載入 pose(`heavy`/`full`,預設 heavy ≈30MB)與 hand 模型,GPU 失敗退回 CPU。
- `estimateFps()`:用 `requestVideoFrameCallback` 播放約 40 幀,取幀間隔中位數。
- 分析迴圈在 `$("analyze")` 的 click handler:`seekTo(t)` → `nextFrame()` → `detectForVideo`。
- `bodyUnit()`:尺度 = 軀幹長的一半(正面時約等於肩寬)。
- `boneMask(mode)`:骨長閘門;`mode` = `strict`/`loose`(`off` 時不呼叫)。
- `removeOutliers`(Hampel)、`fillGaps`、`euroSmooth`、`dropShortRuns`、`buildTrails`、`buildMetrics`、`diagnose`/`renderWarn`。
- `VIS_MIN = 0.05`:關節可見度下限。
- `delatex()` + `md()`:Gemini 回覆的轉換/排版。
- Gemini 呼叫:`POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`,key 放 header `x-goog-api-key`。API key 只存在 input 欄位(記憶體),**不寫入任何儲存空間**,這是使用者的明確要求。模型下拉預設 `gemini-3.7-flash` 等,按「載入可用模型」會向 Google 查帳號可用清單。

## 5. 設計決策與原因(改之前請先看)

1. **追蹤不用 Gemini**。Gemini 看影片是語意理解,沒有逐幀精確座標。追蹤用 MediaPipe(免費、可在手機瀏覽器跑),Gemini 只負責文字建議。
2. **尺度用軀幹長,不用肩寬**。側面拍攝時兩肩重疊,肩寬只剩正面的 1/4(實測 33px vs 軀幹 284px),所有門檻和速度會失真 ~4 倍。
3. **容器標示的 fps 不可信**。使用者的影片 `r_frame_rate=120`,實際平均 ~30fps(VFR)。所以要實測;取樣頻率不會超過實際幀率(超過只是重複分析同一幀)。
4. **骨長閘門**(`boneMask`):整支影片的軀幹/上臂/前臂 2D 長度應大致固定,偏離中位數太多(軀幹 0.7~1.3×、上臂 0.45~1.5×、前臂 0.4~1.5×)代表關節被誤判到背景/頭髮,該幀不採用。
   - 「標準骨長」只從可信度 > 0.1 的幀取中位數;「逐幀檢查」對可信度 > `VIS_MIN` 的幀都做。**曾經兩者都用 0.1,結果投擲出手時(手肘可信度 0.00~0.1)整段被丟掉**,已修正。
   - 下限放寬是因為手臂朝/離鏡頭時 2D 投影會自然縮短。
   - 某段骨長完全沒有可信資料(例如髖部出鏡的半身影片)時不拿它過濾(`has()`),否則整條會被清空。
5. **沒追蹤到就不畫線,也不內插**(使用者明確要求)。只補 ≤ 約 0.1 秒的小缺口;短於約 0.1 秒的零碎片段視為雜訊丟掉。軌跡在當前幀沒追蹤到時**只省略圓點,過去已追蹤的線段照畫**(曾經整條消失造成閃爍,已改)。
6. **軌跡預設只畫「最近 1 秒」並漸淡**。長影片含多次投擲,全部疊在一起就是一團。「從頭累積到目前」會隨播放逐漸長出(曾誤做成一次畫整支影片,已修)。
7. **背景分頁不會卡住**:`nextFrame()` 在 `document.hidden` 時略過 rAF 等待,`seekTo()` 有 3 秒保險。播放與匯出仍依賴 rAF,匯出時分頁需在前景。
8. **骨架只畫軀幹 + 投擲手的上臂/前臂**,不畫另一隻手和腿(減少雜亂)。骨架畫的是原始偵測,**沒有平滑**。
9. **預設用高精度(heavy)模型**:同一支影片偵測成功率 77% → 98%,骨架明顯更貼合。

## 6. Gemini 建議的提示詞(使用者反覆調整的結果)

使用者需求:像球場邊的教練、白話、可照著調整。目前規則:

- 篇幅 350~500 字;結構:整體感覺 → 先改 1~2 件事(「現在」+「改成」)→ 下次拍攝小提醒 → **練習方式(放最後,每個要改的點對應一個,寫清楚做法/次數/做到什麼感覺算對)**。
- **完全禁止**出現「角度、度數、°、速度、位移、身體單位、峰值」與任何數字;用「身體位置、方向、看得到/感覺得到的動作」描述(例:「手肘再抬高一點,大概跟肩膀差不多高」)。
- 純文字,不用 LaTeX。模型仍可能輸出 `$113.9^\circ$`,所以 `delatex()` 會轉成純文字;**只有內容含 `\`、`^` 或純數字才轉**,避免吃掉 `$5-$10` 這類金額。
- 有「品質警告」時,第一句要先說明條件限制。
- 量化數據仍會送給模型當判斷依據,只是不准念出來。

## 7. 已知問題 / 待辦(依價值排序)

1. **尚未做「自動切出每一次投擲」**。使用者的測試影片有 ~8 次投擲,指標(出手時間、後拉最小角度等)是整段影片的全域極值,對 Gemini 很混亂(它會說「後拉 0.07 秒、出手 17.97 秒」)。建議:用手腕速度峰值切段,讓使用者選「第 N 次」,指標與建議都針對該次。
2. **回拉階段追蹤不到**:回拉時手肘被頭/身體擋住,姿勢模型對手肘幾乎亂猜(可信度 0.01~0.04,上臂長度在 39~142px 亂跳,標準 108px),手部模型也幾乎偵測不到(9/70 幀)。嚴格模式線乾淨但這段中斷;**寬鬆模式**(手腕只要求肩→腕距離 ≤ 1.15×手臂長)能補回,但 Python 實測是上下亂竄的鋸齒。這是模型/視角上限,不是過濾能解決。若要真正解決,需要更好的視角(側面全身)或換模型。
3. 食指在「手部模型」與「姿勢模型」之間切換來源,會跳動(尚未固定單一來源)。
4. 骨架線沒有平滑。
5. 匯出疊圖影片在 Safari 的格式支援未測;`requestVideoFrameCallback` 在舊版 Safari 不支援(此時略過幀率偵測)。
6. **整個網頁沒有在真實瀏覽器裡完整跑過**(見 §8),請接手者第一件事是用真影片跑一遍並回報問題。

## 8. 測試與環境注意事項

- **Chrome 自動化(claude-in-chrome)測不了**:自動化分頁是背景狀態(`visibilityState: hidden`),連最單純的 `<video>` 都停在 `readyState 0`;檔案上傳工具也不允許讀 `~/Downloads`。因此網頁行為只做了 `node --check` 語法檢查,數據驗證靠 Python 原型。
- **Python 原型**(不在 repo 內,放在 session 暫存區,可自行重建):
  - 用 venv 裝 `mediapipe==0.10.14`、`numpy<2`、`opencv-python-headless==4.9.0.80`、`matplotlib`。
  - **不要用 mediapipe 1.0.1**:macOS 上初始化就崩(`DrishtiMetalHelper ... Service is unavailable`),即使指定 CPU delegate。
  - 模型:`pose_landmarker_{full,heavy}.task`、`hand_landmarker.task`(`storage.googleapis.com/mediapipe-models/...`)。
  - 原型把 `index.html` 的處理(骨長閘門、Hampel、One Euro)用 numpy 重寫,輸出各階段的有效幀數、抖動(二階差分 RMS)與疊圖,用來驗證改動。
- 語法檢查方法:把 `<script type="module">` 內容抽出成 `.mjs` 後 `node --check`。純函式(如 `delatex`)可用 `new Function` 取出單獨測。

### 測試影片(都在使用者本機 `~/Downloads/`,不在 repo)

| 影片 | 特徵 | 結論 |
|---|---|---|
| `949a6502-…mp4` | 9.4 秒、背對鏡頭、人被切在畫面左緣 | 偵測成功率 33%,不適合追蹤;用來確認品質警告會觸發 |
| `980af365-…mp4` | 32 秒、側面、約 8 次投擲、30fps | 主要測試影片。標準模型 77% → heavy 98% |
| `motion-trace*.mp4` | 使用者從網頁匯出的疊圖影片(0.5 倍速錄製,長度約 2 倍) | 用來檢視實際畫面效果(線亂、閃爍等) |

### 關鍵實測數字(`980af365`,heavy 模型,投擲手=右)
- 手腕有畫線的幀數:放寬可見度前後 → 骨長嚴格閘門 328/969 → 修正逐幀檢查後 501/969 → 寬鬆模式 640/969。
- 手腕抖動(二階差分 RMS,身體單位):原始 ~0.65 → 處理後 ~0.19。
- 投擲手選擇:自動以「軌跡量」判斷會選錯(選到垂在身旁的手);此影片應選右手。網頁目前是**手動選**,沒有自動判斷。

## 9. 時間線(摘要)

1. 評估可行性:追蹤用 MediaPipe,Gemini 只做文字建議。
2. 做出第一版 `index.html`(姿勢+手部追蹤、軌跡、慢動作、匯出、Gemini)。
3. 加平滑與離群點(Hampel + One Euro)、平滑強度滑桿。
4. 修背景分頁卡住;加 120fps 選項、實際幀率偵測、拍攝品質提醒。
5. 發現側面影片肩寬失真 → 改軀幹尺度;軌跡改「最近 N 秒」。
6. 發現姿勢模型本身準度是瓶頸 → 加 heavy 模型、放寬可見度;加骨長閘門與簡化骨架。
7. 修閃爍(逐幀骨長檢查、軌跡不整條消失);修「全部」模式。
8. Gemini 輸出調整:LaTeX 轉換、排版、白話教練、不出現術語、練習放最後。
9. 加「追蹤過濾」嚴格/寬鬆/關閉選單(回拉階段取捨)。
