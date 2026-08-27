package uvm

import (
	"context"
	"fmt"
	"math/rand"
	"strings"

	"cloud.google.com/go/firestore"
)

// ランキングの表示名に使うタイ人名（uvm.py:NICKNAME_GIVEN_NAMES / _SURNAMES）。
// 名はタイの一般的なチューレン（ชื่อเล่น＝あだ名）、姓はタイに多い姓の形。
// 名＋姓の組み合わせだけで十分にばらけるので、数字は衝突時のみ足す。
var nicknameGivenNames = [...]string{
	"Ploy", "Mint", "Fern", "Nan", "Aum", "Beam", "Boss", "Champ",
	"Earth", "Film", "Gift", "Ice", "June", "Ken", "Mook", "Nut",
	"Oat", "Pim", "Praew", "Tan", "Ton", "View", "Win", "Yok",
	"Bank", "Best", "Gun", "Nam", "Fah", "Bow", "Cake", "Dew",
	"Focus", "Golf", "Jane", "Kwan", "Lek", "May", "Nink", "Opal",
	"Pat", "Puy", "Rung", "Som", "Tar", "Tui", "Ummi", "Vee",
	"Wan", "Yui", "Bam", "Chom", "Da", "Eak", "Grace", "Jib",
	"Kim", "Mai", "New", "Noon", "Pao", "Ping", "Sea", "Tam",
}

var nicknameSurnames = [...]string{
	"Sukjai", "Chaiyaphon", "Srisuwan", "Wongthep", "Rattanakorn", "Boonmee",
	"Phongsak", "Thongchai", "Saetang", "Kittisak", "Jaidee", "Maneerat",
	"Piyawat", "Sombat", "Chansiri", "Preecha", "Narong", "Sirikul",
	"Wattana", "Anuwat", "Kanjana", "Lertsak", "Meesuk", "Nopporn",
	"Panya", "Rojana", "Sanguan", "Suwannee", "Tavorn", "Udomsak",
	"Wiriya", "Yotsapon", "Amporn", "Bunnag", "Charoen", "Duangjai",
	"Intira", "Kraisorn", "Malai", "Nakhon", "Phanit", "Rungrat",
	"Somchai", "Thanapon", "Uthai", "Wichian", "Yindee", "Chaowalit",
}

// assignNickname は未設定のユーザーに表示名を自動で割り当てる
// （uvm.py:_assign_nickname）。
//
// ユーザーに入力させない代わりに nicknames/{小文字の名前} を Create で押さえて
// 一意性を担保する（既存なら AlreadyExists で弾かれる）。
// 5回試して埋まっていたら空文字を返し、呼び出し側は nickname を書かない。
func assignNickname(ctx context.Context, db *firestore.Client, uid string) string {
	for attempt := range 5 {
		name := fmt.Sprintf("%s %s",
			nicknameGivenNames[rand.Intn(len(nicknameGivenNames))],
			nicknameSurnames[rand.Intn(len(nicknameSurnames))])
		// 名＋姓が埋まっていたら数字で逃がす
		if attempt >= 2 {
			name = fmt.Sprintf("%s %d", name, 10+rand.Intn(90))
		}
		_, err := db.Collection("nicknames").Doc(strings.ToLower(name)).
			Create(ctx, map[string]any{"uid": uid})
		if err == nil {
			return name
		}
		if !isAlreadyExists(err) {
			// 権限エラー等は再試行しても同じなので諦める。
			return ""
		}
	}
	return ""
}
