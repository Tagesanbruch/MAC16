Below is a focused, design‑oriented summary based strictly on the retrieved literature, with emphasis on what is realistically actionable for your 16‑bit MAC in 55 nm at ~1 GHz SS. I’ll organize by your four topics, and within each give: (1) key papers/results; (2) what they imply for your design; and (3) concrete architectural/physical techniques you can adopt.

---

## 1. High‑Speed Accumulator Architectures (Breaking the Loop)

### 1.1 Keeping the Accumulator in Redundant / Carry‑Save Form

**Redundant‑binary and double carry‑save MACs**

1. **A High-Speed, Energy-Efficient Two-Cycle Multiply-Accumulate (MAC) Architecture and Its Application to a Double-Throughput MAC Unit** – 2010, IEEE TCAS‑I [65 nm]  
   - **Node**: 65 nm, 1.1 V standard‑cell library.  
   - **Key idea**: First cycle does *only* partial‑product (PP) generation and reduction in a CSA tree; second cycle performs final accumulation and all other logic using a special sign‑extension scheme so that the “accumulator + CPA” is not in the first cycle’s critical path [1].  
   - The first pipeline stage: PP generation + reduction tree (carry‑save).  
   - The second stage: sign‑extension, carry‑propagate adder (CPA), saturation, etc.  
   - Reported: 31 % speed improvement and 32 % energy/operation reduction vs a reference two‑cycle MAC where a multiplier feeds a separate accumulator adder [1].

2. **A MAC unit with double carry-save scheme suitable for 6-input LUT based reconfigurable systems** – 2015, IEEE ICECS [FPGA]  
   **and**  
   **A high performance multiply-accumulate unit with double carry-save scheme for 6-input LUT based reconfigurable systems** – 2015, ELECO [FPGA]  
   - **Node**: LUT‑based FPGAs (Stratix III; not an ASIC node) [2][3].  
   - **Key idea**: Use *double carry‑save* encoding for the accumulate result – output is kept as two (actually three in some works) redundant vectors, never merged to binary each cycle. Only when needed (e.g., final readout) is a binary CPA used.  
   - They employ only (6,3) counters in PP reduction and accumulate, minimizing logic depth and **entirely avoiding carry propagation** in the MAC loop.  
   - Though FPGA‑oriented, the underlying principle (accumulator state as (Sum, Carry) vectors, not binary) is technology‑agnostic.

3. **A high-performance CMOS redundant binary multiplication-and-accumulation (MAC) unit** – 1994, IEEE TCAS‑I [0.8 µm]  
   - **Node**: 0.8 µm two‑metal CMOS [4].  
   - **Key idea**: Use a redundant‑binary representation tied to modified Booth recoding so that the PP reduction and accumulation are all in redundant form; only a final “vector merging adder” (CPA) converts to binary.  
   - Even in 0.8 µm they exceed 200 MHz by balancing pipeline stages and removing carry chains from the MAC loop.

**Implications for your design**

- A **single‑cycle MAC with binary accumulator** is fundamentally disadvantaged versus “fused” or redundant MACs. Every cycle you pay a CPA delay; at SS that becomes lethal.
- Architectures [1][2][3][4] show that **defering the final CPA until the last cycle** is standard practice:
  - Keep the running sum in *carry‑save or redundant* format (two or more vectors).
  - Each MAC cycle:  
    `CSA_Reduction(Acc_sum, Acc_carry, Product)` → new (sum, carry).  
  - Only when you must read out (end of dot product / filter window) do you apply a single fast CPA (e.g., Kogge–Stone / Han‑Carlson / carry‑select).

**Actionable architecture change**

For a 16‑bit 55 nm MAC:

- Replace `Accumulator = Accumulator + Product` (binary) with:
  - A **fused CSA tree** whose inputs each cycle are:
    - Partial products of current 16×16 Booth‑encoded multiplier
    - The previous cycle’s accumulator **sum** and **carry** vectors
  - The tree outputs updated accumulator sum/carry. No CPA in this stage.
- Add a **single “vector‑merging adder” (VMA)**:
  - A parallel‑prefix CPA that merges the two vectors into a final 32‑bit (or wider) result.
  - This VMA is only clock‑enabled when “read_out_valid” is true, not every cycle.
