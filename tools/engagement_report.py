from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import DefaultCredentialsError
from google.cloud import firestore


REPO_ROOT = Path(__file__).resolve().parents[1]
FIREBASERC = REPO_ROOT / ".firebaserc"

DEFAULT_PROJECT_ALIAS = "prod"
DEFAULT_DAYS = 3

ACTIVITY_FIELDS = (
    "last_active_at",
    "last_sentence_generated_at",
    "last_quiz_generated_at",
    "last_quiz_answered_at",
)

COUNT_FIELDS = (
    "sentence_generated_count",
    "quiz_generated_count",
    "quiz_question_generated_count",
    "quiz_answer_count",
    "quiz_correct_count",
)


@dataclass(frozen=True)
class ActiveUser:
    uid: str
    tier: str
    data: dict[str, Any]


def load_project_id(project: str) -> str:
    if project.startswith("thai-"):
        return project

    with FIREBASERC.open() as f:
        projects = json.load(f).get("projects", {})

    project_id = projects.get(project)
    if not project_id:
        known = ", ".join(sorted(projects))
        raise SystemExit(f"Unknown Firebase project alias: {project}. Known aliases: {known}")
    return project_id


def to_utc_datetime(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value.astimezone(UTC)
    return None


def int_value(value: Any) -> int:
    return value if isinstance(value, int) else 0


def is_in_window(value: Any, cutoff: datetime) -> bool:
    dt = to_utc_datetime(value)
    return dt is not None and dt >= cutoff


def fetch_active_users(db: firestore.Client, cutoff: datetime) -> list[ActiveUser]:
    query = db.collection("users").where(filter=firestore.FieldFilter("last_active_at", ">=", cutoff))
    users: list[ActiveUser] = []
    for doc in query.stream():
        data = doc.to_dict() or {}
        tier = data.get("tier")
        users.append(ActiveUser(uid=doc.id, tier=tier if isinstance(tier, str) else "unknown", data=data))
    return users


def summarize(users: list[ActiveUser], cutoff: datetime) -> dict[str, Any]:
    tier_counts = Counter(user.tier for user in users)
    field_user_counts = {
        field: sum(1 for user in users if is_in_window(user.data.get(field), cutoff))
        for field in ACTIVITY_FIELDS
    }
    count_sums = {
        field: sum(int_value(user.data.get(field)) for user in users)
        for field in COUNT_FIELDS
    }

    active_times = [
        dt
        for user in users
        if (dt := to_utc_datetime(user.data.get("last_active_at"))) is not None
    ]

    return {
        "active_users": len(users),
        "active_users_by_tier": dict(sorted(tier_counts.items())),
        "users_with_activity_in_window": field_user_counts,
        "lifetime_metric_sums_for_active_users": count_sums,
        "latest_active_at": max(active_times).isoformat() if active_times else None,
        "oldest_active_at_in_window": min(active_times).isoformat() if active_times else None,
    }


def print_table(project: str, project_id: str, days: int, cutoff: datetime, summary: dict[str, Any]) -> None:
    print(f"Project: {project} ({project_id})")
    print(f"Window: last {days} days since {cutoff.isoformat()}")
    print()
    print(f"Active users: {summary['active_users']}")
    print()

    print("Active users by tier:")
    for tier, count in summary["active_users_by_tier"].items():
        print(f"  {tier}: {count}")
    if not summary["active_users_by_tier"]:
        print("  none: 0")
    print()

    print("Users with activity in window:")
    for field, count in summary["users_with_activity_in_window"].items():
        print(f"  {field}: {count}")
    print()

    print("Lifetime metric sums for active users:")
    for field, count in summary["lifetime_metric_sums_for_active_users"].items():
        print(f"  {field}: {count}")
    print()

    print(f"Latest last_active_at: {summary['latest_active_at']}")
    print(f"Oldest last_active_at in window: {summary['oldest_active_at_in_window']}")


def print_csv(summary: dict[str, Any]) -> None:
    writer = csv.writer(sys.stdout)
    writer.writerow(["section", "metric", "value"])
    writer.writerow(["summary", "active_users", summary["active_users"]])
    writer.writerow(["summary", "latest_active_at", summary["latest_active_at"]])
    writer.writerow(["summary", "oldest_active_at_in_window", summary["oldest_active_at_in_window"]])
    for metric, value in summary["active_users_by_tier"].items():
        writer.writerow(["active_users_by_tier", metric, value])
    for metric, value in summary["users_with_activity_in_window"].items():
        writer.writerow(["users_with_activity_in_window", metric, value])
    for metric, value in summary["lifetime_metric_sums_for_active_users"].items():
        writer.writerow(["lifetime_metric_sums_for_active_users", metric, value])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Aggregate Thai Memo user engagement metrics from Firestore."
    )
    parser.add_argument(
        "--project",
        default=os.environ.get("FIREBASE_PROJECT", DEFAULT_PROJECT_ALIAS),
        help="Firebase alias from .firebaserc or a raw project id. Default: prod",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=DEFAULT_DAYS,
        help="Lookback window in days. Default: 3",
    )
    parser.add_argument(
        "--format",
        choices=("table", "json", "csv"),
        default="table",
        help="Output format. Default: table",
    )
    parser.add_argument(
        "--credentials",
        help="Optional service account JSON path. Otherwise Application Default Credentials are used.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.days <= 0:
        raise SystemExit("--days must be greater than 0")

    if args.credentials:
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = args.credentials

    project_id = load_project_id(args.project)
    cutoff = datetime.now(UTC) - timedelta(days=args.days)

    try:
        db = firestore.Client(project=project_id)
        users = fetch_active_users(db, cutoff)
    except DefaultCredentialsError as exc:
        print(
            "Failed to load Google credentials. Run "
            "`gcloud auth application-default login` or pass `--credentials path/to/service-account.json`.",
            file=sys.stderr,
        )
        print(f"Detail: {exc}", file=sys.stderr)
        return 1
    except GoogleAPIError as exc:
        print(f"Firestore request failed: {exc}", file=sys.stderr)
        return 1

    summary = summarize(users, cutoff)

    if args.format == "json":
        payload = {
            "project": args.project,
            "project_id": project_id,
            "days": args.days,
            "cutoff": cutoff.isoformat(),
            **summary,
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    elif args.format == "csv":
        print_csv(summary)
    else:
        print_table(args.project, project_id, args.days, cutoff, summary)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
