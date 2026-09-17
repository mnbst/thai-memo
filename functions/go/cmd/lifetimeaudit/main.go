// lifetimeaudit は買い切り（premium_lifetime / 無償移行）の doc を数える読み取り専用ツール。
//
// 返金通知用のキー（subscription.lifetime_transaction_id）を持たない買い切り
// 購入者が何人いるか＝dailyBatch の埋め戻し対象が何件あるかを確認する。
// 書き込みは一切しない。
//
//	gcloud auth application-default login
//	cd functions/go && go run ./cmd/lifetimeaudit -project thai-memo-prod
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"sort"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

var lifetimeProducts = map[string]bool{
	"premium_lifetime":      true,
	"premium_lifetime_test": true,
}

func main() {
	projectID := flag.String("project", "", "GCP プロジェクト ID（必須）")
	flag.Parse()
	if *projectID == "" {
		log.Fatal("-project は必須です")
	}

	ctx := context.Background()
	db, err := firestore.NewClient(ctx, *projectID)
	if err != nil {
		log.Fatalf("firestore クライアントの作成に失敗: %v", err)
	}
	defer db.Close()

	counts := map[string]int{}
	var backfill, unrecoverable []string

	it := db.Collection("users").Documents(ctx)
	defer it.Stop()
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			log.Fatalf("users の読み取りに失敗: %v", err)
		}
		data := doc.Data()
		sub, _ := data["subscription"].(map[string]any)
		tier, _ := data["tier"].(string)
		productID, _ := sub["product_id"].(string)
		source, _ := sub["lifetime_source"].(string)
		txID, _ := sub["lifetime_transaction_id"].(string)
		sourceTxID, _ := sub["lifetime_source_transaction_id"].(string)
		sourceToken, _ := sub["lifetime_source_purchase_token"].(string)
		originalTxID, _ := sub["original_transaction_id"].(string)
		purchaseToken, _ := sub["purchase_token"].(string)
		platform, _ := sub["platform"].(string)
		mark, _ := sub["lifetime"].(bool)

		counts["users"]++
		if lifetimeProducts[productID] {
			counts["product_id=買い切り"]++
		}
		if !mark {
			continue
		}
		counts["lifetime=true"]++
		counts["lifetime=true かつ tier="+tier]++
		if source == "monthly_migration" {
			counts["無償移行"]++
			if sourceTxID != "" || sourceToken != "" {
				counts["無償移行キーあり"]++
				continue
			}
			migratedAt, migratedOK := sub["lifetime_migrated_at"].(time.Time)
			updatedAt, updatedOK := sub["updated_at"].(time.Time)
			safe := migratedOK && updatedOK && !updatedAt.After(migratedAt)
			if safe && ((platform == "ios" && originalTxID != "") ||
				(platform == "android" && purchaseToken != "")) {
				backfill = append(backfill, doc.Ref.ID+" (無償移行)")
			} else {
				unrecoverable = append(unrecoverable,
					fmt.Sprintf("%s (無償移行 platform=%q original_transaction_id=%q)",
						doc.Ref.ID, platform, originalTxID))
			}
			continue
		}
		if txID != "" {
			counts["キーあり"]++
			continue
		}
		if tier != "premium" {
			counts["キーなし（premium 以外・対象外）"]++
			continue
		}
		switch {
		case lifetimeProducts[productID] && originalTxID != "":
			backfill = append(backfill, doc.Ref.ID)
		default:
			unrecoverable = append(unrecoverable,
				fmt.Sprintf("%s (product_id=%q original_transaction_id=%q)",
					doc.Ref.ID, productID, originalTxID))
		}
	}

	keys := make([]string, 0, len(counts))
	for k := range counts {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	fmt.Println("--- 集計 ---")
	for _, k := range keys {
		fmt.Printf("%s: %d\n", k, counts[k])
	}

	fmt.Printf("\n埋め戻し対象（dailyBatch が補える）: %d\n", len(backfill))
	for _, uid := range backfill {
		fmt.Printf("  %s\n", uid)
	}
	fmt.Printf("\nフィールド自動復元不能（通知時はowner fallback）: %d\n", len(unrecoverable))
	for _, line := range unrecoverable {
		fmt.Printf("  %s\n", line)
	}
}
