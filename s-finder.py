#!/usr/bin/env python3
"""
Scan Struts2 *validation.xml files, extract validators,
and export them to a CSV file to help migrate to Spring Bean Validation.

Usage:
    python struts_validator_mapper.py /path/to/your/project
    python struts_validator_mapper.py /path/to/your/project --csv-file my_validators.csv

If no path is given, the current directory is used.
"""

import argparse
import csv
import glob
import os
import re
import xml.etree.ElementTree as ET
from typing import Dict, List, Any, Tuple


# ----------------- find & parse ----------------- #

def find_validation_files(root: str) -> List[str]:
    """
    Find all *validation.xml files under the given root directory (recursively).
    """
    pattern = os.path.join(os.path.abspath(root), "**", "*validation.xml")
    return sorted(glob.glob(pattern, recursive=True))


def strip_doctype(xml_text: str) -> str:
    """
    Remove DOCTYPE line so ElementTree doesn't try to fetch DTDs.
    """
    return re.sub(r'<!DOCTYPE[^>]*>', '', xml_text, flags=re.IGNORECASE | re.MULTILINE)


def infer_class_and_method_from_filename(path: str) -> Tuple[str, str]:
    """
    Infer Struts action class simple name and method name from filename.

    Patterns:
      MyAction-validation.xml                 -> class_simple=MyAction, method_name=""
      MyAction-submitOrder-validation.xml     -> class_simple=MyAction, method_name="submitOrder"
    """
    base = os.path.basename(path)
    name = base[:-4] if base.lower().endswith(".xml") else base

    if not name.endswith("-validation"):
        # Not a standard Struts validation file, fallback
        return name, ""

    core = name[:-len("-validation")]  # remove suffix
    if "-" in core:
        # MyAction-submitOrder -> class=MyAction, method=submitOrder
        class_simple, method_name = core.split("-", 1)
    else:
        class_simple = core
        method_name = ""

    return class_simple, method_name


def guess_class_fqn(path: str, class_simple: str) -> str:
    """
    Try to guess the fully-qualified class name from the file path.

    Example:
      /repo/src/main/java/com/example/web/MyAction-validation.xml
      -> com.example.web.MyAction

    If guessing fails, just return class_simple.
    """
    norm = os.path.normpath(path)
    parts = norm.split(os.sep)

    for marker in ("java", "src"):
        if marker in parts:
            idx = parts.index(marker) + 1
            pkg_parts = parts[idx:-1]  # up to but excluding the file
            if pkg_parts:
                package = ".".join(pkg_parts)
                return f"{package}.{class_simple}"

    return class_simple


def parse_validation_file(path: str) -> List[Dict[str, Any]]:
    """
    Parse a Struts validation XML file and return a list of validator dicts.

    Each dict has:
      file, class_simple, class_fqn_guess, method_name,
      validator_scope (field/class),
      field_name (if scope=field),
      validator_type,
      params (dict),
      message
    """
    validators: List[Dict[str, Any]] = []

    class_simple, method_name = infer_class_and_method_from_filename(path)
    class_fqn = guess_class_fqn(path, class_simple)

    try:
        with open(path, "r", encoding="utf-8") as f:
            xml_text = f.read()
        xml_text = strip_doctype(xml_text)
        root = ET.fromstring(xml_text)
    except Exception as e:
        print(f"[WARN] Failed to parse {path}: {e}")
        return validators

    # Field-level validators: <field name="..."><field-validator type="...">...</field-validator></field>
    for field_elem in root.findall("field"):
        field_name = field_elem.get("name", "")

        for fv in field_elem.findall("field-validator"):
            vtype = fv.get("type", "")
            params = {}
            for p in fv.findall("param"):
                pname = p.get("name", "")
                pval = (p.text or "").strip()
                if pname:
                    params[pname] = pval

            msg_elem = fv.find("message")
            msg = (msg_elem.text or "").strip() if msg_elem is not None else ""

            validators.append(
                {
                    "file": path,
                    "class_simple": class_simple,
                    "class_fqn_guess": class_fqn,
                    "method_name": method_name,
                    "validator_scope": "field",
                    "field_name": field_name,
                    "validator_type": vtype,
                    "params": params,
                    "message": msg,
                }
            )

    # Class-level validators: <validator type="...">...</validator>
    for cv in root.findall("validator"):
        vtype = cv.get("type", "")
        params = {}
        for p in cv.findall("param"):
            pname = p.get("name", "")
            pval = (p.text or "").strip()
            if pname:
                params[pname] = pval

        msg_elem = cv.find("message")
        msg = (msg_elem.text or "").strip() if msg_elem is not None else ""

        validators.append(
            {
                "file": path,
                "class_simple": class_simple,
                "class_fqn_guess": class_fqn,
                "method_name": method_name,
                "validator_scope": "class",
                "field_name": "",
                "validator_type": vtype,
                "params": params,
                "message": msg,
            }
        )

    return validators


# ----------------- helpers ----------------- #

def flatten_params(params: Dict[str, str]) -> str:
    """
    Flatten params dict into 'name=value;name2=value2' for CSV.
    """
    if not params:
        return ""
    return ";".join(f"{k}={v}" for k, v in params.items())


def export_to_csv(validators: List[Dict[str, Any]], csv_path: str) -> None:
    """
    Export all validator mappings to a CSV file.
    """
    fieldnames = [
        "file",
        "class_simple",
        "class_fqn_guess",
        "method_name",
        "validator_scope",
        "field_name",
        "validator_type",
        "params",
        "message",
    ]

    with open(csv_path, mode="w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        for v in validators:
            row = {
                "file": v["file"],
                "class_simple": v["class_simple"],
                "class_fqn_guess": v["class_fqn_guess"],
                "method_name": v["method_name"],
                "validator_scope": v["validator_scope"],
                "field_name": v["field_name"],
                "validator_type": v["validator_type"],
                "params": flatten_params(v["params"]),
                "message": v["message"],
            }
            writer.writerow(row)


# ----------------- main ----------------- #

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Scan Struts2 *validation.xml files and export validators "
                    "to CSV to help migrate to Spring Bean Validation."
    )
    parser.add_argument(
        "root",
        nargs="?",
        default=".",
        help="Root directory to search (default: current directory).",
    )
    parser.add_argument(
        "--csv-file",
        default="struts_validators.csv",
        help="Output CSV file name (default: struts_validators.csv).",
    )
    args = parser.parse_args()

    validation_files = find_validation_files(args.root)
    if not validation_files:
        print(f"No *validation.xml files found under: {os.path.abspath(args.root)}")
        return

    print(f"Found {len(validation_files)} *validation.xml file(s).")
    print()

    all_validators: List[Dict[str, Any]] = []

    for path in validation_files:
        vals = parse_validation_file(path)
        all_validators.extend(vals)

    print(f"Total validators found: {len(all_validators)}")
    print(f"Writing CSV to: {os.path.abspath(args.csv_file)}")

    export_to_csv(all_validators, args.csv_file)
    print("Done.")


if __name__ == "__main__":
    main()
