import json
import random
import time
from datetime import datetime, timezone

from google import genai
from firebase_admin import firestore, initialize_app
from firebase_functions import https_fn
from google.cloud import secretmanager
from pythainlp.tokenize import subword_tokenize

initialize_app()

# --- Constants ---

GEMINI_MODEL = "gemini-2.5-flash"
API_TEMPERATURE = 0.8
API_MAX_TOKENS = 8192

STYLES = [
    "ニュース記事体（客観的・フォーマルな報道文体）",
    "口語体（友達同士のカジュアルな話し言葉）",
    "丁寧語（フォーマルな敬語・丁寧な表現）",
    "SNS・テキストメッセージ（略語・絵文字・短い表現）",
    "物語・文学体（描写的・書き言葉的な表現）",
]

TOPICS = [
    "あいさつ（朝、昼、夜のあいさつ、初対面、久しぶりの再会など）",
    "食べ物（レストランでの注文、料理の感想、食材の購入など）",
    "旅行（ホテル予約、道案内、観光地での会話など）",
    "感情（喜び、悲しみ、驚き、不安などの表現）",
    "仕事（職場での会話、ビジネスマナー、打ち合わせなど）",
    "家族（家族の紹介、日常会話、家族行事など）",
    "買い物（値段交渉、商品の質問、支払いなど）",
    "交通（タクシー、電車、バスでの会話）",
    "健康（病院、薬局、体調不良の説明など）",
    "天気（天気の話題、季節の挨拶など）",
    "趣味（スポーツ、音楽、映画などの趣味について）",
    "学校（授業、宿題、学校生活について）",
    "宗教・信仰（寺院訪問、お参り、托鉢、僧侶との会話、仏教行事など）",
    "伝統・祭り（ソンクラーン、ロイクラトン、王室行事、伝統儀式など）",
    "礼儀作法（ワイ（合掌）、年長者への敬意、タブー、社会的マナーなど）",
    "恋愛・男女関係（告白、デート、口説き文句、恋人同士の会話、別れなど）",
]

POLITENESS_LEVELS = [
    "フォーマル（丁寧語・敬語を使用）",
    "カジュアル（くだけた友達同士の表現）",
    "中立（一般的な日常表現）",
]

GRAMMAR_FOCUSES = [
    "疑問文（〜ไหม？〜มั้ย？など）",
    "否定文（ไม่〜、ไม่ได้〜など）",
    "条件文（ถ้า〜、หาก〜など）",
    "比較表現（กว่า、เหมือนなど）",
    "命令・依頼（〜นะ、〜ด้วยなど）",
    "可能表現（ได้、เป็นなど）",
    "過去・完了（แล้ว、เคยなど）",
    "助詞・接続詞（แต่、และ、หรือなど）",
]

VOCAB_LEVELS = [
    "初級（基本的な日常語彙のみ）",
    "中級（日常会話レベルの語彙）",
    "上級（やや専門的・慣用的な語彙）",
]

SENTENCE_LENGTHS = [
    "短文（5〜8単語）",
    "中文（9〜12単語）",
    "長文（13〜18単語）",
]

EMOTIONS = [
    "喜び・嬉しさ",
    "悲しみ・落ち込み",
    "驚き",
    "不安・心配",
    "感謝",
    "期待・楽しみ",
    "中立・平静",
]

LEARNING_PURPOSES = [
    "会話練習（実際に話せる表現の習得）",
    "語彙習得（新しい単語の導入）",
    "文法理解（文法パターンの習得）",
    "文化理解（タイ文化・習慣の学習）",
]

TONE_DENSITIES = [
    "低（同じ声調が多め・声調バリエーション少なめ）",
    "中（複数の声調をバランスよく含む）",
    "高（5種類の声調をまんべんなく含む・声調練習向け）",
]


# --- Helpers ---


def _get_gemini_api_key() -> str:
    import os

    client = secretmanager.SecretManagerServiceClient()
    project_id = os.environ.get("GCLOUD_PROJECT", "")
    name = f"projects/{project_id}/secrets/gemini-api-key/versions/latest"
    response = client.access_secret_version(request={"name": name})
    api_key = response.payload.data.decode("UTF-8")
    if not api_key:
        raise RuntimeError("SECRET_MANAGER_ERROR")
    return api_key


def _segment_syllables(word: str) -> list[str]:
    return subword_tokenize(word, engine="dict")


