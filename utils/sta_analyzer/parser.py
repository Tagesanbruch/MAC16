import re
import json
import logging
from pathlib import Path
from typing import List, Dict, Optional, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

class STAParser:
    def __init__(self, log_path: str):
        self.log_path = Path(log_path)
        self.base_dir = self.log_path.parent
        self.summary_data = []

    def parse(self) -> List[Dict[str, Any]]:
        """
        Main parsing entry point.
        1. Parses the textual log table to get path summaries.
        2. Links each row to its corresponding JSON detail file.
        """
        if not self.log_path.exists():
            raise FileNotFoundError(f"Log file not found: {self.log_path}")

        logger.info(f"Parsing STA log: {self.log_path}")
        
        with open(self.log_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Step 1: Find the summary table for Setup (Max) or Hold (Min)
        # We focus on "Report Timing (Max/Setup)" usually.
        # The log has sections. Let's look for the table under "Report Timing (Max/Setup)"
        # Or just find the table with headers "Endpoint", "Slack", etc.
        
        # Regex to find the table rows
        # Table format:
        # | Endpoint | Clock Group | Delay Type | Path Delay | Path Required | CPPR | Slack | Freq(MHz) |
        # | ...      | ...         | ...        | ...        | ...           | ...  | ...   | ...       |
        
        # We need to find the specific block where iSTA reports the path summaries.
        # Based on log analysis:
        # I0202 ... Sta.cc:1902] 
        # +----------------...+
        # | Endpoint ...
        
        lines = content.splitlines()
        in_table = False
        headers = []
        
        # We associate wires based on simple 1-based indexing as implied by the logs
        # wire_path_1.json, wire_path_2.json ...
        path_index = 1 
        
        for line in lines:
            if "+-------" in line:
                continue
            
            if "| Endpoint" in line and "| Slack" in line:
                in_table = True
                headers = [h.strip() for h in line.split('|') if h.strip()]
                continue
                
            if in_table:
                if not line.strip().startswith("|"):
                    in_table = False
                    continue
                
                # Parse Row
                parts = [p.strip() for p in line.split('|') if p.strip()]
                if len(parts) >= 8: # Ensure we have enough columns
                    row_data = {
                        "Endpoint": parts[0],
                        "Clock Group": parts[1],
                        "Delay Type": parts[2],
                        "Path Delay": parts[3],
                        "Path Required": parts[4],
                        "CPPR": parts[5],
                        "Slack": parts[6],
                        "Freq(MHz)": parts[7],
                        "id": path_index
                    }
                    
                    # Try to find corresponding JSON
                    # The log puts json in `dirname/wire_paths/wire_path_{id}.json`
                    # Note: log path is `.../sta_all.log`
                    # The textual report says: "output sta report path: .../mac16-1000MHz"
                    # And JSONs are at ".../mac16-1000MHz/wire_paths/"
                    # We might need to heuristics to find the wire_paths dir.
                    
                    # Heuristic: look in subdirectories of local dir for 'wire_paths'
                    # Or check matching log lines "output json file path: .../wire_path_N.json"
                    
                    # For now, let's look for `wire_paths` in the same directory structure as common in iEDA logs
                    # usually `syn/.../mac16-1000MHz/wire_paths`
                    # and `sta_all.log` is at `syn/.../sta_all.log`
                    
                    # Let's try to map it by finding the JSON file
                    json_path = self._find_json_for_id(path_index)
                    if json_path:
                         row_data['details'] = self.parse_path_json(json_path)
                    else:
                         row_data['details'] = None

                    self.summary_data.append(row_data)
                    path_index += 1
        
        logger.info(f"Parsed {len(self.summary_data)} timing paths.")
        return self.summary_data

    def _find_json_for_id(self, idx: int) -> Optional[Path]:
        """
        Attempts to find wire_path_{idx}.json by searching likely subdirectories.
        """
        filename = f"wire_path_{idx}.json"
        
        # Search strategy 1: Look for any 'wire_paths' dir under the log's parent directory recursively
        # This can be slow if the dir is huge, but usually it's shallow.
        matches = list(self.base_dir.rglob(f"wire_paths/{filename}"))
        if matches:
            return matches[0]
            
        return None

    def parse_path_json(self, json_path: Path) -> List[Dict[str, Any]]:
        """
        Parses the detail JSON file.
        Structure: List of dicts, each dict has one key like "node_0" or "inst_arc_0".
        We want to flatten this into a sequential list of steps.
        """
        try:
            with open(json_path, 'r') as f:
                data = json.load(f)
                
            steps = []
            current_step = {}
            
            # The JSON format is a bit odd: a list of singleton dicts.
            # Wrapper to iterate through them.
            for item in data:
                key = list(item.keys())[0]
                val = item[key]
                
                if key.startswith("node"):
                    # This is a pin/port
                    # Format: { "Point": "...", "Capacitance": ..., "slew": ..., "trans_type": ... }
                    # We treat this as the start or end of a segment
                    step_data = {
                        "type": "node",
                        "name": val.get("Point", "Unknown"),
                        "cap": val.get("Capacitance", 0),
                        "slew": val.get("slew", 0),
                        "edge": val.get("trans_type", "")
                    }
                    steps.append(step_data)
                    
                elif key.startswith("inst_arc"):
                    # This is the delay arc through a cell or net
                    # Format: { "Incr": 0.123 }
                    step_data = {
                        "type": "arc",
                        "delay": val.get("Incr", 0)
                    }
                    steps.append(step_data)
            
            return steps
            
        except Exception as e:
            logger.error(f"Failed to parse JSON {json_path}: {e}")
            return []
