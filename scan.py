#!/usr/bin/env python3
"""
GitLab Dependency Scanning Vulnerability JSON Parser
Extracts HIGH severity vulnerabilities and categorizes by solution
Output: Pipe-delimited CSV with name, description, severity, solution
"""

import json
import csv
import sys
from pathlib import Path
from collections import defaultdict


def clean_text(text):
    """
    Clean text by removing newlines, extra spaces, and special characters.
    
    Args:
        text: Text to clean
        
    Returns:
        Cleaned text
    """
    if not text or text == 'N/A':
        return text
    
    # Replace newlines with spaces
    text = text.replace('\n', ' ').replace('\r', ' ')
    
    # Replace multiple spaces with single space
    text = ' '.join(text.split())
    
    # Remove pipe characters to avoid CSV delimiter conflicts
    text = text.replace('|', ' ')
    
    return text.strip()


def summarize_description(description, max_length=200):
    """
    Summarize description to a maximum length.
    
    Args:
        description: Full description text
        max_length: Maximum length for summary
        
    Returns:
        Summarized description
    """
    description = clean_text(description)
    
    if len(description) <= max_length:
        return description
    
    # Find the last sentence that fits
    sentences = description.split('. ')
    summary = ""
    
    for sentence in sentences:
        if len(summary) + len(sentence) + 2 <= max_length:
            summary += sentence + '. '
        else:
            break
    
    # If no complete sentence fits, just truncate
    if not summary:
        summary = description[:max_length-3] + '...'
    
    return summary.strip()


def parse_gitlab_vulnerabilities(json_file_path):
    """
    Parse GitLab dependency scanning JSON file and extract HIGH severity vulnerabilities.
    
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
    
    # Filter only HIGH severity vulnerabilities
    for vuln in vuln_list:
        severity = vuln.get('severity', '').upper()
        
        if severity == 'HIGH':
            raw_description = vuln.get('description', 'N/A')
            raw_solution = vuln.get('solution', 'N/A')
            
            vuln_info = {
                'name': clean_text(vuln.get('name', 'N/A')),
                'description': summarize_description(raw_description, max_length=250),
                'severity': vuln.get('severity', 'N/A'),
                'solution': clean_text(raw_solution),
            }
            vulnerabilities.append(vuln_info)
    
    return vulnerabilities


def categorize_by_solution(vulnerabilities):
    """
    Categorize vulnerabilities by their solution.
    
    Args:
        vulnerabilities: List of vulnerability dictionaries
        
    Returns:
        Dictionary with solutions as keys and lists of vulnerabilities as values
    """
    categorized = defaultdict(list)
    
    for vuln in vulnerabilities:
        solution = vuln['solution']
        categorized[solution].append(vuln)
    
    return categorized


def export_to_csv(vulnerabilities, output_file='high_severity_vulnerabilities.csv'):
    """Export HIGH severity vulnerabilities to pipe-delimited CSV file."""
    if not vulnerabilities:
        print("No HIGH severity vulnerabilities found to export.")
        return
    
    # Categorize by solution
    categorized = categorize_by_solution(vulnerabilities)
    
    print(f"\n✓ Found {len(vulnerabilities)} HIGH severity vulnerabilities")
    print(f"✓ Categorized into {len(categorized)} different solutions\n")
    
    # Print category summary
    print("Solution Categories:")
    print("-" * 80)
    for idx, (solution, vulns) in enumerate(categorized.items(), 1):
        solution_preview = solution[:60] + '...' if len(solution) > 60 else solution
        print(f"{idx}. {solution_preview} ({len(vulns)} vulnerabilities)")
    print()
    
    # Write to CSV with pipe delimiter and proper quoting
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        fieldnames = ['name', 'description', 'severity', 'solution']
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter='|', 
                               quoting=csv.QUOTE_MINIMAL, 
                               quotechar='"')
        
        writer.writeheader()
        
        # Write vulnerabilities grouped by solution
        for solution in sorted(categorized.keys()):
            for vuln in categorized[solution]:
                writer.writerow(vuln)
    
    print(f"✓ Successfully exported to '{output_file}' (pipe-delimited)")
    print(f"  Fields: name | description | severity | solution")
    print(f"  Note: Descriptions are summarized to ~250 characters max")


def export_categorized_csv(vulnerabilities, output_file='high_severity_by_solution.csv'):
    """Export vulnerabilities with solution category grouping."""
    if not vulnerabilities:
        print("No HIGH severity vulnerabilities found to export.")
        return
    
    categorized = categorize_by_solution(vulnerabilities)
    
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        fieldnames = ['solution_category', 'name', 'description', 'severity', 'solution']
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter='|',
                               quoting=csv.QUOTE_MINIMAL,
                               quotechar='"')
        
        writer.writeheader()
        
        # Write vulnerabilities grouped by solution with category marker
        for category_num, (solution, vulns) in enumerate(sorted(categorized.items()), 1):
            for vuln in vulns:
                row = vuln.copy()
                row['solution_category'] = f"Category_{category_num}"
                writer.writerow(row)
    
    print(f"✓ Also exported categorized version to '{output_file}'")
    print(f"  Fields: solution_category | name | description | severity | solution")


def main():
    """Main function to parse and export HIGH severity vulnerabilities to CSV."""
    
    # Check command line arguments
    if len(sys.argv) < 2:
        print("Usage: python gitlab_vuln_parser.py <vulnerability_json_file> [output_csv_file]")
        print("\nExample:")
        print("  python gitlab_vuln_parser.py gl-dependency-scanning-report.json")
        print("  python gitlab_vuln_parser.py gl-dependency-scanning-report.json high_vulns.csv")
        print("\nNote: Only HIGH severity vulnerabilities will be extracted")
        print("      Output will be pipe-delimited (|) CSV")
        sys.exit(1)
    
    json_file = sys.argv[1]
    
    # Determine output CSV filename
    if len(sys.argv) >= 3:
        csv_file = sys.argv[2]
    else:
        # Auto-generate CSV filename from JSON filename
        json_path = Path(json_file)
        csv_file = json_path.stem + '_high_severity.csv'
    
    # Parse the JSON file
    print(f"Parsing GitLab vulnerability report: {json_file}")
    print("Filtering: HIGH severity only")
    vulnerabilities = parse_gitlab_vulnerabilities(json_file)
    
    # Export to CSV
    export_to_csv(vulnerabilities, csv_file)
    
    # Also export categorized version
    categorized_file = csv_file.replace('.csv', '_categorized.csv')
    export_categorized_csv(vulnerabilities, categorized_file)
    
    print(f"\n✓ Done! Total HIGH severity vulnerabilities: {len(vulnerabilities)}")


if __name__ == '__main__':
    main()
