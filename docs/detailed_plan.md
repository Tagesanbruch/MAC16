# MAC16 Project - Detailed Implementation & Gap Analysis Plan

## 1. Gap Analysis Against Requirements

Based on `Plan.md` and current project status:

| Requirement | Status | Current Gaps & Analysis |
|:---:|:---:|---|
| **1. Functional Verification** | ❌ **FAIL** | Current TB runs but reports data mismatches (`Simulation Passed` not achieved). RTL logic needs debugging (likely carry/overflow or shift direction logic). |
| **2. PDK & Std Cells** | ✅ **PASS** | Using `icsprout55` PDK and standard cell library. |
| **3. PVT Evaluation** | ⚠️ **PARTIAL** | iEDA supports multi-corner timing via `iSTA`. We need to configure scripts to run 3 separate timing runs (TT, SS, FF) using respective `.lib` files. |
| **4. Synthesis Results** | ✅ **PASS** | `yosys` flow is working. Area is ~4900um^2 (passing). Power reporting needs to be enabled/parsed from iSTA. |
| **5. Formal Verification** | ⭕ **TODO** | Not yet set up. Need to determine if `yosys` `equiv_status` or specific LEC tool is available/required. |
| **6. P&R & Reports** | ⭕ **TODO** | P&R flow (Placement, CTS, Routing) is **completely missing**. Need to integrate `iPL`, `iCTS`, `iRT`. |
| **7. Physical Verification** | ⭕ **TODO** | DRC/LVS not run. `iDRC` is available. `iLVS` is not explicitly listed in API, might need alternative or manual check if tool unavailable. SPEF extraction needs to be set up. |
| **8. STA @ 1GHz (3 Corners)** | ❌ **FAIL** | setup slack is negative (-0.77ns) at TT/1GHz. Design runs at ~560MHz. **Critical**: Needs RTL pipelining to meet 1GHz. |
| **9. Total Area** | ✅ **PASS** | Current estimate ~4900um^2 is well within 8100um^2 limit. |
| **10. Bonus (Power/Freq)** | ⚠️ **RISK** | Power < 100uW is aggressive (current unmeasured). 1.5GHz is very unlikely without deep pipelining. |
| **11. Optimization** | ⭕ **TODO** | Multiplier tree optimization and pipelining are required to close timing. |

---

## 2. Detailed Execution Plan

### Phase 1: Functional Fixes (Day 1)
- **Objective**: Get `Simulation Passed` in functional simulation.
- **Tasks**:
    - Debug `mac16.sv` comparison failures (fix shift logic or accumulation adder).
    - Ensure `iverilog` compatibility (fix any remaining synthesis vs sim mismatches).
    - Verify all 3 modes (0, 1, Switch) pass in `tb_mac16.sv`.

### Phase 2: RTL Optimization (Day 1-2)
- **Objective**: Meet 1GHz Setup Timing.
- **Tasks**:
    - **Pipeline Multiplier**: Break 16x16 multiplication into 2 or 3 stages.
    - **Retiming**: Move registers to balance combinational logic depth.
    - **Re-Run Synthesis/STA**: Verify slack >= 0 at 1GHz (TT corner).

### Phase 3: Backend Flow Integration (Day 2-3)
- **Objective**: Complete P&R and Physical Verification.
- **Tasks**:
    - **Floorplan**: Create `def` with valid core area (100x100um die, 90x90um core).
    - **Placement (`iPL`)**: Integrate into Makefile/TCL flow.
    - **CTS (`iCTS`)**: Build clock tree.
    - **Routing (`iRT`)**: Route signals.
    - **Extraction**: Generate SPEF.

### Phase 4: Multi-Corner Signoff (Day 3)
- **Objective**: Verify design across all PVT corners.
- **Tasks**:
    - Create `scripts/run_corners.tcl` to iterate TT, SS, FF libraries.
    - Run STA with extracted SPEF for all corners.
    - Generate summary report.

### Phase 5: Documentation & Reporting (Day 4)
- **Objective**: Finalize deliverables.
- **Tasks**:
    - Generate Word/Markdown design report.
    - Archive design databases (GDS, Netlist, SPEF, Logs).

---

## 3. Immediate Next Steps
1.  Debug RTL to fix verification failures.
2.  Implement 3-stage pipeline for Multiplier to target 1GHz.
