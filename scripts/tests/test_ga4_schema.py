from __future__ import annotations

import unittest

from scripts.ga4_funnel import parse_rows
from scripts.ga4_register_dimension import (
    DIMENSIONS,
    METRICS,
    missing_definitions,
)


class Ga4SchemaTest(unittest.TestCase):
    def test_definition_keys_are_unique(self) -> None:
        dimension_keys = [(item.parameter, item.scope) for item in DIMENSIONS]
        metric_keys = [item.parameter for item in METRICS]

        self.assertEqual(len(dimension_keys), len(set(dimension_keys)))
        self.assertEqual(len(metric_keys), len(set(metric_keys)))

    def test_boolean_parameters_are_dimensions(self) -> None:
        event_dimensions = {
            item.parameter for item in DIMENSIONS if item.scope == "EVENT"
        }
        metrics = {item.parameter for item in METRICS}

        for parameter in ("correct", "is_premium", "monotone", "product_loaded", "ok"):
            self.assertIn(parameter, event_dimensions)
            self.assertNotIn(parameter, metrics)

    def test_score_parameters_do_not_collide(self) -> None:
        metrics = {item.parameter for item in METRICS}

        self.assertIn("pronunciation_score", metrics)
        self.assertIn("quiz_score", metrics)
        self.assertNotIn("score", metrics)

    def test_missing_definitions_respects_scope(self) -> None:
        dimensions = [
            {"parameterName": "tier", "scope": "EVENT"},
            {"parameterName": "source", "scope": "EVENT"},
        ]
        metrics = [{"parameterName": "recognized_pct"}]

        missing_dimensions, missing_metrics = missing_definitions(dimensions, metrics)
        missing_dimension_keys = {
            (item.parameter, item.scope) for item in missing_dimensions
        }

        self.assertNotIn(("tier", "EVENT"), missing_dimension_keys)
        self.assertIn(("tier", "USER"), missing_dimension_keys)
        self.assertNotIn("recognized_pct", {item.parameter for item in missing_metrics})


class Ga4FunnelTest(unittest.TestCase):
    def test_parse_rows_reads_closed_funnel_metrics(self) -> None:
        report = {
            "funnelTable": {
                "rows": [
                    {
                        "dimensionValues": [{"value": "1. first_open"}],
                        "metricValues": [
                            {"value": "10"},
                            {"value": "0.8"},
                            {"value": "2"},
                        ],
                    },
                    {
                        "dimensionValues": [{"value": "2. onboarding_start"}],
                        "metricValues": [
                            {"value": "8"},
                            {"value": "1"},
                            {"value": "0"},
                        ],
                    },
                ]
            }
        }

        self.assertEqual(
            parse_rows(report),
            [("first_open", 10, 0.8, 2), ("onboarding_start", 8, 1.0, 0)],
        )


if __name__ == "__main__":
    unittest.main()
