// テスト用フェイクとして意図的にFirestoreのsealedクラスを実装する
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/services/sentence_view_marker.dart';

import '../helpers/fake_firebase.dart';

/// users/{uid}/sentences/{id} の update だけを見るフェイク。
class _Firestore extends Fake implements FirebaseFirestore {
  final Map<String, Map<String, dynamic>> updates = {};

  /// doc ID → 投げる例外。既読が書けない状況を作る。
  final Map<String, Object> failures = {};

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    expect(path, 'users');
    return _Collection(this);
  }
}

class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this._db);
  final _Firestore _db;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Doc(_db, path!);
}

class _Doc extends Fake implements DocumentReference<Map<String, dynamic>> {
  _Doc(this._db, this._id);
  final _Firestore _db;
  final String _id;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    expect(path, 'sentences');
    return _Collection(_db);
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    final failure = _db.failures[_id];
    if (failure != null) throw failure;
    _db.updates[_id] = Map<String, dynamic>.from(data);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Firestore firestore;
  late FakeFirebaseAuth auth;

  SentenceViewMarker marker() =>
      SentenceViewMarker(firestore: firestore, auth: auth);

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    firestore = _Firestore();
    auth = FakeFirebaseAuth()..user = FakeUser(uid: 'u1', isAnonymous: false);
  });

  test('表示した例文に viewed=true を書く', () async {
    final m = marker();
    m.markViewed('s1');
    await m.settled();

    expect(firestore.updates['s1'], {'viewed': true});
    expect((await prefs()).getStringList(SentenceViewMarker.sentKey), ['s1']);
    expect((await prefs()).getStringList(SentenceViewMarker.pendingKey),
        isEmpty);
  });

  test('送信済みの例文は二度書かない', () async {
    final m = marker();
    m.markViewed('s1');
    await m.settled();
    firestore.updates.clear();

    m.markViewed('s1');
    await m.settled();

    expect(firestore.updates, isEmpty);
  });

  test('IDが無ければ何もしない', () async {
    final m = marker();
    m.markViewed(null);
    m.markViewed('');
    await m.settled();

    expect(firestore.updates, isEmpty);
  });

  test('通信できなければ端末に溜め、flush で送り直す', () async {
    firestore.failures['s1'] =
        FirebaseException(plugin: 'firestore', code: 'unavailable');

    final m = marker();
    m.markViewed('s1');
    await m.settled();

    expect(firestore.updates, isEmpty);
    expect((await prefs()).getStringList(SentenceViewMarker.pendingKey), ['s1']);

    firestore.failures.clear();
    await m.flush();

    expect(firestore.updates['s1'], {'viewed': true});
    expect(
        (await prefs()).getStringList(SentenceViewMarker.pendingKey), isEmpty);
  });

  test('消えた例文は待ち行列から外す', () async {
    firestore.failures['gone'] =
        FirebaseException(plugin: 'firestore', code: 'not-found');

    final m = marker();
    m.markViewed('gone');
    await m.settled();

    expect(
        (await prefs()).getStringList(SentenceViewMarker.pendingKey), isEmpty);
    expect((await prefs()).getStringList(SentenceViewMarker.sentKey), isEmpty);
  });

  test('未ログインなら溜めておき、ログイン後の flush で送る', () async {
    auth.user = null;

    final m = marker();
    m.markViewed('s1');
    await m.settled();

    expect(firestore.updates, isEmpty);
    expect((await prefs()).getStringList(SentenceViewMarker.pendingKey), ['s1']);

    auth.user = FakeUser(uid: 'u1', isAnonymous: false);
    await m.flush();

    expect(firestore.updates['s1'], {'viewed': true});
  });

  test('clear で記録を消す', () async {
    final m = marker();
    m.markViewed('s1');
    await m.settled();

    await m.clear();

    expect((await prefs()).getStringList(SentenceViewMarker.sentKey), isNull);
    expect((await prefs()).getStringList(SentenceViewMarker.pendingKey), isNull);
  });
}