- Pipeline boundary:
  - Stage N‑1: Last compressor layer → registers for (Acc_sum, Acc_carry)  
  - Final stage: VMA → output register.
- This both reduces the per‑cycle combinational depth and eliminates frequent CPA toggling → helping both **frequency** and **dynamic power**.

### 1.2 “Vector Merging Adder” (VMA) Choices

The VMA is well‑discussed in multiplier literature:

- Generic sources on “vector merging adder” note that it’s simply the final CPA that merges CSA outputs [5].  
- For highest speed at 1 GHz in 55 nm:
  - Use a **parallel‑prefix adder** (Kogge–Stone, Sklansky, Han–Carlson) or a well‑tuned **square‑root carry‑select adder** as in recent VMA optimizations [6].
  - Place it in a **separate, late pipeline stage** with short combinational depth and heavy buffering/upsizing as needed.

---

## 2. Deep Pipelining & Retiming for Multipliers

### 2.1 What frequency is realistic and what depth per stage?

Direct 55 nm MACs at 1 GHz SS are rare in the open literature, but we can infer from:

- **Two-cycle MAC in 65 nm** [1]:  
  - Full 16–64‑bit MAC in **two stages** reaches high clock rates at 65 nm, 1.1 V. Their “first stage” PP+CSA tree is roughly one deep combinational chunk.
- **Wave‑pipelined multipliers** (180 nm/0.35 µm) reach multi‑GHz with no register between internal levels, but require extremely tight delay balancing and are not robust to PVT, especially at old nodes [7][8]. For your 1.84× TT→SS factor, wave pipelining is *not* advisable.

Empirical rule from digital design practice in 65 nm–40 nm for ~1 GHz:

- Full‑custom or high‑end CPU datapaths typically target **10–12 FO4** per pipeline stage at worst, often less in SS.
- A CSA compressor layer (3:2 or 4:2) is only a few gate delays; routing and fanout dominate.

**Practical target for your 55 nm SS=1 GHz goal**

- Assume TT must reach ≈1.8 GHz (0.56 ns). SS is ~1.84× slower → you want **≤0.56 ns @ TT** per stage.  
- In 55 nm, one FO4 delay is on the order of ~25–35 ps at nominal Vdd (roughly; depends heavily on your library).  
  - 0.56 ns / 30 ps ≈ 18 FO4 at TT.  
  - With SS slowdown, you must keep **effective SS depth ~10 FO4** or better.
- Conclusion: design each **MAC pipeline stage** to be:
  - ≈ 10 FO4 or less at SS → maybe 12–14 FO4 at TT.

### 2.2 How to slice a Booth+Wallace/column‑compression tree into 6–8 stages

From column‑compression and pipelined multiplier work:

- **Column Compression Pipelined Multipliers** [9] show the natural structuring:
  - PP generation (Booth encoder + PP gens).
  - Multiple layers of CSA (3:2, 4:2 compressors).
  - Final VMA (CPA).
  - They insert registers **between CSA layers** to reduce logic depth.
- **Fine‑grain pipelining** in Wallace tree multipliers (FPGA and async variants) effectively breaks the tree every 1–2 compressor levels [10].  
- **Two‑dimensional pipeline gating** for array multipliers [11] also relies on separating horizontal and vertical pipeline stages.

For a 16×16 Booth+Wallace in 55 nm:

- Partial-products: 8 Booth rows (radix‑4) or 5–6 rows (radix‑8), each 16–17 bits.
- A typical compression schedule to 2 rows needs ~3–4 compressor “levels”.

**Concrete slicing strategy (6–8 stages total)**

Assume you want 6–7 stages from inputs to CSA accumulator:

1. **Stage 0** (optional, if input timing is loose):  
   - Register A, B.
2. **Stage 1**:  
   - Booth encoding (radix‑4 or radix‑8) + PP generation.  
   - Target 2–3 FO4 for encoder + ANDs. Register PP rows.
3. **Stage 2**:  
   - CSA Level 1: compress PP rows using 3:2/4:2 compressors to reduce height.  
   - Keep to 1 compressor level + short local routing → ~4–6 FO4.
4. **Stage 3**:  
   - CSA Level 2: further compression.  
   - Again, 1 compressor level → ~4–6 FO4.
