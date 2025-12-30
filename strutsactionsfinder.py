#!/usr/bin/env python3
"""
Scan Struts2 config files (struts*.xml), extract <action> mappings,
and export them to a CSV file to help migrate to Spring MVC.

Usage:
    python struts_action_mapper.py /path/to/your/project
    python struts_action_mapper.py /path/to/your/project --csv-file my_actions.csv

If no path is given, the current directory is used.
"""

import argparse
import csv
import glob
import os
import xml.etree.ElementTree as ET
from typing import Dict, List, Any


def find_struts_files(root: str) -> List[str]:
    """
    Find all struts*.xml files under the given root directory (recursively).
    """
    pattern = os.path.join(os.path.abspath(root), "**", "struts*.xml")
    return sorted(glob.glob(pattern, recursive=True))


def parse_struts_file(path: str) -> List[Dict[str, Any]]:
    """
    Parse a single Struts XML file and return a list of action dicts.

    Each dict has:
      file, package_name, namespace, extends,
      action_name, action_class, action_method,
      results: [ { name, type, target } ]
    """
    actions: List[Dict[str, Any]] = []

    try:
        tree = ET.parse(path)
        root = tree.getroot()
    except Exception as e:
        print(f"[WARN] Failed to parse {path}: {e}")
        return actions

    # Typical Struts config structure: <struts><package>...</package></struts>
    for package in root.findall("package"):
        pkg_name = package.get("name", "")
        namespace = package.get("namespace", "")
        extends = package.get("extends", "")

        for action in package.findall("action"):
            action_name = action.get("name", "")
            action_class = action.get("class", "")
            action_method = action.get("method", "")

            results = []
            for res in action.findall("result"):
                res_name = res.get("name", "")
                res_type = res.get("type", "dispatcher")  # Struts default
                target = (res.text or "").strip()
                results.append(
                    {
                        "name": res_name,
                        "type": res_type,
                        "target": target,
                    }
                )

            actions.append(
                {
                    "file": path,
                    "package_name": pkg_name,
                    "namespace": namespace,
                    "extends": extends,
                    "action_name": action_name,
                    "action_class": action_class,
                    "action_method": action_method,
                    "results": results,
                }
            )

    return actions


def guess_http_method(action_name: str) -> str:
    """
    Very simple heuristic to guess GET vs POST based on action name.
    You can tweak this list to match your naming conventions.
    """
    name_lower = (action_name or "").lower()

    post_verbs = (
        "save",
        "create",
        "update",
        "delete",
        "submit",
        "add",
        "remove",
        "cancel",
        "post",
        "do",
    )

    if any(name_lower.startswith(verb) for verb in post_verbs):
        return "POST"
    return "GET"


def suggest_spring_url(namespace: str, action_name: str) -> str:
    """
    Suggest a simple Spring MVC URL based on Struts namespace + action name.

    e.g. namespace="/devices", action_name="list" -> "/devices/list"
    You can later customize to REST-style URLs if you want.
    """
    ns = (namespace or "").strip()
    if not ns:
        ns = "/"

    ns = ns.rstrip("/")  # avoid trailing slash
    path = action_name or ""
    if not path:
        return ns or "/"

    return f"{ns}/{path}"


def print_mapping_card(action: Dict[str, Any]) -> None:
    """
    Print a human-friendly mapping card for one Struts action.
    """
    file = action["file"]
    pkg_name = action["package_name"]
    namespace = action["namespace"]
    extends = action["extends"]
    action_name = action["action_name"]
    action_class = action["action_class"]
    action_method = action["action_method"]
    results = action["results"]

    http_method = guess_http_method(action_name)
    spring_url = suggest_spring_url(namespace, action_name)

    print("=" * 80)
    print(f"File:                 {file}")
    print(f"Package name:         {pkg_name}")
    print(f"Package namespace(NS):{namespace}")
    print(f"Package extends:      {extends}")
    print("-" * 80)
    print(f"Action name (A):      {action_name}")
    print(f"Action class (C):     {action_class}")
    print(f"Action method (M):    {action_method}")
    print("-" * 80)
    print("Results:")
    if not results:
        print("  (no <result> elements found)")
    else:
        for res in results:
            name = res["name"] or "(default)"
            rtype = res["type"]
            target = res["target"]
            print(f"  - {name:<10} -> {target}  (type={rtype})")

    print("-" * 80)
    print("Spring MVC migration hints:")
    print(f"  Suggested HTTP verb:   {http_method}")
    print(f"  Suggested Spring URL:  {spring_url}")
    print("  Controller class:      (decide, e.g. DevicesController)")
    print("  Form/DTO class:        (decide, e.g. DeviceOrderForm)")
    print("  Model attribute name:  (decide, e.g. \"orderForm\")")
    print("=" * 80)
    print()


def flatten_results_for_csv(results: List[Dict[str, str]]) -> str:
    """
    Flatten the results list into a single string for CSV.

    Format: "name:type:target|name:type:target|..."
    """
    parts = []
    for r in results:
        name = r.get("name") or ""
        rtype = r.get("type") or ""
        target = r.get("target") or ""
        parts.append(f"{name}:{rtype}:{target}")
    return "|".join(parts)


def export_to_csv(actions: List[Dict[str, Any]], csv_path: str) -> None:
    """
    Export all action mappings to a CSV file.
    """
    fieldnames = [
        "file",
        "package_name",
        "namespace",
        "extends",
        "action_name",
        "action_class",
        "action_method",
        "results_flat",
        "suggested_http_method",
        "suggested_spring_url",
    ]

    with open(csv_path, mode="w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        for action in actions:
            http_method = guess_http_method(action["action_name"])
            spring_url = suggest_spring_url(action["namespace"], action["action_name"])
            results_flat = flatten_results_for_csv(action["results"])

            row = {
                "file": action["file"],
                "package_name": action["package_name"],
                "namespace": action["namespace"],
                "extends": action["extends"],
                "action_name": action["action_name"],
                "action_class": action["action_class"],
                "action_method": action["action_method"],
                "results_flat": results_flat,
                "suggested_http_method": http_method,
                "suggested_spring_url": spring_url,
            }
            writer.writerow(row)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Scan Struts2 XML files and export action mappings to CSV "
                    "to help migrate to Spring MVC."
    )
    parser.add_argument(
        "root",
        nargs="?",
        default=".",
        help="Root directory to search (default: current directory).",
    )
    parser.add_argument(
        "--csv-file",
        default="struts_actions.csv",
        help="Output CSV file name (default: struts_actions.csv).",
    )
    parser.add_argument(
        "--no-cards",
        action="store_true",
        help="Do not print mapping cards to stdout, only write CSV.",
    )
    args = parser.parse_args()

    struts_files = find_struts_files(args.root)
    if not struts_files:
        print(f"No struts*.xml files found under: {os.path.abspath(args.root)}")
        return

    print(f"Found {len(struts_files)} struts*.xml file(s).")
    print()

    all_actions: List[Dict[str, Any]] = []

    for path in struts_files:
        actions = parse_struts_file(path)
        all_actions.extend(actions)

        if not args.no_cards:
            for action in actions:
                print_mapping_card(action)

    print(f"Total actions found: {len(all_actions)}")
    print(f"Writing CSV to: {os.path.abspath(args.csv_file)}")

    export_to_csv(all_actions, args.csv_file)

    print("Done.")


if __name__ == "__main__":
    main()
