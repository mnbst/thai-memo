// =============================================================================
// learning_progress_store.dart
// 学習の進み具合（セットのカーソル・いまの段・クイズの進行）を端末に1レコードで
// 持つ。
//
// 以前はカーソル（daily_set_progress）とクイズ（saved_confirmation_quiz /
// saved_summary_quiz）を別々のキーに書き、段は保存していなかった。段を保存して
// いないぶん、起動のたびにクイズの保存から段を逆算する必要があり、そのために
// 「持ち主」（例文ID・セットID）を保存へ添えて突き合わせていた。突き合わせは
// 復元の順序に依存し、カーソルより先に聞くと必ず捨てる（まとめクイズの結果で
// 閉じると、再起動でやり直しになった）。
//
// 3つを同じレコードへ原子的に書けば、整合はレコード自身が持つ。まとめクイズの
// 持ち主（セットID）は要らなくなり、捨てるのは「セットが変わったら一緒に消す」と
// いう1つの規則で足りる。確認クイズだけは、カーソルの外にある1本にも付きうるので
// 例文IDを持ち続ける。
//
// Firestore（端末間の正本）へ送るのはセットの部分だけで、そこは
// daily_set_progress_store.dart のまま変えていない。段とクイズは端末のもの。
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_set_progress_store.dart';

/// 学習タブのどの段にいるか。
enum LearningStage {
  sentence,
  confirmationQuiz,
  summaryQuiz;

  static LearningStage fromName(Object? value) {
    return LearningStage.values.firstWhere(
      (stage) => stage.name == value,
      orElse: () => LearningStage.sentence,
    );
  }
}

/// 端末に保存する学習の進み具合。
@immutable
class LearningProgressRecord {
  const LearningProgressRecord({
    this.set = const DailySetProgressSnapshot(),
    this.stage = LearningStage.sentence,
    this.confirmationQuiz,
    this.summaryQuiz,
  });

  /// セットの並びとカーソル。Firestore と共有する唯一の部分。
  final DailySetProgressSnapshot set;

  /// いまの段。保存するのは、結果画面や回答中で閉じた人を同じ場所へ戻すため。
  final LearningStage stage;

  /// 確認クイズ（1問）の進行。どの例文のものかは payload の sentence_id が
  /// 持つ（カーソルの外の1本にも付きうる）。カーソルが動けば一緒に消える。
  final Map<String, dynamic>? confirmationQuiz;

  /// まとめクイズ（5問）の進行。持ち主は進行中のセット。
  final Map<String, dynamic>? summaryQuiz;

  LearningProgressRecord copyWith({
    DailySetProgressSnapshot? set,
    LearningStage? stage,
    Map<String, dynamic>? confirmationQuiz,
    Map<String, dynamic>? summaryQuiz,
    bool clearConfirmationQuiz = false,
    bool clearSummaryQuiz = false,
  }) {
    return LearningProgressRecord(
      set: set ?? this.set,
      stage: stage ?? this.stage,
      confirmationQuiz:
          clearConfirmationQuiz ? null : confirmationQuiz ?? this.confirmationQuiz,
      summaryQuiz: clearSummaryQuiz ? null : summaryQuiz ?? this.summaryQuiz,
    );
  }

  Map<String, dynamic> toJson() => {
        'set': set.toJson(),
        'stage': stage.name,
        'confirmation_quiz': confirmationQuiz,
        'summary_quiz': summaryQuiz,
      };

  static LearningProgressRecord fromJson(Map<String, dynamic> data) {
    return LearningProgressRecord(
      set: data['set'] is Map
          ? DailySetProgressSnapshot.fromJson(
              Map<String, dynamic>.from(data['set'] as Map),
            )
          : const DailySetProgressSnapshot(),
      stage: LearningStage.fromName(data['stage']),
      confirmationQuiz: _asMap(data['confirmation_quiz']),
      summaryQuiz: _asMap(data['summary_quiz']),
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;
}

/// [LearningProgressRecord] の読み書き。読み書きは直列化する（書き手が
/// カーソル・クイズ・段の3つあり、読んで書き戻す間に割り込まれると消える）。
class LearningProgressStore {
  static const String key = 'learning_progress';

  /// 1.4.10 までのキー。読んで畳んだ時点で消す。
  static const String legacySetKey = 'daily_set_progress';
  static const String legacyConfirmationQuizKey = 'saved_confirmation_quiz';
  static const String legacySummaryQuizKey = 'saved_summary_quiz';

  /// 1.4.8 以前の、さらに古い分割キー。セットの復元だけが対象。
  static const List<String> legacySplitKeys = [
    'daily_set_ids',
    'daily_set_cursor',
    'daily_set_id',
    'pending_daily_sets',
    'completed_daily_set_ids',
  ];

  Future<void> _tail = Future.value();

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

  /// 書き込みが落ち着くまで待つ（テストと、保存直後に読む経路のため）。
  Future<void> settled() => _serialized(() async {});

  Future<LearningProgressRecord> load() => _serialized(_load);

  Future<LearningProgressRecord> _load() async {
    return _read(await SharedPreferences.getInstance());
  }

  /// レコードを読む。無ければ旧キーから畳む（直列化の内側で呼ぶこと）。
  Future<LearningProgressRecord> _read(SharedPreferences prefs) async {
    final encoded = prefs.getString(key);
    if (encoded != null && encoded.isNotEmpty) {
      try {
        return LearningProgressRecord.fromJson(
          Map<String, dynamic>.from(jsonDecode(encoded) as Map),
        );
      } catch (_) {
        // 壊れていれば旧キーからの読み直しに落とす。
      }
    }
    return _migrateLegacy(prefs);
  }

  /// 読んで、変えて、書き戻す。割り込みを避けるためここで直列化する。
  ///
  /// 読みは [load] と同じ経路を通す。ここで空のレコードから書き始めると、
  /// まだ畳んでいない旧キーを追い越して「何も無かったこと」にしてしまう。
  Future<LearningProgressRecord> update(
    LearningProgressRecord Function(LearningProgressRecord current) change,
  ) {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      final current = await _read(prefs);
      final next = change(current);
      await prefs.setString(key, jsonEncode(next.toJson()));
      return next;
    });
  }