5. **Stage 4**:  
   - CSA Level 3 + add accumulator (sum, carry) into tree (if using fused MAC).  
   - Pipeline registers at the output of this stage produce updated (sum, carry).
6. **Stage 5**:  
   - Optional: final compression to two vectors + partial sums; or you can stop at stage 4 if your SSA tree is short enough.
7. **Stage 6**:  
   - VMA (CPA stage) used **only** on final read‑out; can be clock‑gated.

Points to mind:

- **Register placement**: ensure each stage has **balanced logic depth and fanout**:
  - Avoid one stage with 2 compressors and another with none; retime registers if necessary.
- Use synthesis retiming cautiously:
  - Allow the tool to move registers **within** PP/CSA but **fix** your Acc_Sum/Acc_Carry registers to keep a clear MAC loop boundary.
- Physically:
  - Place compressors of each stage in a **tight cluster** separate from others to limit inter‑stage wire length and parasitics.

Given your current 5‑stage design (1.15 GHz TT, 0.6 GHz SS), the main likely problems are:

- Too many gate levels (and long wires) in one or two critical stages, especially the “multiplier+accumulator” stage.
- A CPA in the MAC loop.

Moving to a **7‑stage fused CSA MAC** with a late VMA stage and careful retiming is the most realistic path to approach 1 GHz at SS.

---

## 3. Low‑Power Techniques for High‑Activity Structures

Your power gap (~2 mW vs <300 µW) is large; multiple orthogonal techniques are needed. The literature points to:

### 3.1 Operand Isolation & Clock Gating

1. **Design of a Low-power Computational Unit using a Pipelined Vedic Multiplier** – ICONAT 2023 [45 nm, 90 nm]  
   - Uses operand isolation around a pipelined multiplier, adder/subtractor, and logic unit to reduce power [12].  
   - Verified in 45 nm and 90 nm libraries; dynamic power is clearly reduced.

2. **Automatic Synthesis of Clock Gating Logic with Controlled Netlist Perturbation** – DAC 2008 [node‑agnostic]  
   - Synthesizes **clock‑gating conditions** automatically, reducing dynamic **clock power by ~14.5 %** across benchmarks [13].  
   - Conceptually equivalent to “valid‑gated” pipeline registers: when the enable condition is false, registers don’t toggle.

3. **Power-aware Pipelined Multiplier Design Based on 2-Dimensional Pipeline Gating** – GLSVLSI 2003 [node not specified]  
   - Introduces **2D pipeline gating**: gating clocks both vertically (across pipeline stages) and horizontally (within a stage) [11].  
   - A 16‑bit array multiplier using this technique achieved **≈66 % average power saving** and **47 % latency reduction** over an ungated design [11].

**Actionable usage**

- Add a per‑stage **valid signal**:
  - When no new MAC operation is in progress (e.g., pipeline bubble or idle), disable:
    - Clock to stage registers (**clock gating**).
    - Inputs to combinational logic (**operand isolation**) by holding them at constants (zero).
- Make gating fine‑grain:
  - E.g., if operands are zero (common in sparse workloads), gate the **partial product generation and CSA logic** entirely for that cycle.

### 3.2 Spurious Switching Reduction in Multipliers / CSA Trees

1. **A micropower low-voltage multiplier with reduced spurious switching** – IEEE TVLSI 2005 [0.35 µm]  
   - Integrates small latches into adders (“latch‑adders”) to synchronize inputs and reduce **glitches and spurious switching** in the adder block [14].  
   - Achieves:
     - ~32 % power reduction for a 16×16 multiplier.
     - Much fewer transitions per adder (down from ≈5.6–10 to ≈2).

2. General column‑compression studies [15] observe:
   - Parasitics and glitching dominate power as multipliers scale.  
   - More compression levels and longer wires increase dynamic power.

**Actionable usage**

- **Gate or latch inputs** to each CSA layer:
  - If higher‑order PP bits are zero (Booth encoding with many zeros), skip toggling in those adder slices.
  - Consider using **gated half/full adders**, where one input can be forced to zero when its operand is inactive.
- **Balance arrival times** into compressors to minimize glitching:
  - Match wire lengths/fanout, or use simple input latches as in [14] to equalize timing.
- Limit **fanout and routing congestion** between CSA stages – long wires = large parasitics = power.

### 3.3 Booth Encoding and Column Compression Tweaks

