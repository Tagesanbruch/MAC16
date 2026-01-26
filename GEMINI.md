# GEMINI.md

This file provides analysis and a go-forward plan for the Gemini CLI agent.

## 1. Project Overview

MAC16 is a 16-bit serial I/O Multiply-Accumulate (MAC) chip design for the `icsprout55` 55nm PDK. The primary goal is achieving a 1GHz clock frequency while meeting specific Power, Performance, and Area (PPA) targets.

**Key Design Constraints:**
- **Frequency:** 1GHz (1.5GHz for bonus)
- **PVT Corners:** TT (1.2V/27°C), SS (1.08V/125°C), FF (1.32V/-40°C)
- **Power (Total):** ≤ 300 µW (≤ 100 µW for bonus)
- **Area:** ≤ 90µm × 90µm
- **Verification:** Must pass formal, LVS, and multi-corner STA with extracted parasitics.

## 2. Current Status Analysis (As of 2026-01-26)

Based on `docs/2026-01-26-plan-metrics-summary.md` and a review of the existing scripts, the project status is as follows:

- **RTL Design & Synthesis:** Several architectural experiments have been conducted.
  - ✅ **`exp_d`** meets the 1GHz timing target at the typical (TT) corner (WNS: +0.032ns).
  - ⚠️ **`exp_f`** is very close to meeting the 1GHz target (WNS: -0.005ns) and may be a good candidate for further physical optimization.
- **Verification Gap:** The primary blocker is the incomplete physical design and verification flow. The `plan-metrics-summary.md` report clearly indicates that items **4, 5, 6, 7, and 8** are all "Not Done".
- **P&R Script (`ieda_flow.tcl`):** The current script is a skeleton that successfully runs placement and routing but **lacks critical sign-off stages**:
  - **No Power Delivery Network (PDN):** The design has no power grid.
  - **No Clock Tree Synthesis (CTS):** The clock is ideal, not a real, routed clock tree.
  - **No Parasitic Extraction (SPEF):** Post-layout STA cannot be performed accurately.
  - **No Physical Verification:** DRC/LVS checks are not integrated.
- **Power Consumption:** Current pre-layout power estimates (~5-8 mW) are significantly higher than the target (<300 µW). As requested, further power optimization is on hold.

**Conclusion:** RTL exploration has yielded viable candidates. The immediate and sole focus should now be on building a robust, sign-off quality verification flow.

## 3. Verification Flow Completion Plan

The following plan details the steps required to complete the "4/5/6/7/8 verification" stages using the iEDA toolchain. We will use the **`exp_d` design** as the primary vehicle for bringing up this flow, as it already meets timing at the TT corner.

### Step 1: Implement Power Delivery Network (PDN)

**Goal:** Add a power grid to the design. This is essential for LVS and power analysis.
**Action:** Modify `scripts/ieda_flow.tcl`. Insert the following commands after `init_floorplan` and before `run_placer`.

**Note:** Cell names like `FILLTIE_H7CL` must be verified from the LEF files (`IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/lef/`).

```tcl
# --- Add to ieda_flow.tcl after init_floorplan ---
puts "\n--- Power Network Planning (PDN) ---"

# 1. Insert Tap Cells for substrate connection
tapcell -tapcell "FILLTIE_H7CL" -distance 60

# 2. Define global power/ground connections
global_net_connect -net_name VDD -instance_pin_name VDD -is_power 1
global_net_connect -net_name VSS -instance_pin_name VSS -is_power 0

# 3. Create Power Stripes (M5 vertical, M4 horizontal)
create_stripe -layer_name "MET5" -net_name_power VDD -net_name_ground VSS -width 2.0 -pitch 40.0 -offset 10.0
create_stripe -layer_name "MET4" -net_name_power VDD -net_name_ground VSS -width 2.0 -pitch 40.0 -offset 10.0

# 4. Connect power layers
connect_two_layer -layers "MET4 MET5"
connect_two_layer -layers "MET1 MET4"

puts "PDN Completed."
# --- End of section ---
```

### Step 2: Enable Clock Tree Synthesis (CTS) & Parasitic Extraction (SPEF)

**Goal:** Build a real clock tree and extract post-layout parasitic data for accurate STA.
**Action:** Modify `scripts/ieda_flow.tcl`.

1.  **Enable CTS:** Uncomment or add the `run_cts` command after placement.
2.  **Export SPEF:** Add the `write_spef` command at the end of the script.

```tcl
# --- In ieda_flow.tcl ---

# After run_placer
puts "\n--- CTS ---"
run_cts

# After write_verilog
set OUT_SPEF "${RESULT_DIR}/${DESIGN}.spef"
write_spef $OUT_SPEF
```

### Step 3: Update STA for Post-Layout Analysis

**Goal:** Make the STA script use the extracted parasitics (SPEF) for timing analysis.
**Action:** Modify `scripts/sta_multicorner.tcl` to read the SPEF file.

```tcl
# --- In sta_multicorner.tcl, inside run_sta proc ---

# After link_design
set spef_path [string map {".v" ".spef"} $NETLIST]
if {[file exists $spef_path]} {
    puts "Info: Reading SPEF file for post-layout STA: $spef_path"
    readSpef $spef_path
    buildRCTree $spef_path 0
} else {
    puts "Warning: SPEF file not found. Running pre-layout STA."
}
# Before read_sdc
```

### Step 4: Integrate Physical & Formal Verification

**Goal:** Add DRC, LVS, and Formal checks to the main flow.
**Action:** Add targets to the `Makefile`.

1.  **DRC:** Add a `run_drc` command at the end of `ieda_flow.tcl`.
2.  **LVS:** This typically requires exporting a GDSII file (`write_gds` in iEDA) and using a tool like KLayout or Calibre. We will create a placeholder target.
3.  **Formal:** The `make equiv` target already exists and should be run after synthesis.

---
## 4. Actionable Checklist

- [ ] **1. Update `ieda_flow.tcl`:**
  - [ ] Add the PDN generation code block.
  - [ ] Add `run_cts` after the placement step.
  - [ ] Add `write_spef` and `write_gds` to the output section.
  - [ ] Add `run_drc` at the end of the flow.
- [ ] **2. Update `sta_multicorner.tcl`:**
  - [ ] Add the logic to read the generated SPEF file.
- [ ] **3. Run Full Flow on `exp_d`:**
  - [ ] Execute `make pr` using the `exp_d` netlist.
  - [ ] Debug any errors in the P&R flow (log file: `syn/yosys-syn-exp_d-*/pr/ieda_pr.log`).
- [ ] **4. Run Post-Layout STA:**
  - [ ] Execute `make sta` on the post-layout netlist (`.../pr/mac16_pr.v`).
  - [ ] Analyze the timing report. Check if timing is still met after adding CTS and parasitics.
- [ ] **5. Run Physical Verification:**
  - [ ] Check the DRC report for violations.
  - [ ] Develop and run an LVS flow (e.g., using exported GDS and Netlist with KLayout).
- [ ] **6. Run Multi-Corner STA:**
  - [ ] Once the flow is stable for the TT corner, run it for SS and FF corners to complete the sign-off.