def _build_prompt(params: dict) -> str:
    topic = params.get("topic") or random.choice(TOPICS)
    style = params.get("style") or random.choice(STYLES)
    politeness = params.get("politeness") or random.choice(POLITENESS_LEVELS)
    grammar_focus = params.get("grammarFocus") or random.choice(GRAMMAR_FOCUSES)
    vocab_level = params.get("vocabLevel") or random.choice(VOCAB_LEVELS)
    sentence_length = params.get("sentenceLength") or random.choice(SENTENCE_LENGTHS)
    emotion = params.get("emotion") or random.choice(EMOTIONS)
    learning_purpose = params.get("learningPurpose") or random.choice(LEARNING_PURPOSES)
    tone_density = params.get("toneDensity") or random.choice(TONE_DENSITIES)
    custom_prompt = params.get("customPrompt", "")
    if custom_prompt:
        custom_prompt = custom_prompt[:20]

    custom_section = (
        f"\n13. ユーザーからの追加の指示: {custom_prompt}" if custom_prompt else ""
    )

    return f"""あなたは日本語話者向けに日々の練習文を作るタイ語教師です。

学習に必要な情報を含むタイ語の新しい文を1つ、JSON形式で生成してください。

要件:
1. 文は実用的な内容にする
2. 今回のトピック: {topic}
3. 文体スタイル: {style}
4. 丁寧さのレベル: {politeness}
5. 文法フォーカス: {grammar_focus}
6. 語彙レベル: {vocab_level}
7. 文の長さ: {sentence_length}
8. 感情・トーン: {emotion}
9. 学習目的: {learning_purpose}
10. 声調密度: {tone_density}
11. 単語分解は最大15単語まで
12. contextの各フィールドは簡潔に（各50文字以内）{custom_section}

次の形式の有効なJSONのみを返してください:

{{
  "thai_text": "タイ語の文",
  "pronunciation": "拼音風のローマ字発音（声調記号付き）(e.g., ไม่รู้สิ = mâi rúu sì, เหมือนกัน = mʉ̌ʉan kan, สุดท้าย = sùt-tháai, คำตอบ = kham-tɔ̀ɔp, ใช้ชีวิต = chái-chii-wít, ให้รู้ตัว = hâi rúu tua, ไม่ค่อย = mâi khâui, ก็ = kô, แหละ = lɛ̀)",
  "japanese_translation": "日本語訳",
  "word_breakdown": [
    {{
      "word": "タイ語の単語",
      "pronunciation": "単語の拼音風発音（声調記号付きローマ字）",
      "meaning": "単語の日本語の意味",
      "grammatical_role": "品詞（例: 名詞, 動詞, 形容詞, 助詞）"
    }}
  ],
  "context": {{
    "topic": "この表現を使う場面・場所",
    "style": "実際に使用した文体スタイル（例: ニュース記事体、口語体など）",
    "emotion": "感情・トーン（フォーマル/カジュアル/丁寧/親しみ）",
    "usage_scenarios": "具体的に使えるシチュエーション",
    "cultural_notes": "文化的背景やニュアンス"
  }}
}}"""


# --- Cloud Function ---


@https_fn.on_call(region="asia-northeast1", memory=512)
def generateThaiSentence(req: https_fn.CallableRequest) -> dict:
    start_time = time.time()
    response = {"success": False}

    log_data = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "userId": req.auth.uid if req.auth else "anonymous",
        "requestedTopic": (req.data or {}).get("topic", "random"),
    }

    try:
        # Auth check
        if not req.auth:
            log_data["error"] = "UNAUTHENTICATED"
            print(f"Authentication failed: {log_data}")
            response["error"] = {
                "code": "UNAUTHENTICATED",
                "message": "User must be authenticated",
            }
            return response

        print(f"Request started: {log_data}")

        # Get API key & init Gemini
        api_key = _get_gemini_api_key()
        client = genai.Client(api_key=api_key)

        # Generate
        params = req.data or {}
        prompt = _build_prompt(params)
        result = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=prompt,
            config=genai.types.GenerateContentConfig(
                temperature=API_TEMPERATURE,
                max_output_tokens=API_MAX_TOKENS,
                response_mime_type="application/json",
            ),
        )
        text = result.text

        if not text or not text.strip():
            raise RuntimeError("Empty response from Gemini API")

        sentence = json.loads(text)

        # PyThaiNLP syllable segmentation
        for wb in sentence.get("word_breakdown", []):
            wb["syllables"] = _segment_syllables(wb.get("word", ""))

        processing_time = int((time.time() - start_time) * 1000)
        log_data["success"] = True
        log_data["processingTimeMs"] = processing_time

        response["success"] = True
        response["data"] = sentence

        # Save to Firestore
        try:
            db = firestore.client()
            db.collection("users").document(req.auth.uid).collection("sentences").add(
                {
                    "thai_text": sentence["thai_text"],
                    "pronunciation": sentence["pronunciation"],
                    "japanese_translation": sentence["japanese_translation"],
                    "created_at": firestore.SERVER_TIMESTAMP,
                }
            )
        except Exception as e:
            print(f"Failed to save sentence to Firestore: {e}")

        print(f"Request completed successfully: {log_data}")
        return response

    except Exception as e:
        processing_time = int((time.time() - start_time) * 1000)
        log_data["success"] = False
        log_data["processingTimeMs"] = processing_time
        error_msg = str(e)
        log_data["errorMessage"] = error_msg

        if "SECRET_MANAGER_ERROR" in error_msg:
            response["error"] = {
                "code": "INTERNAL",
                "message": "Failed to retrieve API configuration",
            }
        elif "GEMINI_API_ERROR" in error_msg:
            response["error"] = {
                "code": "API_ERROR",
                "message": "Failed to generate sentence",
            }
        else:
            response["error"] = {
                "code": "UNKNOWN",
                "message": "An unexpected error occurred",
            }

        print(f"Request failed: {log_data}")
        return response
