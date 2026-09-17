from __future__ import annotations

import unittest

from scripts.set_lifetime_migration_eligible import migration_candidate


def user(
    *,
    platform: str = 'ios',
    status: str = 'active',
    lifetime: bool = False,
    eligible: bool = False,
) -> dict[str, object]:
    subscription: dict[str, object] = {
        'platform': platform,
        'status': status,
        'lifetime': lifetime,
    }
    if platform == 'ios':
        subscription['original_transaction_id'] = 'original-tx'
    elif platform == 'android':
        subscription['purchase_token'] = 'purchase-token'
    return {
        'subscription': subscription,
        'lifetime_migration_eligible': eligible,
    }


class LifetimeMigrationCandidateTest(unittest.TestCase):
    def test_all_monthly_statuses_are_included(self) -> None:
        for status in ('active', 'canceled', 'grace_period', 'expired'):
            with self.subTest(status=status):
                self.assertEqual(
                    migration_candidate(user(status=status)),
                    (True, status),
                )

    def test_android_monthly_purchase_is_included(self) -> None:
        self.assertEqual(
            migration_candidate(user(platform='android')),
            (True, 'active'),
        )

    def test_lifetime_and_manual_grants_are_excluded(self) -> None:
        self.assertEqual(
            migration_candidate(user(lifetime=True)),
            (False, 'already_lifetime'),
        )
        self.assertEqual(
            migration_candidate(user(platform='manual')),
            (False, 'not_store_purchase'),
        )

    def test_missing_source_id_is_excluded_before_showing_broken_offer(self) -> None:
        data = user()
        del data['subscription']['original_transaction_id']  # type: ignore[index]

        self.assertEqual(
            migration_candidate(data),
            (False, 'missing_source_id'),
        )

    def test_existing_roster_member_is_not_written_again(self) -> None:
        self.assertEqual(
            migration_candidate(user(eligible=True)),
            (False, 'already_eligible'),
        )


if __name__ == '__main__':
    unittest.main()