1. **Improved-Booth encoding for low-power multipliers** – ISCAS 1999 [node not given]  
   - Modifies Booth encoding to **increase the probability of zero digits**, thereby:
     - Reducing partial‑product transitions by ≈3.75 %.  
     - Reducing carry bit transitions by 3.75–7 %.  
     - HSPICE: >4 % power reduction for 16×16 two’s complement array and Wallace multipliers [16].

2. **Low-power Booth‑encoded array multiplier (patent)** – 2007, 0.5 µm [17]  
   - Reorders partial products so that low‑transition partial products are added first, absorbing switching early and reducing power in deeper adder levels.

**Actionable usage**

- Use **radix‑4 or radix‑8 Booth with bias toward zero codes**:
  - Design your Booth encoder so “00” and “11” patterns are more frequent for typical data (e.g., weights/activations with zeros or small magnitude).
- In the compressor tree:
  - Order PP columns so those with inherently low activity are **reduced earlier**, and high‑activity columns are merged later where there are fewer stages left.

### 3.4 Bit‑Serial and Mixed‑Precision MACs

1. **Booth Encoded Bit-Serial Multiply-Accumulate Units with Improved Area and Energy Efficiencies** – Electronics 2023 [TSMC 90 nm]  
   - Bit‑serial MACs with radix‑2 and radix‑4 Booth encoding; a 16‑bit radix‑4 bit‑serial MAC at 90 nm, 150–500 MHz shows up to ≈96 % area‑power product (APP) reduction vs baseline bit‑serial designs [18].  
   - Good for ultra‑low power, lower throughput.

2. **A Bit Serial Accelerator Architecture for Efficient ML Compute in Area, Power and Cost Constrained Sensors** – ICECS 2024 [40 nm]  
   - Bit‑serial MACs in 40 nm, reaching up to **12.5 TOPS/W at 0.65 V, 15 MHz** [19].

**Implications for you**

- A pure bit‑serial MAC will not meet 1 GHz throughput constraints: each 16×16 MAC would require ≥16 cycles.
- However, you can:
  - Explore **hybrid architectures** for lower‑frequency / low‑power modes.
  - **Time‑multiplex** bit‑serial sub‑MACs when the application has slack or lower precision needs.

### 3.5 Sign‑Magnitude vs Two’s Complement for MACs

1. **29.3 An 8.09TOPS/W Neural Engine Leveraging Bit-Sparsified Sign-Magnitude Multiplications and Dual Adder Trees** – ISSCC 2023 [65 nm ecosystem]  
   - Shows that **sign‑magnitude (SM) multiplications are 35–67 % more energy‑efficient** than two’s‑complement multiplications for typical neural network operand distributions [20].  
   - Problem: SM additions are more expensive (sign comparison, muxing between add/sub), offsetting gains if you do them in every cycle.

2. **Explicit Sign-Magnitude Encoders Enable Power-Efficient Multipliers** – arXiv 2025 [node not specified]  
   - Proposes **front‑end encoders** that convert 2C inputs to sign‑magnitude, then multiply in SM and convert back to 2C [21].  
   - Achieved: up to **12.9 % switching reduction** for realistic normal‑distributed inputs; up to 33 % for narrower ranges; additional 5–10 % savings via switching‑activity‑aware synthesis.

**Actionable implications**

- For your 16‑bit MAC:
  - If operands are **zero‑centered or sparse**, SM multiplication can significantly reduce internal toggling.
  - You can:
    - Keep the **accumulator in 2C** but implement the **multiplier core in SM** using front‑end encoders and back‑end converters, as in [21].
    - Or use a hybrid where **weights are sign‑magnitude** but activations remain 2C.
  - Beware of SM **addition overhead**:
    - Since your accumulator is in carry‑save redundant form (sum/carry), the SM sign compare overhead is largely at the *entry* to the multiplier; the redundant accumulator can stay mostly format‑agnostic.

---

## 4. 55 nm/65 nm Specific Design Closure & Variation Handling

Your key challenge: **1.84× TT→SS slowdown** in 55 nm; you must hit ≈1.8 GHz TT to reach ≈1 GHz SS.

### 4.1 In‑situ Timing Monitors and AVS

