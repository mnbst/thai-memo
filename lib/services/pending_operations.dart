/// 実行中の学習処理を追跡する。保存先を消す前に、開始済みの処理を完了させる。
class PendingOperations {
  final Set<Future<void>> _pending = {};

  Future<T> track<T>(Future<T> operation) {
    late final Future<void> settled;
    settled = operation
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _pending.remove(settled));
    _pending.add(settled);
    // 成否は元の呼び出し元に返す。待ち合わせ側では失敗も「完了」として扱う。
    return operation;
  }

  Future<void> settle() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }
}
