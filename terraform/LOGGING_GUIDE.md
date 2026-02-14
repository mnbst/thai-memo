# ログ収集と分析ガイド

Thai MemoのCloud Functionsログを収集・分析する方法

---

## 📊 収集されるデータ

### リクエストごとのログ

各リクエストで以下のデータが記録されます：

```json
{
  "timestamp": "2026-02-14T10:30:00.000Z",
  "userId": "abc123def456",
  "requestedSituation": "食べ物（レストランでの注文、料理の感想、食材の購入など）",
  "success": true,
  "processingTimeMs": 2340,
  "generatedSituation": "食べ物（レストランでの注文、料理の感想、食材の購入など）",
  "sentenceLength": 45,
  "wordCount": 8
}
```

### エラーログ

失敗した場合：

```json
{
  "timestamp": "2026-02-14T10:35:00.000Z",
  "userId": "abc123def456",
  "success": false,
  "processingTimeMs": 500,
  "errorCode": "GEMINI_API_ERROR",
  "errorMessage": "Rate limit exceeded"
}
```

---

## 🔍 ログの確認方法

### 1. GCP Consoleでリアルタイムログを確認

```bash
# ブラウザで開く
https://console.cloud.google.com/logs/query?project=thai-memo-backend

# または gcloud CLI で確認
gcloud logging read \
  'resource.type="cloud_function" AND resource.labels.function_name="generateThaiSentence"' \
  --limit 50 \
  --format json
```

### 2. 特定のユーザーのログを検索

```bash
gcloud logging read \
  'resource.type="cloud_function"
   AND jsonPayload.userId="abc123def456"' \
  --limit 10
```

### 3. エラーのみを表示

```bash
gcloud logging read \
  'resource.type="cloud_function"
   AND jsonPayload.success=false' \
  --limit 20
```

---

## 📈 BigQueryでの分析

ログはBigQueryに自動エクスポートされ、SQLで分析できます。

### デイリーレポート: 生成回数と成功率

```sql
SELECT
  DATE(timestamp) as date,
  COUNT(*) as total_requests,
  COUNTIF(jsonPayload.success = true) as successful,
  COUNTIF(jsonPayload.success = false) as failed,
  ROUND(COUNTIF(jsonPayload.success = true) / COUNT(*) * 100, 2) as success_rate
FROM
  `thai-memo-backend.thai_memo_logs.cloudaudit_googleapis_com_data_access_*`
WHERE
  resource.labels.function_name = 'generateThaiSentence'
  AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY
  date
ORDER BY
  date DESC
```

### ユーザーごとの利用状況

```sql
SELECT
  jsonPayload.userId as user_id,
  COUNT(*) as generation_count,
  AVG(jsonPayload.processingTimeMs) as avg_processing_time_ms,
  MAX(timestamp) as last_used
FROM
  `thai-memo-backend.thai_memo_logs.cloudaudit_googleapis_com_data_access_*`
WHERE
  resource.labels.function_name = 'generateThaiSentence'
  AND jsonPayload.success = true
  AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  user_id
ORDER BY
  generation_count DESC
LIMIT 100
```

### 人気のシチュエーション

```sql
SELECT
  jsonPayload.generatedSituation as situation,
  COUNT(*) as count,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) as percentage
FROM
  `thai-memo-backend.thai_memo_logs.cloudaudit_googleapis_com_data_access_*`
WHERE
  resource.labels.function_name = 'generateThaiSentence'
  AND jsonPayload.success = true
  AND jsonPayload.generatedSituation IS NOT NULL
GROUP BY
  situation
ORDER BY
  count DESC
```

### パフォーマンス分析

```sql
SELECT
  ROUND(jsonPayload.processingTimeMs, 0) as processing_time_ms,
  COUNT(*) as request_count,
  APPROX_QUANTILES(jsonPayload.processingTimeMs, 100)[OFFSET(50)] as median,
  APPROX_QUANTILES(jsonPayload.processingTimeMs, 100)[OFFSET(95)] as p95,
  APPROX_QUANTILES(jsonPayload.processingTimeMs, 100)[OFFSET(99)] as p99
FROM
  `thai-memo-backend.thai_memo_logs.cloudaudit_googleapis_com_data_access_*`
WHERE
  resource.labels.function_name = 'generateThaiSentence'
  AND jsonPayload.processingTimeMs IS NOT NULL
  AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
```

### エラー分析

```sql
SELECT
  jsonPayload.errorCode as error_code,
  COUNT(*) as error_count,
  ARRAY_AGG(jsonPayload.errorMessage LIMIT 5) as sample_messages
FROM
  `thai-memo-backend.thai_memo_logs.cloudaudit_googleapis_com_data_access_*`
WHERE
  resource.labels.function_name = 'generateThaiSentence'
  AND jsonPayload.success = false
  AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY
  error_code
ORDER BY
  error_count DESC
```

---

## 📉 Cloud Monitoringでのメトリクス確認

### カスタムメトリクスのダッシュボード作成

1. GCP Console → Monitoring → Dashboards
2. 「CREATE DASHBOARD」をクリック
3. 以下のメトリクスを追加：

#### 生成成功率
```
Metric: logging.googleapis.com/user/successful_sentence_generations
Resource Type: Cloud Function
Aggregation: Rate
```

#### エラー率
```
Metric: logging.googleapis.com/user/failed_sentence_generations
Resource Type: Cloud Function
Aggregation: Rate
Group By: error_code
```

#### 処理時間
```
Metric: logging.googleapis.com/user/sentence_generation_processing_time
Resource Type: Cloud Function
Aggregation: 95th percentile
```

---

## 🔔 アラート設定

### エラー率が高い場合のアラート

```bash
# Terraformで設定する場合（例）
resource "google_monitoring_alert_policy" "high_error_rate" {
  display_name = "High Error Rate - Thai Memo"
  combiner     = "OR"

  conditions {
    display_name = "Error rate > 10%"

    condition_threshold {
      filter          = "resource.type = \"cloud_function\" AND metric.type = \"logging.googleapis.com/user/failed_sentence_generations\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
}
```

---

## 💡 ベストプラクティス

### 1. 定期的な確認

- **毎週**: 成功率、エラー率を確認
- **毎月**: ユーザー数、人気のシチュエーションを分析

### 2. ログ保持期間

- Cloud Logging: 30日（デフォルト）
- BigQuery: 90日（Terraformで設定済み）
- 長期保存が必要な場合はCloud Storageにエクスポート

### 3. コスト管理

- BigQueryクエリは課金対象
- 大量のデータを扱う場合は、パーティショニングとクラスタリングを活用
- 定期的なレポートはスケジュールドクエリで自動化

---

## 🚀 次のステップ

1. **ダッシュボード作成**: 主要メトリクスを可視化
2. **アラート設定**: 異常を早期検知
3. **定期レポート**: BigQueryスケジュールドクエリで自動化

ログデータを活用して、アプリの改善に役立ててください！