1. **A Low-Overhead In-Situ Timing-Error Prediction Technique with Wide-Voltage-Range Transition-Detector for Variation-Tolerant Digital Circuits** – ELEX 2023 [55 nm SMIC]  
   - Implements in‑situ timing monitors (transition detectors) integrated with a CORDIC in **SMIC 55 nm** [22].  
   - Achieves up to **53.2 % energy saving** compared to a traditional worst‑case‑margined design, with ~6.1 % area overhead.  
   - Handles SS corner by **dynamically adjusting voltage based on in‑situ error prediction**, not static design margin.

2. **Design margin elimination through robust timing error detection at ultra-low voltage** – S3S 2017 [40 nm]  
   - On an ARM Cortex‑M0 in 40 nm, in‑path timing error detection allows operation at “point‑of‑first‑failure” rather than SS margins, reducing energy by ~75 % [23].

**Implication**

- If your SoC can tolerate some lightweight AVS/clock‑control:
  - Add **in‑situ timing monitors on the MAC’s longest paths** (e.g., last CSA layer/vectors before VMA).
  - Use them to adjust local supply or clock (within your domain) rather than statically designing for the absolute worst SS.

### 4.2 Process/Temperature Variation Sensors in 55 nm/65 nm

1. **On-Chip Process Variation Sensor Based on Sub-Threshold Leakage Current with Weak Bias Voltages** – IEEE 2019 [SMIC 55 nm]  
   - Sensor measures threshold‑voltage variations for N‑ and P‑MOS using a sub‑threshold leakage based reconfigurable ring oscillator [24].  
   - Implemented in SMIC 55 nm; total area ≈37 µm².

2. **On-chip temperature and process variation sensing using a reconfigurable Ring Oscillator** – 2017 [65 nm]  
   - 65 nm test chip; ring oscillator based sensor estimates both temperature and process variation [25].

**Usage**

- Integrate such sensors near your MAC:
  - Use them to **bin parts** and set operating points (Vdd, frequency) per chip.
  - Combine with AVS or at least per‑chip frequency trimming instead of one global “SS margin”.

### 4.3 Useful Skew Clock Tree Synthesis and CTS

1. **Clustering of flip-flops for useful-skew clock tree synthesis** – ASP‑DAC 2018 [abstract; node not specified]  
   - Combines flip‑flop clustering with **useful‑skew CTS** to reduce clock wire length and total power by up to **34 %**, while still meeting timing [26].

2. General sources on useful skew and clock trees [27][28] and a 55 nm low‑power primer [29] note:
   - **Useful skew** intentionally **unbalances clock arrival times** to relax timing on critical paths at the cost of non‑critical ones:
     - Delay clock to launching FF of a critical path or advance arrival at the capturing FF.
   - In 55 nm designs, useful skew is a standard knob used together with retiming, multi‑bit flip‑flops, and buffer sizing.

**Actionable CTS practices for your MAC**

- During place‑and‑route for the MAC block (or cluster of MACs):
  - Use **useful‑skew‑enabled CTS**:
    - Identify your worst SS paths (likely PP→last CSA layer or CSA→accumulator registers).
    - Allow the clock tree to **introduce controlled skew** to add 20–30 ps of margin on these paths while preserving hold margins on others.
  - **Cluster flip‑flops** of the MAC datapath (as in [26]):
    - Group registers of adjacent pipeline stages in a small physical region to reduce inter‑stage clock skew and wire length.
- Combine with:
  - **Multi‑bit flip‑flops** for local clock power reduction and better clock buffering.
  - Tight placement of CSA/VMA logic to minimize data path variability.

---

## 5. Concrete Plan Toward Your Targets

Bringing all of this together for your specific constraints (16‑bit, 55 nm, 1 GHz SS, <300 µW):

### 5.1 Architecture & Microarchitecture

1. **Switch to a fused CSA MAC with delayed CPA**  
   - Keep accumulator in carry‑save (sum/carry); no CPA in the MAC loop.  
   - Add one final CPA (VMA) stage that is only used for read‑out.  
   - This directly attacks both your critical path and your power (no full‑width add each cycle).

2. **Increase pipeline depth and balance stages (7–8 stages)**  
   - Break your existing “multiplier+accumulator” into 2–3 separate stages:
     - Stage A: Booth encoding + PP gen.  
     - Stage B–C: CSA compression levels.  
     - Stage D: integrate accumulator sum/carry.  
     - Stage E: final VMA (only on read‑out).
   - Keep each stage to ≲10 FO4 at SS; adjust by retiming.

