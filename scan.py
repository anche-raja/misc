#!/usr/bin/env python3
"""
GitLab Dependency Scanning Vulnerability JSON Parser
Extracts name, description, solution, and severity from GitLab vulnerability reports
"""

import json
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
        vuln_info = {
            'name': vuln.get('name', 'N/A'),
            'description': vuln.get('description', 'N/A'),
            'solution': vuln.get('solution', 'N/A'),
            'severity': vuln.get('severity', 'N/A'),
            # Additional useful fields
            'id': vuln.get('id', 'N/A'),
            'location': vuln.get('location', {}).get('dependency', {}).get('package', {}).get('name', 'N/A'),
            'identifiers': [ident.get('value', 'N/A') for ident in vuln.get('identifiers', [])],
        }
        vulnerabilities.append(vuln_info)
    
    return vulnerabilities


def print_vulnerabilities(vulnerabilities):
    """Print vulnerabilities in a readable format."""
    if not vulnerabilities:
        print("No vulnerabilities to display.")
        return
    
    print(f"\n{'='*80}")
    print(f"Found {len(vulnerabilities)} vulnerabilities")
    print(f"{'='*80}\n")
    
    for idx, vuln in enumerate(vulnerabilities, 1):
        print(f"Vulnerability #{idx}")
        print(f"{'-'*80}")
        print(f"Name:        {vuln['name']}")
        print(f"Severity:    {vuln['severity']}")
        print(f"Package:     {vuln['location']}")
        print(f"ID:          {vuln['id']}")
        print(f"Identifiers: {', '.join(vuln['identifiers'])}")
        print(f"\nDescription:\n{vuln['description']}")
        print(f"\nSolution:\n{vuln['solution']}")
        print(f"{'='*80}\n")


def export_to_csv(vulnerabilities, output_file='vulnerabilities.csv'):
    """Export vulnerabilities to CSV file."""
    import csv
    
    if not vulnerabilities:
        print("No vulnerabilities to export.")
        return
    
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        fieldnames = ['name', 'severity', 'description', 'solution', 'location', 'id', 'identifiers']
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        
        writer.writeheader()
        for vuln in vulnerabilities:
            # Convert identifiers list to string for CSV
            vuln_copy = vuln.copy()
            vuln_copy['identifiers'] = ', '.join(vuln['identifiers'])
            writer.writerow(vuln_copy)
    
    print(f"✓ Exported {len(vulnerabilities)} vulnerabilities to '{output_file}'")


def export_to_json(vulnerabilities, output_file='vulnerabilities_summary.json'):
    """Export vulnerabilities to a simplified JSON file."""
    if not vulnerabilities:
        print("No vulnerabilities to export.")
        return
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(vulnerabilities, f, indent=2, ensure_ascii=False)
    
    print(f"✓ Exported {len(vulnerabilities)} vulnerabilities to '{output_file}'")


def filter_by_severity(vulnerabilities, severity_levels):
    """
    Filter vulnerabilities by severity level.
    
    Args:
        vulnerabilities: List of vulnerability dictionaries
        severity_levels: List of severity levels to include (e.g., ['Critical', 'High'])
        
    Returns:
        Filtered list of vulnerabilities
    """
    return [v for v in vulnerabilities if v['severity'] in severity_levels]


def main():
    """Main function to parse and display GitLab vulnerability report."""
    
    # Check command line arguments
    if len(sys.argv) < 2:
        print("Usage: python gitlab_vuln_parser.py <vulnerability_json_file> [options]")
        print("\nOptions:")
        print("  --csv <filename>      Export to CSV file")
        print("  --json <filename>     Export to JSON file")
        print("  --severity <levels>   Filter by severity (comma-separated: Critical,High,Medium,Low)")
        print("\nExample:")
        print("  python gitlab_vuln_parser.py gl-dependency-scanning-report.json")
        print("  python gitlab_vuln_parser.py gl-dependency-scanning-report.json --csv output.csv")
        print("  python gitlab_vuln_parser.py gl-dependency-scanning-report.json --severity Critical,High")
        sys.exit(1)
    
    json_file = sys.argv[1]
    
    # Parse the JSON file
    print(f"Parsing GitLab vulnerability report: {json_file}")
    vulnerabilities = parse_gitlab_vulnerabilities(json_file)
    
    # Process command line options
    csv_output = None
    json_output = None
    severity_filter = None
    
    i = 2
    while i < len(sys.argv):
        if sys.argv[i] == '--csv' and i + 1 < len(sys.argv):
            csv_output = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == '--json' and i + 1 < len(sys.argv):
            json_output = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == '--severity' and i + 1 < len(sys.argv):
            severity_filter = [s.strip() for s in sys.argv[i + 1].split(',')]
            i += 2
        else:
            i += 1
    
    # Apply severity filter if specified
    if severity_filter:
        original_count = len(vulnerabilities)
        vulnerabilities = filter_by_severity(vulnerabilities, severity_filter)
        print(f"Filtered to {len(vulnerabilities)} vulnerabilities (from {original_count}) with severity: {', '.join(severity_filter)}")
    
    # Display vulnerabilities
    print_vulnerabilities(vulnerabilities)
    
    # Export if requested
    if csv_output:
        export_to_csv(vulnerabilities, csv_output)
    
    if json_output:
        export_to_json(vulnerabilities, json_output)
    
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


if __name__ == '__main__':
    main()
