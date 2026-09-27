# Skill Drift Audit

稽核一個已安裝的技能是否與來源一致、文件承諾的檔案是否真的存在，以及**沒有參與開發的人是否真的用得起來**。

## 這個技能解決什麼問題

技能悄悄落後於它的倉庫時，是最昂貴的一種壞掉：文件描述了已安裝程式碼沒有的行為，而且**不會有任何錯誤訊息告訴你**。「從未安裝的能力」和「壞掉的能力」長得一模一樣——所以你應該先排除漂移，再去追程式錯誤。

這個技能回答三個問題：

1. **漂移** — 已安裝的副本與來源是否逐位元組相同？
2. **契約** — SKILL.md 點名的檔案是否真的存在、可編譯、可執行？
3. **公民測試** — 沒有參與開發的人，能否只用隨附文件與自己的真實檔案完成任務？

## 這個技能包含什麼

```
skill-drift-audit/
├── SKILL.md
├── scripts/
│   ├── audit_skill_drift.py        比對兩份技能副本，逐檔檢查
│   ├── check_skill_contract.py     檢查文件承諾的資源是否存在且可用
│   └── citizen_test_kit.py         產出公民測試任務單，並判定交回的結果
├── references/
│   ├── drift-failure-modes.md      五種真實漂移與契約失效案例
│   └── citizen-developer-testing.md 公民測試的四項規範、八項有效性檢查、五種判定
└── templates/
    └── audit_report.example.json   兩個腳本輸出的 JSON 格式
```

## 環境需求

| 項目 | 需求 |
| --- | --- |
| Python | 3.10 以上 |
| 必裝套件 | 無（僅使用標準函式庫） |
| 選用 | `gh` CLI（確認遠端倉庫同步狀態時使用） |
| 選用 | `pyyaml`（技能結構驗證時需要） |

## 安裝方式

### 方式一：直接複製技能資料夾

```bash
cp -R skill-drift-audit ~/skills/
```

### 方式二：使用安裝腳本

```bash
./install.sh
```

安裝腳本會偵測既有安裝並加上時間戳備份，不會直接覆蓋。

## 使用流程

### 1. 確認來源本身是最新的

漂移的比對必須有可信的參照。先確認倉庫本身已同步：

```bash
cd <repo>
git status -sb
git fetch origin
echo "local : $(git rev-parse HEAD)"
echo "remote: $(git rev-parse origin/main)"
```

commit id 相同只能證明「提交相同」，不能證明「內容正確」。請把遠端檔案抓回來驗證內容：

```bash
gh api repos/<owner>/<repo>/contents/<path>/SKILL.md --jq '.content' \
  | base64 -d | grep -c '<最新章節標題>'
```

### 2. 稽核漂移

```bash
python skill-drift-audit/scripts/audit_skill_drift.py \
  --installed ~/skills/<skill-name> \
  --reference <repo>/<skill-name> \
  --json drift_report.json
```

結束碼 0 表示無漂移；1 表示有缺失、差異或額外檔案。

| 嚴重度 | 意義 | 處理 |
| --- | --- | --- |
| `MISSING` | 文件記載的能力不在安裝中 | 先重新安裝再使用 |
| `DIFFERING` | 已安裝的是不同版本 | 重新安裝；行為有變再比對備份 |
| `EXTRA` | 本機有、上游沒有 | 通常無害，但確認它不是掩蓋改名的舊檔 |

### 3. 稽核契約

```bash
python skill-drift-audit/scripts/check_skill_contract.py --skill ~/skills/<skill-name>
```

會抽出 SKILL.md 中所有 `scripts/`、`references/`、`templates/` 路徑逐一比對，編譯每個文件記載的 Python 檔，並找出殘留的樣板檔。

### 4. 公民開發者測試

前兩步都是自我檢查。一個技能可以全部通過，卻仍然沒人用得起來——因為作者會補上文件沒寫的知識（哪個參數重要、該用哪個範例檔、哪一步可以跳過），而那正是真實使用者所缺少的。

```bash
python skill-drift-audit/scripts/citizen_test_kit.py --emit \
  --skill-name <skill-name> \
  --artifact-type "一份 15 頁的 PowerPoint 簡報" \
  --out ./citizen_test
```

把任務單交給一位**沒有參與開發**、平常就會處理這類檔案的同事。**不要**解釋流程、不要指出腳本名稱、不要建議參數。收回結果後判定：

```bash
python skill-drift-audit/scripts/citizen_test_kit.py --evaluate \
  --result ./citizen_test/公民測試_結果回報單.json
```

五種判定：

| 判定 | 條件 |
| --- | --- |
| `PASS` | 八項有效性檢查全過、任務完成、產出與原始檔案一致 |
| `PASS_WITH_FRICTION` | 同上，但過程中需要重試或猜測 |
| `COACHED` | 只有接受額外協助才完成（不算通過） |
| `FAIL` | 卡住，或產出與原始檔案不一致 |
| `INVALID` | 八項檢查有任何一項不通過 |

最容易讓測試失效的三件事：

- 測試者用了技能自帶的範例檔，而不是自己的真實檔案——範例檔是被設計成會成功的，測不出硬編碼假設；
- 測試者讀了原始程式碼——那等於用程式碼取代了要受測的文件；
- 測試者被引導通過某一步——受協助的測試不算通過，但**卡住的那一點是整場最有價值的發現**，要記錄下來而不是丟掉。

> 判定為 `INVALID` 時，要修的是**測試**，不是技能：換一位測試者或換一份素材重測。

## 常見問題

**Q：`EXTRA` 檔案需要處理嗎？**
A：通常不需要。它代表本機有、上游沒有的檔案，可能是你自己的補充。只要確認它不是「上游已改名，而舊檔仍留在本機掩蓋新檔」即可。

**Q：可以只做漂移稽核，跳過公民測試嗎？**
A：可以，但要清楚你證明的是什麼。漂移與契約稽核證明**檔案存在且一致**，不能證明**別人用得起來**。如果這個技能要交給團隊使用，公民測試才是關鍵的那一步。

**Q：公民測試要幾位測試者？**
A：至少一位。若兩位測試者在同一點卡住，那就直接判定為文件缺陷，應補強文件後再測。

## 授權

MIT License，詳見 LICENSE。
