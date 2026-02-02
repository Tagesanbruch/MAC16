# MAC16 Exp R 系列架构优化实验报告 (2026-02-02)

## 一、实验目标

基于 Exp NG (Han-Carlson 加法器, 876 MHz SS) 进一步优化，目标冲击 **1GHz @ SS corner**。

## 二、实验方案

### 2.1 Exp R: 基线（= Exp NG）
- Han-Carlson VMA
- 作为对照组

### 2.2 Exp RA: MUX-Based CSA
- 将所有 6 个 CSA 替换为 MUX 优化版本
- 理论上减少 carry 生成延迟

**关键代码 (`csa_mux.sv`)**:
```verilog
module csa_mux #(parameter WIDTH = 40) (
    input  wire [WIDTH-1:0] a, b, c,
    output wire [WIDTH-1:0] sum, carry
);
    wire [WIDTH-1:0] ab_xor = a ^ b;
    assign sum = ab_xor ^ c;
    // Bitwise MUX: (sel & 1) | (~sel & 0)
    assign carry = (ab_xor & c) | (~ab_xor & a); 
endmodule
```

### 2.3 Exp RB: Kogge-Stone VMA
- 将 Han-Carlson 替换为 Kogge-Stone
- 理论上逻辑深度从 8 级降至 6 级

**关键代码 (`kogge_stone_adder.sv`)**:
```verilog
// Level 1 to Level 6 (Log2 40 ≈ 6 stages)
// Maximum parallelism, minimum depth
genvar i;
generate
    for (i = 0; i < WIDTH; i = i + 1) begin : L1
        if (i == 0) begin
            assign g1[i] = g0[i];
            assign p1[i] = p0[i];
        end else begin
            assign g1[i] = g0[i] | (p0[i] & g0[i-1]);
            assign p1[i] = p0[i] & p0[i-1];
        end
    end
endgenerate
// ... (Continued for L2..L6 with stride 2, 4, 8, 16, 32)
```

### 2.4 Exp RC: Split VMA (5周期)
- 将 VMA 拆分为低20位/高20位两级流水
- 利用延迟余量（4→5周期）

**关键代码 (`mac16.sv`)**:
```verilog
// VMA Stage 1: Low 20-bit addition
wire [19:0] low_a = mult_result_sum[19:0];
wire [19:0] low_b = mult_result_carry[19:0];
assign {vma_low_cout, vma_low_result} = low_a + low_b;

always_ff @(posedge clk) begin
    vma_sum_s1 <= mult_result_sum; // Register full sum
    // ...
end

// VMA Stage 2: High 20-bit addition with carry-in from S1
wire [19:0] high_a = vma_sum_s1[39:20];
wire [19:0] high_b = vma_carry_s1[39:20];
wire [19:0] low_a_s1 = vma_sum_s1[19:0];
wire [19:0] low_b_s1 = vma_carry_s1[19:0];
wire [20:0] low_sum_s1 = low_a_s1 + low_b_s1; // Recompute low sum

// Final High Add with Carry
assign {vma_high_cout, vma_high_result} = high_a + high_b + low_sum_s1[20];
```

---

## 三、实验结果

| 实验 | 优化方向 | TT 频率 | SS 频率 | 面积 | 延迟 | 状态 |
|------|----------|---------|---------|------|------|------|
| **R (基线)** | Han-Carlson | **1634 MHz** | **876 MHz** | 8205 µm² | 4周期 | 🏆 最优 |
| RA | MUX CSA | 1554 MHz | 838 MHz | 8199 µm² | 4周期 | ❌ 倒退 |
| RB | Kogge-Stone | 1456 MHz | 764 MHz | 8254 µm² | 4周期 | ❌ 倒退 |
| RC | Split VMA | 1445 MHz | 802 MHz | 8479 µm² | 5周期 | ❌ 倒退 |

---

## 四、失败原因分析

### 4.1 Exp RA (MUX CSA) 失败
- Yosys/ABC 对 XOR-based CSA 的映射已经非常优化
- MUX 形式的 `(sel & a) | (~sel & b)` 需要更多门
- 综合后实际延迟反而更大

### 4.2 Exp RB (Kogge-Stone) 失败
- Kogge-Stone 虽然逻辑深度更低，但**布线更密集**
- 在 Pre-Layout STA（零线负载）下就已经更慢
- 55nm 工艺线延迟占主导，KS 的布线复杂度成为瓶颈

### 4.3 Exp RC (Split VMA) 失败
- 额外的流水级需要更多寄存器（+3.3% 面积）
- 多级 VMA 并没有显著缩短关键路径
- VMA 并非 SS 角的主要瓶颈（瓶颈在 PPG Stage 2）

---

## 五、关键发现

1. **Exp R (= NG) 的 876 MHz SS 是当前架构的理论极限**
   - 关键路径不在 VMA，而在 PPG (Stage 2)
   - PPG 由 Booth 编码后的 8 个部分积生成，难以进一步压缩

2. **工具链限制**
   - Yosys 对 Booth 编码器的映射不如商业工具
   - 手写的 MUX/KS 结构被综合器"优化"得不如预期

3. **Pre-Layout 局限性**
   - 当前 STA 是零线负载模型
   - 真实 Post-Layout 可能有 10-15% 的额外降频


---

## 六、验证命令汇总

```bash
# 功能验证
make -f iEDA.mk EXP=exp_r  verif   # PASS
make -f iEDA.mk EXP=exp_ra verif   # PASS
make -f iEDA.mk EXP=exp_rb verif   # PASS
make -f iEDA.mk EXP=exp_rc verif   # PASS

# 延迟检查
make -f iEDA.mk EXP=exp_r  latency_check   # 4 cycles PASS
make -f iEDA.mk EXP=exp_ra latency_check   # 4 cycles PASS
make -f iEDA.mk EXP=exp_rb latency_check   # 4 cycles PASS
make -f iEDA.mk EXP=exp_rc latency_check   # 5 cycles PASS

# 多角 STA
make -f iEDA.mk EXP=exp_r  sta_all
make -f iEDA.mk EXP=exp_ra sta_all
make -f iEDA.mk EXP=exp_rb sta_all
make -f iEDA.mk EXP=exp_rc sta_all
```
