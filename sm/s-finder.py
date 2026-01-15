#!/usr/bin/env python3
"""
Scan Struts2 config files (struts*.xml), extract <action> mappings,
interceptor usage, and global settings, and export them to a CSV file
to help migrate to Spring MVC.

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


# ----------------- find & parse ----------------- #

def find_struts_files(root: str) -> List[str]:
    """
    Find all struts*.xml files under the given root directory (recursively).
    """
    pattern = os.path.join(os.path.abspath(root), "**", "struts*.xml")
    return sorted(glob.glob(pattern, recursive=True))


def parse_struts_file(path: str) -> List[Dict[str, Any]]:
    """
    Parse a single Struts XML file and return a list of action dicts.

    Each dict includes:
      file, package_name, namespace, extends,
      default_interceptor_ref,
      package_interceptors, package_interceptor_stacks,
      global_results, exception_mappings, result_types,
      action_name, action_class, action_method,
      action_interceptor_refs,
      results (action-level)
    """
    actions: List[Dict[str, Any]] = []

    try:
        tree = ET.parse(path)
        root = tree.getroot()
    except Exception as e:
        print(f"[WARN] Failed to parse {path}: {e}")
        return actions

    for package in root.findall("package"):
        pkg_name = package.get("name", "")
        namespace = package.get("namespace", "")
        extends = package.get("extends", "")

        # --- interceptors & stacks --- #
        package_interceptors = []
        package_interceptor_stacks = []

        interceptors_elem = package.find("interceptors")
        if interceptors_elem is not None:
            for inter in interceptors_elem.findall("interceptor"):
                package_interceptors.append(
                    {
                        "name": inter.get("name", ""),
                        "class": inter.get("class", ""),
                    }
                )
            for stack in interceptors_elem.findall("interceptor-stack"):
                stack_name = stack.get("name", "")
                refs = [
                    ref.get("name", "")
                    for ref in stack.findall("interceptor-ref")
                ]
                package_interceptor_stacks.append(
                    {"name": stack_name, "refs": refs}
                )

        default_interceptor_ref = ""
        default_ref_elem = package.find("default-interceptor-ref")
        if default_ref_elem is not None:
            default_interceptor_ref = default_ref_elem.get("name", "")

        # --- global results --- #
        global_results = []
        global_results_elem = package.find("global-results")
        if global_results_elem is not None:
            for res in global_results_elem.findall("result"):
                res_name = res.get("name", "")
                res_type = res.get("type", "dispatcher")
                target = (res.text or "").strip()
                global_results.append(
                    {
                        "name": res_name,
                        "type": res_type,
                        "target": target,
                    }
                )

        # --- global exception mappings --- #
        exception_mappings = []
        ex_elem = package.find("global-exception-mappings")
        if ex_elem is not None:
            for em in ex_elem.findall("exception-mapping"):
                exception_mappings.append(
                    {
                        "exception": em.get("exception", ""),
                        "result": em.get("result", ""),
                    }
                )

        # --- result types --- #
        result_types = []
        rt_elem = package.find("result-types")
        if rt_elem is not None:
            for rt in rt_elem.findall("result-type"):
                result_types.append(
                    {
                        "name": rt.get("name", ""),
                        "class": rt.get("class", ""),
                    }
                )

        # --- actions --- #
        for action in package.findall("action"):
            action_name = action.get("name", "")
            action_class = action.get("class", "")
            action_method = action.get("method", "")

            # action-specific results
            results = []
            for res in action.findall("result"):
                res_name = res.get("name", "")
                res_type = res.get("type", "dispatcher")
                target = (res.text or "").strip()
                results.append(
                    {
                        "name": res_name,
                        "type": res_type,
                        "target": target,
                    }
                )

            # action-specific interceptor refs
            action_interceptor_refs = [
                ref.get("name", "")
                for ref in action.findall("interceptor-ref")
            ]

            actions.append(
                {
                    "file": path,
                    "package_name": pkg_name,
                    "namespace": namespace,
                    "extends": extends,
                    "default_interceptor_ref": default_interceptor_ref,
                    "package_interceptors": package_interceptors,
                    "package_interceptor_stacks": package_interceptor_stacks,
                    "global_results": global_results,
                    "exception_mappings": exception_mappings,
                    "result_types": result_types,
                    "action_name": action_name,
                    "action_class": action_class,
                    "action_method": action_method,
                    "action_interceptor_refs": action_interceptor_refs,
                    "results": results,
                }
            )

    return actions


# ----------------- helpers ----------------- #

def guess_http_method(action_name: str) -> str:
    """
    Very simple heuristic to guess GET vs POST based on action name.
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
    """
    ns = (namespace or "").strip()
    if not ns:
        ns = "/"
    ns = ns.rstrip("/")  # avoid trailing slash

    path = action_name or ""
    if not path:
        return ns or "/"

    return f"{ns}/{path}"


def flatten_results_for_csv(results: List[Dict[str, str]]) -> str:
    """
    Flatten a list of result dicts into a single string for CSV.
    Format: "name:type:target|name:type:target|..."
    """
    parts = []
    for r in results:
        name = r.get("name") or ""
        rtype = r.get("type") or ""
        target = r.get("target") or ""
        parts.append(f"{name}:{rtype}:{target}")
    return "|".join(parts)


def flatten_interceptors_for_csv(interceptors: List[Dict[str, str]]) -> str:
    """
    Flatten list of package interceptors.
    Format: "name->class|name->class|..."
    """
    parts = []
    for i in interceptors:
        name = i.get("name") or ""
        cls = i.get("class") or ""
        parts.append(f"{name}->{cls}")
    return "|".join(parts)


def flatten_stacks_for_csv(stacks: List[Dict[str, Any]]) -> str:
    """
    Flatten list of interceptor stacks.
    Format: "stackName:[ref1,ref2]|stackName2:[ref3]|..."
    """
    parts = []
    for s in stacks:
        name = s.get("name") or ""
        refs = s.get("refs") or []
        refs_str = ",".join(refs)
        parts.append(f"{name}:[{refs_str}]")
    return "|".join(parts)


def flatten_exception_mappings_for_csv(mappings: List[Dict[str, str]]) -> str:
    """
    Flatten global exception mappings.
    Format: "exception->result|..."
    """
    parts = []
    for m in mappings:
        ex = m.get("exception") or ""
        res = m.get("result") or ""
        parts.append(f"{ex}->{res}")
    return "|".join(parts)


def flatten_result_types_for_csv(result_types: List[Dict[str, str]]) -> str:
    """
    Flatten result types.
    Format: "name->class|..."
    """
    parts = []
    for rt in result_types:
        name = rt.get("name") or ""
        cls = rt.get("class") or ""
        parts.append(f"{name}->{cls}")
    return "|".join(parts)


def print_mapping_card(action: Dict[str, Any]) -> None:
    """
    Print a human-friendly mapping card for one Struts action.
    """
    file = action["file"]
    pkg_name = action["package_name"]
    namespace = action["namespace"]
    extends = action["extends"]
    default_int = action["default_interceptor_ref"]
    action_name = action["action_name"]
    action_class = action["action_class"]
    action_method = action["action_method"]
    results = action["results"]
    action_int_refs = action["action_interceptor_refs"]

    http_method = guess_http_method(action_name)
    spring_url = suggest_spring_url(namespace, action_name)

    print("=" * 80)
    print(f"File:                 {file}")
    print(f"Package name:         {pkg_name}")
    print(f"Package namespace(NS):{namespace}")
    print(f"Package extends:      {extends}")
    print(f"Default interceptor:  {default_int}")
    print("-" * 80)
    print(f"Action name (A):      {action_name}")
    print(f"Action class (C):     {action_class}")
    print(f"Action method (M):    {action_method}")
    print(f"Action interceptor-refs: {', '.join(action_int_refs) or '(none)'}")
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


def export_to_csv(actions: List[Dict[str, Any]], csv_path: str) -> None:
    """
    Export all action mappings to a CSV file.
    """
    fieldnames = [
        "file",
        "package_name",
        "namespace",
        "extends",
        "default_interceptor_ref",
        "package_interceptors_flat",
        "package_interceptor_stacks_flat",
        "global_results_flat",
        "exception_mappings_flat",
        "result_types_flat",
        "action_name",
        "action_class",
        "action_method",
        "action_interceptor_refs",
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
            pkg_interceptors_flat = flatten_interceptors_for_csv(action["package_interceptors"])
            stacks_flat = flatten_stacks_for_csv(action["package_interceptor_stacks"])
            global_results_flat = flatten_results_for_csv(action["global_results"])
            exception_mappings_flat = flatten_exception_mappings_for_csv(action["exception_mappings"])
            result_types_flat = flatten_result_types_for_csv(action["result_types"])

            row = {
                "file": action["file"],
                "package_name": action["package_name"],
                "namespace": action["namespace"],
                "extends": action["extends"],
                "default_interceptor_ref": action["default_interceptor_ref"],
                "package_interceptors_flat": pkg_interceptors_flat,
                "package_interceptor_stacks_flat": stacks_flat,
                "global_results_flat": global_results_flat,
                "exception_mappings_flat": exception_mappings_flat,
                "result_types_flat": result_types_flat,
                "action_name": action["action_name"],
                "action_class": action["action_class"],
                "action_method": action["action_method"],
                "action_interceptor_refs": ",".join(action["action_interceptor_refs"]),
                "results_flat": results_flat,
                "suggested_http_method": http_method,
                "suggested_spring_url": spring_url,
            }
            writer.writerow(row)


# ----------------- main ----------------- #

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Scan Struts2 XML files and export action mappings, "
                    "interceptors, and global settings to CSV "
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
