package poolreview

// ネイティブ確認の表を Google スプレッドシートで受け渡す。シートは1つで、回ごとにタブを足す。
// 認証は ADC から SheetAccount に成り代わる（gcloud の標準ログインには spreadsheets スコープを付けられないため）。
// シートは SheetAccount に編集者として共有し、ネイティブにはリンク共有で編集してもらう。

import (
	"context"
	"fmt"

	"google.golang.org/api/impersonate"
	"google.golang.org/api/option"
	"google.golang.org/api/sheets/v4"
)

// SheetAccount はシートを読み書きするサービスアカウント（tester。ADC のユーザーに TokenCreator を付けてある）。
const SheetAccount = "native-sheet@thai-memo-67139.iam.gserviceaccount.com"

// GSheet はネイティブ確認のスプレッドシート。
type GSheet struct {
	svc *sheets.Service
	id  string
}

// NewGSheet は ID のスプレッドシートを開く（URL の /d/<ID>/ の部分）。
func NewGSheet(ctx context.Context, id string) (*GSheet, error) {
	ts, err := impersonate.CredentialsTokenSource(ctx, impersonate.CredentialsConfig{
		TargetPrincipal: SheetAccount,
		Scopes:          []string{sheets.SpreadsheetsScope},
	})
	if err != nil {
		return nil, err
	}
	svc, err := sheets.NewService(ctx, option.WithTokenSource(ts))
	if err != nil {
		return nil, err
	}
	return &GSheet{svc: svc, id: id}, nil
}

// URL はスプレッドシートの URL。
func (g *GSheet) URL() string { return "https://docs.google.com/spreadsheets/d/" + g.id + "/edit" }

// AddTab は title のタブを足して表を書く。見出し行を固定し、id 列を隠し、判定の列をプルダウンにする。
// 同じ名前のタブが既にあればエラー（記入済みを上書きしない）。
func (g *GSheet) AddTab(ctx context.Context, title string, table [][]string) error {
	rows := int64(len(table))
	if rows < 2 {
		return fmt.Errorf("表に文が無い")
	}
	res, err := g.svc.Spreadsheets.BatchUpdate(g.id, &sheets.BatchUpdateSpreadsheetRequest{
		Requests: []*sheets.Request{{AddSheet: &sheets.AddSheetRequest{Properties: &sheets.SheetProperties{
			Title:          title,
			GridProperties: &sheets.GridProperties{FrozenRowCount: 1, RowCount: rows, ColumnCount: numCols},
		}}}},
	}).Context(ctx).Do()
	if err != nil {
		return fmt.Errorf("タブ %q を足せない（シートを %s に編集者で共有したか）: %w", title, SheetAccount, err)
	}
	sid := res.Replies[0].AddSheet.Properties.SheetId

	vals := make([][]any, len(table))
	for i, r := range table {
		vals[i] = make([]any, len(r))
		for j, c := range r {
			vals[i][j] = c
		}
	}
	if _, err := g.svc.Spreadsheets.Values.Update(g.id, a1(title), &sheets.ValueRange{Values: vals}).
		ValueInputOption("RAW").Context(ctx).Do(); err != nil {
		return err
	}

	col := func(c int64) *sheets.DimensionRange {
		return &sheets.DimensionRange{SheetId: sid, Dimension: "COLUMNS", StartIndex: c, EndIndex: c + 1}
	}
	width := func(c, px int64) *sheets.Request {
		return &sheets.Request{UpdateDimensionProperties: &sheets.UpdateDimensionPropertiesRequest{
			Range: col(c), Properties: &sheets.DimensionProperties{PixelSize: px}, Fields: "pixelSize"}}
	}
	reqs := []*sheets.Request{
		{UpdateDimensionProperties: &sheets.UpdateDimensionPropertiesRequest{
			Range: col(colID), Properties: &sheets.DimensionProperties{HiddenByUser: true}, Fields: "hiddenByUser"}},
		width(colKeyWord, 100), width(colThai, 300), width(colTrans, 260), width(colScene, 240),
		width(colProposal, 300), width(colVerdict, 100), width(colFixedThai, 300), width(colComment, 280),
		{SetDataValidation: &sheets.SetDataValidationRequest{
			Range: &sheets.GridRange{SheetId: sid, StartRowIndex: 1, EndRowIndex: rows, StartColumnIndex: colVerdict, EndColumnIndex: colVerdict + 1},
			Rule: &sheets.DataValidationRule{
				Condition:    &sheets.BooleanCondition{Type: "ONE_OF_LIST", Values: verdictValues()},
				ShowCustomUi: true, Strict: true,
			}}},
		{RepeatCell: &sheets.RepeatCellRequest{
			Range:  &sheets.GridRange{SheetId: sid, StartRowIndex: 0, EndRowIndex: rows, StartColumnIndex: colKeyWord, EndColumnIndex: numCols},
			Cell:   &sheets.CellData{UserEnteredFormat: &sheets.CellFormat{WrapStrategy: "WRAP", VerticalAlignment: "TOP"}},
			Fields: "userEnteredFormat(wrapStrategy,verticalAlignment)"}},
		{RepeatCell: &sheets.RepeatCellRequest{
			Range:  &sheets.GridRange{SheetId: sid, StartRowIndex: 0, EndRowIndex: 1},
			Cell:   &sheets.CellData{UserEnteredFormat: &sheets.CellFormat{TextFormat: &sheets.TextFormat{Bold: true}}},
			Fields: "userEnteredFormat.textFormat.bold"}},
	}
	reqs = append(reqs, verdictColors(sid)...)
	_, err = g.svc.Spreadsheets.BatchUpdate(g.id, &sheets.BatchUpdateSpreadsheetRequest{Requests: reqs}).Context(ctx).Do()
	return err
}

