import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';

Future<ProviderContainer> containerWithUser(Map<String, dynamic> user) async {
  final container = ProviderContainer(
    overrides: [
      userDocProvider.overrideWith((ref) => Stream.value(user)),
    ],
  );
  await container.read(userDocProvider.future);
  return container;
}

void main() {
  Map<String, dynamic> monthlyUser({Object? eligible}) => {
        'tier': 'premium',
        if (eligible != null) 'lifetime_migration_eligible': eligible,
        'subscription': {
          'platform': 'ios',
          'status': 'active',
          'lifetime': false,
        },
      };

  test('サーバーの対象フラグがtrueの月額ユーザーだけ案内対象になる', () async {
    final container = await containerWithUser(monthlyUser(eligible: true));
    addTearDown(container.dispose);

    expect(container.read(lifetimeMigrationEligibleProvider), isTrue);
  });

  test('対象フラグが無い月額ユーザーには案内しない', () async {
    final container = await containerWithUser(monthlyUser());
    addTearDown(container.dispose);

    expect(container.read(lifetimeMigrationEligibleProvider), isFalse);
  });

  test('対象フラグがfalseの月額ユーザーには案内しない', () async {
    final container = await containerWithUser(monthlyUser(eligible: false));
    addTearDown(container.dispose);

    expect(container.read(lifetimeMigrationEligibleProvider), isFalse);
  });
}
