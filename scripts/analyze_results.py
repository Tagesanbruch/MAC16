import os
import re
import argparse
import sys

def parse_sim_log(log_path):
    if not os.path.exists(log_path):
        return "Not Run", False
    
    with open(log_path, 'r') as f:
        content = f.read()
    
    if "Simulation Passed" in content:
        return "Passed", True
    else:
        return "Failed", False

def parse_area_report(syn_dir, design, freq):
    report_path = f"{syn_dir}/{design}-{freq}MHz/hierarchical_area.rpt"
    if not os.path.exists(report_path):
        return "N/A", False
    
    area = 0.0
    with open(report_path, 'r') as f:
        for line in f:
            if f"Chip area for module '{design}'" in line: # Adjust based on actual report format
                match = re.search(r"Chip area for module .*:\s+([\d\.]+)", line)
                if match:
                    area = float(match.group(1))
            # Fallback for different yosys versions or format
            if f"Chip area for module '\\{design}'" in line:
                 match = re.search(r"Chip area for module .*:\s+([\d\.]+)", line)
                 if match:
                    area = float(match.group(1))

    # Requirement 90um * 90um = 8100
    passing = area <= 8100
    return f"{area:.2f}", passing

def parse_timing_report(syn_dir, design, freq):
    # This is simplified; assumes we only have one main timing report or log
    # In reality, iEDA/OpenSTA logs might be scattered or named differently per corner
    # For now, we look at the main STA log or report
    
    report_path = f"{syn_dir}/{design}-{freq}MHz/{design}.rpt"
    log_path = f"{syn_dir}/{design}-{freq}MHz/sta.log"
    
    slack = -999.0
    found = False
    
    # Try reading formatted report first
    if os.path.exists(report_path):
        with open(report_path, 'r') as f:
            content = f.read()
            # Look for "slack (VIOLATED)" or "slack (MET)"
            # Example: | slack (VIOLATED) | -0.774 |
            match = re.search(r"\|\s*slack\s*\((VIOLATED|MET)\)\s*\|\s*([-\d\.]+)", content)
            if match:
                slack = float(match.group(2))
                found = True
    
    return slack, (slack >= 0)

def generate_report(sim_status, area_val, area_pass, slack_val, slack_pass, output_file):
    with open(output_file, 'w') as f:
        f.write("# Gap Analysis Report\n\n")
        f.write("| Requirement | Current Status | Detailed Value | Pass/Fail |\n")
        f.write("|---|---|---|---|\n")
        f.write(f"| 1. Functional Verification | {sim_status} | N/A | {'✅' if sim_status=='Passed' else '❌'} |\n")
        f.write(f"| 8. Setup Timing @ 1GHz | {'Evaluated' if slack_pass else 'Violated'} | {slack_val} ns | {'✅' if slack_pass else '❌'} |\n")
        f.write(f"| 9. Area <= 8100 um^2 | {'Met' if area_val != 'N/A' and area_pass else 'Exceeded'} | {area_val} | {'✅' if area_pass else '❌'} |\n")
        f.write("\n## Pending Items (Manual Analysis)\n")
        f.write("- [ ] 3 PVT Corners (Need to confirm iEDA support)\n")
        f.write("- [ ] Power < 300uW (Need power report)\n")
        f.write("- [ ] Physical Verification (LVS/SPEF)\n")
        f.write("- [ ] P&R (Not yet integrated)\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sim_log", required=True)
    parser.add_argument("--syn_dir", required=True)
    parser.add_argument("--design", required=True)
    parser.add_argument("--freq", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    sim_status, sim_pass = parse_sim_log(args.sim_log)
    area_val, area_pass = parse_area_report(args.syn_dir, args.design, args.freq)
    slack_val, slack_pass = parse_timing_report(args.syn_dir, args.design, args.freq)

    generate_report(sim_status, area_val, area_pass, slack_val, slack_pass, args.output)
    print(f"Report generated: {args.output}")
