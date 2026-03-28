#!/usr/bin/env python3
"""Convert Cloud Custodian JSON output to SARIF v2.1.0 format."""

import argparse
import json
import os
import sys

SARIF_SCHEMA = (
    "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/"
    "main/sarif-2.1/schema/sarif-schema-2.1.0.json"
)

POLICY_RULE_MAP = {
    "find-orphaned-disks": {
        "id": "FINOPS-ORPHAN-001",
        "name": "OrphanedDisk",
        "shortDescription": "Unattached managed disk detected",
        "helpUri": "https://learn.microsoft.com/azure/cost-management-billing/costs/cost-mgt-best-practices",
        "level": "warning",
        "security-severity": "6.0",
    },
    "find-orphaned-nics": {
        "id": "FINOPS-ORPHAN-002",
        "name": "OrphanedNIC",
        "shortDescription": "Unattached network interface detected",
        "helpUri": "https://learn.microsoft.com/azure/cost-management-billing/costs/cost-mgt-best-practices",
        "level": "warning",
        "security-severity": "4.0",
    },
    "find-orphaned-public-ips": {
        "id": "FINOPS-ORPHAN-003",
        "name": "OrphanedPublicIP",
        "shortDescription": "Unattached public IP address detected",
        "helpUri": "https://learn.microsoft.com/azure/cost-management-billing/costs/cost-mgt-best-practices",
        "level": "warning",
        "security-severity": "5.0",
    },
    "check-required-tags": {
        "id": "FINOPS-TAG-001",
        "name": "MissingRequiredTags",
        "shortDescription": "Resource group missing required governance tags",
        "helpUri": "https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging",
        "level": "error",
        "security-severity": "7.0",
    },
    "detect-oversized-vms": {
        "id": "FINOPS-SIZE-001",
        "name": "OversizedVM",
        "shortDescription": "VM SKU is oversized for workload environment",
        "helpUri": "https://learn.microsoft.com/azure/advisor/advisor-cost-recommendations",
        "level": "warning",
        "security-severity": "6.5",
    },
    "detect-oversized-plans": {
        "id": "FINOPS-SIZE-002",
        "name": "OversizedAppServicePlan",
        "shortDescription": "App Service Plan SKU is oversized for workload environment",
        "helpUri": "https://learn.microsoft.com/azure/advisor/advisor-cost-recommendations",
        "level": "warning",
        "security-severity": "6.5",
    },
    "detect-no-autoshutdown": {
        "id": "FINOPS-IDLE-001",
        "name": "NoAutoShutdown",
        "shortDescription": "Development VM running without auto-shutdown schedule",
        "helpUri": "https://learn.microsoft.com/azure/devtest-labs/devtest-lab-auto-shutdown",
        "level": "warning",
        "security-severity": "5.5",
    },
}


def build_rule(policy_name: str, rule_info: dict) -> dict:
    """Build a SARIF rule descriptor from policy metadata."""
    return {
        "id": rule_info["id"],
        "name": rule_info["name"],
        "shortDescription": {"text": rule_info["shortDescription"]},
        "helpUri": rule_info["helpUri"],
        "properties": {"security-severity": rule_info["security-severity"]},
    }


def build_result(policy_name: str, resource: dict, rule_info: dict) -> dict:
    """Build a SARIF result entry from a single Custodian resource finding."""
    resource_id = resource.get("id", resource.get("name", "unknown"))
    resource_name = resource.get("name", resource_id.split("/")[-1] if "/" in str(resource_id) else str(resource_id))

    return {
        "ruleId": rule_info["id"],
        "level": rule_info["level"],
        "message": {
            "text": f"{rule_info['shortDescription']}: {resource_name} ({resource_id})"
        },
        "locations": [
            {
                "logicalLocations": [
                    {
                        "fullyQualifiedName": str(resource_id),
                        "kind": "resource",
                    }
                ]
            }
        ],
    }


def convert_empty(sarif_output_file: str) -> None:
    """Produce a valid SARIF file with no findings."""
    sarif = {
        "$schema": SARIF_SCHEMA,
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "custodian-to-sarif",
                        "version": "1.0.0",
                        "informationUri": "https://cloudcustodian.io",
                        "rules": [],
                    }
                },
                "results": [],
            }
        ],
    }
    os.makedirs(os.path.dirname(sarif_output_file) or ".", exist_ok=True)
    with open(sarif_output_file, "w", encoding="utf-8") as fh:
        json.dump(sarif, fh, indent=2)
    print(f"Produced empty SARIF at {sarif_output_file}")


def convert(custodian_output_dir: str, sarif_output_file: str) -> None:
    """Read Custodian output directory and produce SARIF JSON."""
    rules = []
    results = []
    seen_rules = set()

    for policy_dir in sorted(os.listdir(custodian_output_dir)):
        policy_path = os.path.join(custodian_output_dir, policy_dir)
        if not os.path.isdir(policy_path):
            continue

        resources_file = os.path.join(policy_path, "resources.json")
        if not os.path.isfile(resources_file):
            continue

        with open(resources_file, "r", encoding="utf-8") as fh:
            try:
                resources = json.load(fh)
            except json.JSONDecodeError:
                print(f"Warning: could not parse {resources_file}", file=sys.stderr)
                continue

        rule_info = POLICY_RULE_MAP.get(policy_dir)
        if rule_info is None:
            # Unknown policy — create a generic rule entry
            rule_info = {
                "id": f"FINOPS-UNKNOWN-{policy_dir}",
                "name": policy_dir,
                "shortDescription": f"Cloud Custodian policy violation: {policy_dir}",
                "helpUri": "https://cloudcustodian.io",
                "level": "note",
                "security-severity": "3.0",
            }

        if rule_info["id"] not in seen_rules:
            rules.append(build_rule(policy_dir, rule_info))
            seen_rules.add(rule_info["id"])

        for resource in resources:
            results.append(build_result(policy_dir, resource, rule_info))

    sarif = {
        "$schema": SARIF_SCHEMA,
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "custodian-to-sarif",
                        "version": "1.0.0",
                        "informationUri": "https://cloudcustodian.io",
                        "rules": rules,
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
        f"Converted {len(results)} findings from "
        f"{len(seen_rules)} rules to {sarif_output_file}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert Cloud Custodian JSON output to SARIF v2.1.0"
    )
    parser.add_argument(
        "custodian_output_dir",
        help="Directory containing Cloud Custodian policy output folders",
    )
    parser.add_argument(
        "sarif_output_file",
        help="Path for the generated SARIF JSON file",
    )
    args = parser.parse_args()

    if not os.path.isdir(args.custodian_output_dir):
        print(
            f"Warning: {args.custodian_output_dir} is not a directory, "
            "producing empty SARIF",
            file=sys.stderr,
        )
        # Produce valid empty SARIF instead of crashing
        convert_empty(args.sarif_output_file)
        return

    convert(args.custodian_output_dir, args.sarif_output_file)


if __name__ == "__main__":
    main()