3. **Consider SM‑based multiplier core if workload allows**  
   - For ML‑like traffic, a SM multiplier with front‑end encoders [21] may give 10–20 % dynamic power reduction in the multiplier core.  
   - Keep accumulator redundant/2C to avoid SM add overhead in the loop.

### 5.2 Power Reduction

1. **Aggressive operand isolation and per‑stage clock gating**
   - Gate:
     - Stage clocks when pipeline bubbles/idle.  
     - PP generation when inputs are zero or unchanged.  
   - Use automatic clock‑gating inference where possible, but hand‑code clears where you know functional enables.

2. **Spurious switching control**
   - Delay‑balance PP signals into each CSA layer (short, equi‑length wires; local buffering).
   - Consider lightweight “latch‑adder” structures for particularly glitchy nodes (inspired by [14]).

3. **Encoding and compression tweaks**
   - Use improved Booth encoding variants that bias toward zero digits [16].
   - Order columns and compressors to absorb low‑transition partial products first [17].

### 5.3 Variation and Physical Design

1. **CTS with useful skew + clustering**
   - Enable useful‑skew CTS and cluster MAC pipeline registers.  
   - Explicitly constrain skew windows such that:
     - Critical MAC paths get positive slack at SS.
     - Hold margins are checked at FF and corners.

2. **On‑chip process/temp sensing and (optionally) AVS**
   - Integrate a tiny ring‑oscillator‑based process sensor near the MAC [24].  
   - Use its reading to:
     - Select one of several compiled frequency/voltage operating points.
     - Or drive an adaptive AVS loop if your SoC supports it.

3. **Guardband allocation**
   - Design MAC pipeline at **≈1.8 GHz at TT** with a modest TT guardband (~5–10 %) and rely on:
     - Useful skew + local upsizing of critical cells.  
     - Process binning / AVS for outlier dies.

---

### Key References (Representative)