// ColorTab は既にあるタブ title の条件付き書式を、判定の色分けに付け直す（前に作ったタブ用）。
func (g *GSheet) ColorTab(ctx context.Context, title string) error {
	ss, err := g.svc.Spreadsheets.Get(g.id).Fields("sheets(properties,conditionalFormats)").Context(ctx).Do()
	if err != nil {
		return err
	}
	for _, sh := range ss.Sheets {
		if sh.Properties.Title == title {
			sid := sh.Properties.SheetId
			var reqs []*sheets.Request
			for range sh.ConditionalFormats {
				reqs = append(reqs, &sheets.Request{DeleteConditionalFormatRule: &sheets.DeleteConditionalFormatRuleRequest{SheetId: sid, Index: 0}})
			}
			reqs = append(reqs, verdictColors(sid)...)
			_, err := g.svc.Spreadsheets.BatchUpdate(g.id, &sheets.BatchUpdateSpreadsheetRequest{Requests: reqs}).Context(ctx).Do()
			return err
		}
	}
	return fmt.Errorf("タブ %q が無い", title)
}

// verdictColors は判定の欄に色を付ける条件付き書式（OK 緑・案でOK 青・FIX 黄・NG 赤）。
func verdictColors(sid int64) []*sheets.Request {
	colors := []struct {
		v       string
		r, g, b float64
	}{
		{VerdictOK, 0.85, 0.94, 0.83},
		{VerdictProposal, 0.81, 0.89, 0.97},
		{VerdictFix, 1.0, 0.95, 0.75},
		{VerdictNG, 0.96, 0.80, 0.80},
	}
	col := string(rune('A' + colVerdict))
	var reqs []*sheets.Request
	for _, c := range colors {
		reqs = append(reqs, &sheets.Request{AddConditionalFormatRule: &sheets.AddConditionalFormatRuleRequest{
			Rule: &sheets.ConditionalFormatRule{
				Ranges: []*sheets.GridRange{{SheetId: sid, StartRowIndex: 1, StartColumnIndex: colVerdict, EndColumnIndex: colVerdict + 1}},
				BooleanRule: &sheets.BooleanRule{
					Condition: &sheets.BooleanCondition{Type: "CUSTOM_FORMULA", Values: []*sheets.ConditionValue{
						{UserEnteredValue: fmt.Sprintf(`=$%s2="%s"`, col, c.v)}}},
					Format: &sheets.CellFormat{BackgroundColor: &sheets.Color{Red: c.r, Green: c.g, Blue: c.b}},
				},
			},
		}})
	}
	return reqs
}

func verdictValues() []*sheets.ConditionValue {
	out := make([]*sheets.ConditionValue, len(Verdicts))
	for i, v := range Verdicts {
		out[i] = &sheets.ConditionValue{UserEnteredValue: v}
	}
	return out
}

// ReadTab は title のタブの表（見出し行つき）を読む。
func (g *GSheet) ReadTab(ctx context.Context, title string) ([][]string, error) {
	res, err := g.svc.Spreadsheets.Values.Get(g.id, a1(title)).Context(ctx).Do()
	if err != nil {
		return nil, fmt.Errorf("タブ %q を読めない: %w", title, err)
	}
	out := make([][]string, len(res.Values))
	for i, r := range res.Values {
		out[i] = make([]string, len(r))
		for j, c := range r {
			out[i][j] = fmt.Sprint(c)
		}
	}
	return out, nil
}

// a1 はタブ全体の範囲（'タブ名'!A:G）。
func a1(title string) string {
	return fmt.Sprintf("'%s'!A:%c", title, rune('A'+numCols-1))
}
