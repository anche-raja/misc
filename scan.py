#!/usr/bin/env python3
"""
GitLab Dependency Scanning Vulnerability JSON Parser
Extracts name, description, solution, and severity to CSV file
"""

import json
import csv
import sys
from pathlib import Path


def parse_gitlab_vulnerabilities(json_file_path):
    """
    Parse GitLab dependency scanning JSON file and extract vulnerability information.
    
    Args:
        json_file_path: Path to the GitLab vulnerability JSON file
        
    Returns:
        List of dictionaries containing vulnerability information
    """
    try:
        with open(json_file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: File '{json_file_path}' not found!")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON format - {e}")
        sys.exit(1)
    
    vulnerabilities = []
    
    # GitLab vulnerability reports have vulnerabilities in the 'vulnerabilities' key
    vuln_list = data.get('vulnerabilities', [])
    
    if not vuln_list:
        print("Warning: No vulnerabilities found in the JSON file")
        return vulnerabilities
    
    for vuln in vuln_list:
        # Extract location information
        location_info = vuln.get('location', {})
        dependency_info = location_info.get('dependency', {})
        package_info = dependency_info.get('package', {})
        
        # Extract identifiers (CVE, etc.)
        identifiers = vuln.get('identifiers', [])
        cve_list = [ident.get('value', '') for ident in identifiers if ident.get('type') == 'cve']
        all_identifiers = [ident.get('value', '') for ident in identifiers]
        
        vuln_info = {
            'name': vuln.get('name', 'N/A'),
            'severity': vuln.get('severity', 'N/A'),
            'description': vuln.get('description', 'N/A'),
            'solution': vuln.get('solution', 'N/A'),
            'package_name': package_info.get('name', 'N/A'),
            'package_version': dependency_info.get('version', 'N/A'),
            'cve': ', '.join(cve_list) if cve_list else 'N/A',
            'identifiers': ', '.join(all_identifiers) if all_identifiers else 'N/A',
            'id': vuln.get('id', 'N/A'),
        }
        vulnerabilities.append(vuln_info)
    
    return vulnerabilities


def export_to_csv(vulnerabilities, output_file='vulnerabilities.csv'):
    """Export vulnerabilities to CSV file with pipe delimiter."""
    if not vulnerabilities:
        print("No vulnerabilities to export.")
        return
    
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        fieldnames = [
            'name', 
            'severity', 
            'package_name', 
            'package_version',
            'cve',
            'description', 
            'solution', 
            'identifiers',
            'id'
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter='|')
        
        writer.writeheader()
        writer.writerows(vulnerabilities)
    
    print(f"✓ Successfully exported {len(vulnerabilities)} vulnerabilities to '{output_file}'")
    
    # Print summary
    print("\nSummary by Severity:")
    print("-" * 40)
    severity_count = {}
    for vuln in vulnerabilities:
        severity = vuln['severity']
        severity_count[severity] = severity_count.get(severity, 0) + 1
    
    for severity in ['Critical', 'High', 'Medium', 'Low', 'Unknown', 'Info']:
        count = severity_count.get(severity, 0)
        if count > 0:
            print(f"{severity:12s}: {count}")


def main():
    """Main function to parse and export GitLab vulnerability report to CSV."""
    
    # Check command line arguments
    if len(sys.argv) < 2:
        print("Usage: python gitlab_vuln_parser.py <vulnerability_json_file> [output_csv_file]")
        print("\nExample:")
        print("  python gitlab_vuln_parser.py gl-dependency-scanning-report.json")
        print("  python gitlab_vuln_parser.py gl-dependency-scanning-report.json vulnerabilities.csv")
        sys.exit(1)
    
    json_file = sys.argv[1]
    
    # Determine output CSV filename
    if len(sys.argv) >= 3:
        csv_file = sys.argv[2]
    else:
        # Auto-generate CSV filename from JSON filename
        json_path = Path(json_file)
        csv_file = json_path.stem + '_vulnerabilities.csv'
    
    # Parse the JSON file
    print(f"Parsing GitLab vulnerability report: {json_file}")
    vulnerabilities = parse_gitlab_vulnerabilities(json_file)
    
    # Export to CSV
    export_to_csv(vulnerabilities, csv_file)


if __name__ == '__main__':
    main()
