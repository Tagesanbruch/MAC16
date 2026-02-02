import argparse
import sys
from pathlib import Path
from rich.console import Console
from rich.table import Table

from parser import STAParser
from visualizer import STAVisualizer

def main():
    parser = argparse.ArgumentParser(description="STA Analyzer & Visualizer")
    parser.add_argument("--log", required=True, help="Path to sta_all.log")
    parser.add_argument("--name", help="Name of the analysis (creates a subfolder in output/)")
    parser.add_argument("--output", help="Custom output directory (overrides default output folder)")
    args = parser.parse_args()
    
    # Determine default output directory relative to this script
    script_dir = Path(__file__).resolve().parent
    base_output_dir = script_dir / "output"
    
    if args.output:
        # User specified full custom path
        output_dir = Path(args.output)
    else:
        # Use default output dir, optionally with a subfolder if --name is provided
        if args.name:
            output_dir = base_output_dir / args.name
        else:
            output_dir = base_output_dir
        
    output_dir.mkdir(parents=True, exist_ok=True)
    
    console = Console()
    
    # 1. Parse
    try:
        parser_tool = STAParser(args.log)
        data = parser_tool.parse()
    except Exception as e:
        console.print(f"[bold red]Error parsing log:[/bold red] {e}")
        import traceback
        console.print(traceback.format_exc())
        sys.exit(1)
        
    if not data:
        console.print("[yellow]No timing paths found in log.[/yellow]")
        sys.exit(0)

    # 2. Terminal Summary
    table = Table(title=f"Timing Summary (Top {len(data)})")
    table.add_column("ID", justify="right", style="cyan", no_wrap=True)
    table.add_column("Endpoint", style="white")
    table.add_column("Slack (ns)", justify="right")
    table.add_column("Freq (MHz)", justify="right")
    table.add_column("Details", justify="center")
    
    for path in data:
        slack = float(path['Slack'])
        slack_style = "green" if slack >= 0 else "red"
        has_details = "Yes" if path.get('details') else "No"
        
        table.add_row(
            str(path['id']), 
            path['Endpoint'], 
            f"[{slack_style}]{path['Slack']}[/{slack_style}]", 
            path['Freq(MHz)'],
            has_details
        )
        
    console.print(table)
    
    # 3. Export JSON
    json_output_path = output_dir / "timing_data.json"
    try:
        import json
        with open(json_output_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2)
        console.print(f"[blue]JSON data saved to:[/blue] {json_output_path}")
    except Exception as e:
        console.print(f"[bold red]Error saving JSON:[/bold red] {e}")

    # 4. Generate HTML
    viz = STAVisualizer(str(output_dir))
    viz.generate_report(data, args.log)
    
    console.print(f"[bold green]Success![/bold green] Open {output_dir}/timing_report.html to view details.")

if __name__ == "__main__":
    main()
