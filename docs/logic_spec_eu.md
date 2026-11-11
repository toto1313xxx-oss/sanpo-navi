# EA_v3_EU ロジック仕様書

## 概要

EUR/USD 向け平均回帰型 Expert Advisor。
USD/JPY 版 (EA_v3) のリスク管理フレームを流用し、
通貨特性に合わせて以下を再設計している。

- エントリーロジック（SignalEU）: 平均回帰 (Bollinger + Z-score)
- サーキットブレーカー (CircuitBreakerEU): 既存 5 層 + 第 6 層 (相関リスク)
- マクロフィルター (MacroFilter): ECB/FRB 発表前後の停止
- リスク管理 (RiskManagerEU): ATR 動的サイジング

## 1. シグナル (SignalEU)

### 入力
- Bollinger Bands(20, 2.0) on H1
- RSI(14) on H1
- Z-score(20) on H1

### エントリー条件

ロング:
1. `close < lower_band`
2. `rsi < 30`
3. `z_score < -2.0`
4. 直近 5 本中 3 本以上が下落（過剰売り確認）

ショート:
1. `close > upper_band`
2. `rsi > 70`
3. `z_score > +2.0`
4. 直近 5 本中 3 本以上が上昇

### イグジット条件
- TP: 中央線（移動平均）到達
- SL: ATR(14) × 1.5
- タイムストップ: 48 本（2 日）経過で強制決済

## 2. サーキットブレーカー (CircuitBreakerEU)

| 層 | トリガー | アクション |
|----|----------|------------|
| 1  | 日次損失 > 口座 2%      | その日の新規停止 |
| 2  | 週次損失 > 口座 5%      | 週末まで新規停止 |
| 3  | 連敗 5 回                | 24 時間停止 |
| 4  | スプレッド > 平均の 3 倍 | 一時停止 (再評価) |
| 5  | VIX 急騰 (> 30)          | 新規停止 |
| 6  | **EUR 相関資産 (DXY/GOLD) との異常相関解除** | 新規停止 |

第 6 層は EU 独自。EUR/USD と DXY の逆相関が
30 本移動相関で +0.3 以上になったら市場構造が壊れていると判断。

## 3. マクロフィルター (MacroFilter)

停止対象イベント:
- ECB 政策金利発表
- FRB FOMC
- EUR / USD CPI
- 米国雇用統計 (NFP)
- Lagarde / Powell 講演

停止ウィンドウ: 発表前 60 分 〜 発表後 30 分。

実装は経済カレンダー CSV の事前読み込み方式
（MT5 標準の `CalendarValueHistory()` が使えない環境向けのフォールバック）。

## 4. リスク管理 (RiskManagerEU)

ポジションサイズ:
```
lot = (balance × risk_pct) / (ATR × pip_value × 1.5)
```

- `risk_pct`: 既定 0.5%、連敗で段階的に減衰 (0.5 → 0.3 → 0.2)
- 最大同時ポジション: 2
- 同方向ピラミッディング禁止

## 5. バックテストと検証項目

- 期間: 2018-01 〜 2025-10
- 最大 DD 目標: < 10%
- Sharpe 目標: > 1.2
- Profit Factor 目標: > 1.5
- 月次負け月: < 4 回/年
