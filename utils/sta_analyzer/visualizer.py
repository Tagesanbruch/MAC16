import os
from pathlib import Path
from typing import List, Dict, Any
from jinja2 import Template

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>STA Timing Analysis Report</title>
    <style>
        :root {
            --bg-color: #0d1117;
            --text-color: #c9d1d9;
            --border-color: #30363d;
            --accent-color: #58a6ff;
            --success-color: #238636;
            --danger-color: #da3633;
            --warning-color: #d29922;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-color);
            margin: 0;
            padding: 20px;
        }
        h1, h2, h3 { color: var(--text-color); }
        a { color: var(--accent-color); text-decoration: none; }
        
        .container { max-width: 1200px; margin: 0 auto; }
        
        /* Summary Table */
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
            font-size: 14px;
        }
        th, td {
            text-align: left;
            padding: 8px 12px;
            border-bottom: 1px solid var(--border-color);
        }
        th { font-weight: 600; color: var(--accent-color); }
        tr:hover { background-color: #161b22; cursor: pointer; }
        
        .slack-pass { color: var(--success-color); font-weight: bold; }
        .slack-fail { color: var(--danger-color); font-weight: bold; }
        
        /* Detail View */
        .path-detail {
            display: none; /* Hidden by default */
            background-color: #161b22;
            padding: 15px;
            border: 1px solid var(--border-color);
            border-radius: 6px;
            margin-top: 10px;
            margin-bottom: 20px;
        }
        .path-detail.active { display: block; }
        
        /* Waterfall / Bar Chart */
        .timeline {
            position: relative;
            margin-top: 20px;
            padding-top: 20px;
        }
        .step {
            display: flex;
            align-items: center;
            margin-bottom: 4px;
            font-size: 12px;
            font-family: monospace;
        }
        .step-label {
            width: 350px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            padding-right: 10px;
            text-align: right;
            color: #8b949e;
        }
        .step-bar-container {
            flex-grow: 1;
            background-color: #21262d;
            height: 18px;
            position: relative;
            border-radius: 2px;
        }
        .step-bar {
            height: 100%;
            background-color: var(--accent-color);
            position: absolute;
            border-radius: 2px;
            min-width: 2px;
        }
        .step-bar.net { background-color: #7ee787; opacity: 0.7; }
        .step-bar.cell { background-color: #79c0ff; }
        
        .step-value {
            margin-left: 10px;
            width: 60px;
            text-align: right;
        }
        .legend {
            display: flex;
            gap: 15px;
            margin-bottom: 10px;
            font-size: 12px;
        }
        .legend-item { display: flex; align-items: center; }
        .legend-color { width: 12px; height: 12px; margin-right: 5px; border-radius: 2px; }
    </style>
    <script>
        function toggleDetail(id) {
            const detail = document.getElementById('detail-' + id);
            if (detail.style.display === 'block') {
                detail.style.display = 'none';
            } else {
                detail.style.display = 'block';
            }
        }
    </script>
</head>
<body>
    <div class="container">
        <h1>STA Timing Analysis Report</h1>
        <p>Generated from: {{ log_path }}</p>
        
        <h2>Critical Paths Summary</h2>
        <p>Click on a row to toggle detailed breakdown.</p>
        
        <table>
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Endpoint</th>
                    <th>Slack (ns)</th>
                    <th>Delay (ns)</th>
                    <th>Required (ns)</th>
                    <th>Freq (MHz)</th>
                </tr>
            </thead>
            <tbody>
                {% for path in paths %}
                <tr onclick="toggleDetail({{ path.id }})">
                    <td>#{{ path.id }}</td>
                    <td>{{ path.Endpoint }}</td>
                    <td class="{{ 'slack-pass' if path.Slack|float >= 0 else 'slack-fail' }}">
                        {{ path.Slack }}
                    </td>
                    <td>{{ path['Path Delay'] }}</td>
                    <td>{{ path['Path Required'] }}</td>
                    <td>{{ path['Freq(MHz)'] }}</td>
                </tr>
                <tr id="row-detail-{{ path.id }}" style="border-bottom: none;">
                    <td colspan="6" style="padding: 0; border: none;">
                        <div id="detail-{{ path.id }}" class="path-detail">
                            <h3>Path #{{ path.id }} Details</h3>
                            
                            {% if path.details %}
                            <div class="legend">
                                <div class="legend-item">
                                    <div class="legend-color" style="background-color: #79c0ff;"></div> Cell Delay
                                </div>
                                <div class="legend-item">
                                    <div class="legend-color" style="background-color: #7ee787;"></div> Net Delay
                                </div>
                            </div>
                            
                            <div class="timeline">
                                {% set total_delay = path['Path Delay']|float %}
                                {% set current_time = 0.0 %}
                                
                                {% for step in path.processed_steps %}
                                <div class="step">
                                    <div class="step-label" title="{{ step.name }}">
                                        {{ step.name }}
                                        <div style="font-size: 10px; color: #666;">{{ step.type }}</div>
                                    </div>
                                    
                                    <div class="step-bar-container">
                                        <!-- Visualization logic: left offset based on cumulative time, width based on delay -->
                                        {% set width_pct = (step.delay / total_delay * 100) if total_delay > 0 else 0 %}
                                        {% set left_pct = (step.start_time / total_delay * 100) if total_delay > 0 else 0 %}
                                        
                                        <div class="step-bar {{ 'cell' if step.is_cell else 'net' }}" 
                                             style="left: {{ left_pct }}%; width: {{ width_pct }}%;">
                                        </div>
                                    </div>
                                    
                                    <div class="step-value">
                                        {{ "%.4f"|format(step.delay) }} ns
                                    </div>
                                </div>
                                {% endfor %}
                            </div>
                            {% else %}
                            <p>No detailed JSON path data found.</p>
                            {% endif %}
                        </div>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</body>
</html>
"""

class STAVisualizer:
    def __init__(self, output_dir: str):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
    
    def process_details_for_viz(self, paths: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Pre-process the raw steps into a format suitable for the waterfall chart.
        We need to calculate cumulative times (start_time) for each step.
        """
        for path in paths:
            if not path.get('details'):
                 continue
                 
            raw_steps = path['details']
            processed_steps = []
            
            # Reconstruct the flow:
            # The raw list is mixed: node, arc, node, arc...
            # We want to show the Arcs (Delays) visually, and label them with the Node they drive or come from.
            
            current_time = 0.0
            
            # Iterate through the sequence
            # Pattern: Node -> Arc -> Node (The arc is the delay between nodes)
            # We visualize the Arc.
            
            for i in range(len(raw_steps)):
                item = raw_steps[i]
                
                if item['type'] == 'arc':
                    # Look back for "From" node (optional) or current is enough
                    prev_node = raw_steps[i-1] if i > 0 and raw_steps[i-1]['type'] == 'node' else None
                    
                    delay = float(item['delay'])
                    
                    # Heuristic to determine if Net or Cell
                    # Usually "Incr" doesn't say. 
                    # But the previous Node might give a hint.
                    # If prev node name ends in ":CK" or ":D" or ":A", and next is ":Q" or ":Y", it's a Cell.
                    # If prev node is output pin and next is input pin, it's a Net.
                    
                    is_cell = True # Default
                    name = "Delay"
                    
                    if prev_node:
                        name = prev_node['name']
                        # Simple heuristic: if name contains "wire" or is connecting two different instances, it's a net?
                        # Actually, raw JSON doesn't say explicit types.
                        # Let's assume based on iEDA typical behavior:
                        # Arc follows a Node.
                        pass
                        
                    processed_steps.append({
                        "name": name,
                        "type": "Delay",
                        "start_time": current_time,
                        "delay": delay,
                        "is_cell": True # TODO: refine detection
                    })
                    
                    current_time += delay
                    
            path['processed_steps'] = processed_steps
            
        return paths

    def generate_report(self, data: List[Dict[str, Any]], log_source: str):
        # Preprocess data
        data = self.process_details_for_viz(data)
        
        template = Template(HTML_TEMPLATE)
        html_content = template.render(paths=data, log_path=log_source)
        
        output_file = self.output_dir / "timing_report.html"
        with open(output_file, "w", encoding='utf-8') as f:
            f.write(html_content)
            
        print(f"Report generated: {output_file}")