[1] A HIGH-SPEED, ENERGY-EFFICIENT TWO-CYCLE MULTIPLY-ACCUMULATE (MAC) ARCHITECTURE AND ITS APPLICATION TO A DOUBLE-THROUGHPUT MAC UNIT. <https://www.sjalander.com/research/pdf/sjalander-tcas2010.pdf>  
[2] A MAC UNIT WITH DOUBLE CARRY-SAVE SCHEME SUITABLE FOR 6-INPUT LUT BASED RECONFIGURABLE SYSTEMS. <https://ieeexplore.ieee.org/document/7440400/>  
[3] A HIGH PERFORMANCE MULTIPLY-ACCUMULATE UNIT WITH DOUBLE CARRY-SAVE SCHEME FOR 6-INPUT LUT BASED RECONFIGURABLE SYSTEMS. <https://ieeexplore.ieee.org/document/7394625/>  
[4] A HIGH-PERFORMANCE CMOS REDUNDANT BINARY MULTIPLICATION-AND-ACCUMULATION (MAC) UNIT. <http://ieeexplore.ieee.org/document/260217/>  
[5] MULTIPLIER LECTURE NOTES (VECTOR MERGING ADDER DISCUSSION). <https://www.ee.iitm.ac.in/vinita/pdf/digic/multipliers.pdf>  
[6] AN EFFICIENT ARCHITECTURE FOR SIGNED CARRY SAVE MULTIPLICATION. <https://ieeexplore.ieee.org/iel7/8012254/8416766/08979361.pdf>  
[7] A HIGH PERFORMANCE HYBRID WAVE-PIPELINED MULTIPLIER. <https://ieeexplore.ieee.org/document/1430156/>  
[8] LOW-POWER 6-GHZ WAVE-PIPELINED 8B × 8B MULTIPLIER. <https://ietresearch.onlinelibrary.wiley.com/doi/10.1049/iet-cds.2012.0221>  
[9] COLUMN COMPRESSION PIPELINED MULTIPLIERS. <https://piurilabs.di.unimi.it/Papers/asap_1995_column.pdf>  
[10] A HIGH-SPEED MULTIPLEXER-BASED FINE-GRAIN PIPELINED ARCHITECTURE… (MODIFIED WALLACE TREE). <https://www.tandfonline.com/doi/abs/10.1080/00207217.2015.1017844>  
[11] POWER-AWARE PIPELINED MULTIPLIER DESIGN BASED ON 2-DIMENSIONAL PIPELINE GATING. <https://www.cecs.uci.edu/~papers/compendium94-03/papers/2003/glsvlsi03/pdffiles/p1_01.pdf>  
[12] DESIGN OF A LOW-POWER COMPUTATIONAL UNIT USING A PIPELINED VEDIC MULTIPLIER. <https://ieeexplore.ieee.org/document/10080520/>  
[13] AUTOMATIC SYNTHESIS OF CLOCK GATING LOGIC WITH CONTROLLED NETLIST PERTURBATION. <https://people.eecs.berkeley.edu/~alanmi/publications/2008/dac08_hurst2.pdf>  
[14] A MICROPOWER LOW-VOLTAGE MULTIPLIER WITH REDUCED SPURIOUS SWITCHING. <https://ieeexplore.ieee.org/document/1393025/>  
[15] ANALYSIS OF COLUMN COMPRESSION MULTIPLIERS. <https://ieeexplore.ieee.org/abstract/document/930101>  
[16] IMPROVED-BOOTH ENCODING FOR LOW-POWER MULTIPLIERS. <http://ieeexplore.ieee.org/document/777806/>  
[17] LOW-POWER BOOTH-ENCODED ARRAY MULTIPLIER. <https://patents.google.com/patent/US7225217>  
[18] BOOTH ENCODED BIT-SERIAL MULTIPLY-ACCUMULATE UNITS WITH IMPROVED AREA AND ENERGY EFFICIENCIES. <https://www.mdpi.com/2079-9292/12/10/2177>  
[19] A BIT SERIAL ACCELERATOR ARCHITECTURE FOR EFFICIENT ML COMPUTE IN AREA, POWER AND COST CONSTRAINED SENSORS. <https://ieeexplore.ieee.org/document/10849332/>  
[20] 29.3 AN 8.09TOPS/W NEURAL ENGINE LEVERAGING BIT-SPARSIFIED SIGN-MAGNITUDE MULTIPLICATIONS AND DUAL ADDER TREES. <https://ieeexplore.ieee.org/document/10067269/>  
[21] EXPLICIT SIGN-MAGNITUDE ENCODERS ENABLE POWER-EFFICIENT MULTIPLIERS. <https://arxiv.org/html/2507.18179v1>  
[22] A LOW-OVERHEAD IN-SITU TIMING-ERROR PREDICTION TECHNIQUE WITH WIDE-VOLTAGE-RANGE TRANSITION-DETECTOR. <https://www.jstage.jst.go.jp/article/elex/advpub/0/advpub_20.20230145/_pdf>  
[23] DESIGN MARGIN ELIMINATION THROUGH ROBUST TIMING ERROR DETECTION AT ULTRA-LOW VOLTAGE. <https://ieeexplore.ieee.org/document/8308743/>  
[24] ON-CHIP PROCESS VARIATION SENSOR BASED ON SUB-THRESHOLD LEAKAGE CURRENT WITH WEAK BIAS VOLTAGES. <https://ieeexplore.ieee.org/document/8790891/>  
[25] ON-CHIP TEMPERATURE AND PROCESS VARIATION SENSING USING A RECONFIGURABLE RING OSCILLATOR. <https://ieeexplore.ieee.org/document/7939649/>  
[26] CLUSTERING OF FLIP-FLOPS FOR USEFUL-SKEW CLOCK TREE SYNTHESIS. <https://ieeexplore.ieee.org/document/8297374/>  
[27] SYNTHESIS OF CLOCK TREES WITH USEFUL SKEW BASED ON SPARSE GRAPHS. <https://docs.lib.purdue.edu/dissertations/AAI10170556/>  
[28] USEFUL-SKEW CLOCK SYNTHESIS BOOSTS ASIC PERFORMANCE (CHAPTER). <http://ndl.ethernet.edu.et/bitstream/123456789/58431/1/10pdf.pdf>  
[29] AN ASIC LOW POWER PRIMER. <https://picture.iczhiku.com/resource/eetop/SyiERehJITsdJbNM.pdf>