  Future<void> clear() => _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        for (final name in [
          key,
          legacySetKey,
          legacyConfirmationQuizKey,
          legacySummaryQuizKey,
          ...legacySplitKeys,
        ]) {
          await prefs.remove(name);
        }
      });

  /// 旧キー（カーソル・確認クイズ・まとめクイズ）を1レコードへ畳む。
  ///
  /// 畳むときだけは、旧データが持っていた持ち主（例文ID・セットID）で突き合わせる。
  /// 別のセット・別の例文のものを引き継ぐと、終わったクイズの画面から学習が
  /// 再開してしまう。畳んだ後は、カーソルと同じレコードにいるので照合は要らない。
  Future<LearningProgressRecord> _migrateLegacy(SharedPreferences prefs) async {
    final setSnapshot = _readLegacySet(prefs);
    final activeSetId = setSnapshot.active?.setId;
    final activeSentenceId = setSnapshot.activeSentenceId;

    final summary = _readLegacyQuiz(
      prefs,
      legacySummaryQuizKey,
      ownerField: 'set_id',
      ownerId: activeSetId,
    );
    // 確認クイズの持ち主（例文ID）は畳んだ後も payload に残す。カーソルの外に
    // ある1本（起動失敗時の最新例文フォールバックなど）にも付きうるので、
    // セットのカーソルからは導けない。
    final confirmation = _readLegacyQuiz(
      prefs,
      legacyConfirmationQuizKey,
      ownerField: 'sentence_id',
      ownerId: activeSentenceId,
      keepOwner: true,
    );

    final record = LearningProgressRecord(
      set: setSnapshot,
      // 段は保存していなかったので、残っているまとめクイズから読み替える。
      // 確認クイズは例文画面からいつでも開き直せるので、段は動かさない。
      stage: summary != null ? LearningStage.summaryQuiz : LearningStage.sentence,
      confirmationQuiz: confirmation,
      summaryQuiz: summary,
    );

    await prefs.setString(key, jsonEncode(record.toJson()));
    for (final name in [
      legacySetKey,
      legacyConfirmationQuizKey,
      legacySummaryQuizKey,
      ...legacySplitKeys,
    ]) {
      await prefs.remove(name);
    }
    return record;
  }

  DailySetProgressSnapshot _readLegacySet(SharedPreferences prefs) {
    final encoded = prefs.getString(legacySetKey);
    if (encoded != null && encoded.isNotEmpty) {
      try {
        return DailySetProgressSnapshot.fromJson(
          Map<String, dynamic>.from(jsonDecode(encoded) as Map),
        );
      } catch (_) {
        // 壊れていれば、さらに古い分割キーへ落とす。
      }
    }
    return _readLegacySplitSet(prefs);
  }

  /// 1.4.8 以前の分割キーから読む。
  DailySetProgressSnapshot _readLegacySplitSet(SharedPreferences prefs) {
    final ids = prefs.getStringList('daily_set_ids') ?? const [];
    final setId = prefs.getString('daily_set_id');
    final cursor = prefs.getInt('daily_set_cursor') ?? 0;
    final completed =
        prefs.getStringList('completed_daily_set_ids') ?? const <String>[];
    final pending = <DailySetRef>[];
    try {
      final rawSets =
          (jsonDecode(prefs.getString('pending_daily_sets') ?? '[]') as List)
              .whereType<Map>();
      for (final raw in rawSets) {
        final set = DailySetRef.fromJson({
          'set_id': raw['set_id'],
          'sentence_ids': raw['sentence_ids'],
        });
        if (set != null) pending.add(set);
      }
    } catch (_) {
      // 壊れていれば待機列は諦める。進行中セットの復元は続ける。
    }

    final active = (setId != null && setId.isNotEmpty && ids.isNotEmpty)
        ? DailySetRef(setId: setId, sentenceIds: ids)
        : null;
    return DailySetProgressSnapshot(
      active: active,
      activeSentenceId: active != null && cursor >= 0 && cursor < ids.length
          ? ids[cursor]
          : null,
      pending: pending,
      completedSetIds: completed,
    );
  }

  /// 旧キーのクイズ保存を、持ち主が一致するときだけ引き継ぐ。
  ///
  /// まとめクイズの持ち主（セットID）は畳むときに落とす。新しいレコードでは
  /// カーソルと同じ場所にいるので、一致するかを毎回確かめる必要がない。
  /// 確認クイズの持ち主（例文ID）は [keepOwner] で残す。
  Map<String, dynamic>? _readLegacyQuiz(
    SharedPreferences prefs,
    String legacyKey, {
    required String ownerField,
    required String? ownerId,
    bool keepOwner = false,
  }) {
    final encoded = prefs.getString(legacyKey);
    if (encoded == null || encoded.isEmpty || ownerId == null) return null;
    try {
      final data = jsonDecode(encoded);
      if (data is! Map) return null;
      if (data[ownerField] != ownerId) return null;
      final quiz = Map<String, dynamic>.from(data);
      if (!keepOwner) quiz.remove(ownerField);
      return quiz;
    } catch (_) {
      return null;
    }
  }
}
