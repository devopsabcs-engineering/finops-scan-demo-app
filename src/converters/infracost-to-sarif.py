#!/usr/bin/env python3
"""Convert Infracost JSON breakdown output to SARIF v2.1.0 format."""

import argparse
import json
import os
import sys

SARIF_SCHEMA = (
    "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/"
    "main/sarif-2.1/schema/sarif-schema-2.1.0.json"
)

DEFAULT_THRESHOLD = 50.0

RULE_ID = "FINOPS-COST-001"
RULE_NAME = "HighMonthlyCost"


def get_level(monthly_cost: float) -> str:
    """Return SARIF level based on monthly cost."""
    if monthly_cost > 500:
        return "error"
    if monthly_cost > 100:
        return "warning"
    return "note"


def convert(infracost_json_file: str, sarif_output_file: str, threshold: float) -> None:
    """Read Infracost JSON and produce SARIF JSON."""
    with open(infracost_json_file, "r", encoding="utf-8") as fh:
        data = json.load(fh)

    results = []
    projects = data.get("projects", [])

    for project in projects:
        project_name = project.get("name", "unknown")
        breakdown = project.get("breakdown", {})
        resources = breakdown.get("resources", [])

        for resource in resources:
            resource_name = resource.get("name", "unknown")
            monthly_cost_str = resource.get("monthlyCost")
            if monthly_cost_str is None:
                continue

            try:
                monthly_cost = float(monthly_cost_str)
            except (ValueError, TypeError):
                continue

            if monthly_cost < threshold:
                continue

            level = get_level(monthly_cost)
            results.append(
                {
                    "ruleId": RULE_ID,
                    "level": level,
                    "message": {
                        "text": (
                            f"Resource {resource_name} estimated at "
                            f"${monthly_cost:.2f}/month exceeds threshold "
                            f"of ${threshold:.2f}"
                        )
                    },
                    "locations": [
                        {
                            "logicalLocations": [
                                {
                                    "fullyQualifiedName": resource_name,
                                    "kind": "resource",
                                }
                            ]
                        }
                    ],
                    "properties": {
                        "monthlyCost": monthly_cost,
                        "costCurrency": "USD",
                        "projectName": project_name,
                    },
                }
            )

    security_severity = "7.0" if any(r["level"] == "error" for r in results) else "5.0"

    sarif = {
        "$schema": SARIF_SCHEMA,
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "infracost-to-sarif",
                        "version": "1.0.0",
                        "informationUri": "https://www.infracost.io",
                        "rules": [
                            {
                                "id": RULE_ID,
                                "name": RULE_NAME,
                                "shortDescription": {
                                    "text": "Resource monthly cost exceeds threshold"
                                },
                                "helpUri": "https://www.infracost.io/docs/",
                                "properties": {
                                    "security-severity": security_severity,
                                },
                            }
                        ],
                    }
                },
                "results": results,
            }
        ],
    }

    os.makedirs(os.path.dirname(sarif_output_file) or ".", exist_ok=True)
    with open(sarif_output_file, "w", encoding="utf-8") as fh:
        json.dump(sarif, fh, indent=2)

    print(
        f"Converted {len(results)} cost findings to {sarif_output_file} "
        f"(threshold: ${threshold:.2f})"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert Infracost JSON output to SARIF v2.1.0"
    )
    parser.add_argument(
        "infracost_json_file",
        help="Path to the Infracost JSON breakdown file",
    )
    parser.add_argument(
        "sarif_output_file",
        help="Path for the generated SARIF JSON file",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=DEFAULT_THRESHOLD,
        help=f"Monthly cost threshold in USD (default: {DEFAULT_THRESHOLD})",
    )
    args = parser.parse_args()

    if not os.path.isfile(args.infracost_json_file):
        print(
            f"Error: {args.infracost_json_file} does not exist",
            file=sys.stderr,
        )
        sys.exit(1)

    convert(args.infracost_json_file, args.sarif_output_file, args.threshold)


if __name__ == "__main__":
    main()
