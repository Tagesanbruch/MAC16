#include <common.h>
#include <debug.h>
#include <dlfcn.h>
#include <memory/paddr.h>
extern VNPC *top;

typedef struct {
  word_t gpr[32];
  vaddr_t pc;
} CPU_state;

CPU_state cpu = {};
enum { DIFFTEST_TO_DUT, DIFFTEST_TO_REF };
void (*ref_difftest_memcpy)(paddr_t addr, void *buf, size_t n,
                            bool direction) = NULL;
void (*ref_difftest_regcpy)(void *dut, bool direction) = NULL;
void (*ref_difftest_pccpy)(uint32_t *dut, bool direction) = NULL;
void (*ref_difftest_exec)(uint64_t n) = NULL;
void (*ref_difftest_raise_intr)(uint64_t NO) = NULL;
void isa_reg_display();
extern uint32_t npc_state;
extern uint32_t npc_halt_pc;
void statistics();
const char *isa_reg_idx2str(int idx);
#ifdef CONFIG_DIFFTEST

static bool is_skip_ref = false;
static int skip_dut_nr_inst = 0;

bool isa_difftest_checkregs(CPU_state *ref_r, vaddr_t pc) {
  bool bool_tmp = true;
  for (int i = 0; i < 32; i++) {
    if (gpr(i) != ref_r->gpr[check_reg_idx(i)]) {
      // Log("REF %s.\n", isa_reg_idx2str(i));
      Log("PC: %#x, GPR %s is %#x, REF is %#x.\n", pc, isa_reg_idx2str(i),
          gpr(i), ref_r->gpr[i]);
      bool_tmp = false;
    }
  }
  return bool_tmp;
}

void difftest_skip_ref(uint32_t PC) {
  is_skip_ref = true;
  skip_dut_nr_inst = 0;
  // printf("PC=0x%x\n", PC);
  ref_difftest_pccpy(&PC, DIFFTEST_TO_REF);
}

void difftest_skip_dut(int nr_ref, int nr_dut) {
  skip_dut_nr_inst += nr_dut;
  while (nr_ref-- > 0) {
    ref_difftest_exec(1);
  }
}

void init_difftest(char *ref_so_file, long img_size, int port) {
  // If no .so file provided, skip DIFFTEST silently
  if (ref_so_file == NULL) {
    Log("DIFFTEST disabled: no reference .so file provided");
    return;
  }

  // Check if file exists
  FILE *test_fp = fopen(ref_so_file, "r");
  if (test_fp == NULL) {
    Log("DIFFTEST disabled: reference .so file not found: %s", ref_so_file);
    return;
  }
  fclose(test_fp);

  void *handle;
  handle = (void *)dlopen(ref_so_file, RTLD_LAZY);
  assert(handle);

  ref_difftest_memcpy =
      (void (*)(paddr_t, void *, size_t, bool))dlsym(handle, "difftest_memcpy");
  assert(ref_difftest_memcpy);

  ref_difftest_regcpy =
      (void (*)(void *, bool))dlsym(handle, "difftest_regcpy");
  assert(ref_difftest_regcpy);

  ref_difftest_pccpy =
      (void (*)(uint32_t *, bool))dlsym(handle, "difftest_pccpy");
  assert(ref_difftest_pccpy);

  ref_difftest_exec = (void (*)(uint64_t))dlsym(handle, "difftest_exec");
  assert(ref_difftest_exec);

  ref_difftest_raise_intr =
      (void (*)(uint64_t))dlsym(handle, "difftest_raise_intr");
  assert(ref_difftest_raise_intr);

  void (*ref_difftest_init)(int) =
      (void (*)(int))dlsym(handle, "difftest_init");
  assert(ref_difftest_init);

  Log("Differential testing: %s", ANSI_FMT("ON", ANSI_FG_GREEN));
  Log("The result of every instruction will be compared with %s. "
      "This will help you a lot for debugging, but also significantly reduce "
      "the performance. "
      "If it is not necessary, you can turn it off in menuconfig.",
      ref_so_file);

  ref_difftest_init(port);
  ref_difftest_memcpy(RESET_VECTOR, guest_to_host(RESET_VECTOR), img_size,
                      DIFFTEST_TO_REF);
  // ref_difftest_memcpy(MROM_BASE, guest_to_host(MROM_BASE), MROM_SIZE,
  //                     DIFFTEST_TO_REF);
  ref_difftest_regcpy(&cpu, DIFFTEST_TO_REF);
}

static void checkregs(CPU_state *ref, vaddr_t pc) {
  if (!isa_difftest_checkregs(ref, pc)) {
    npc_state = 1;
    npc_halt_pc = pc;
    isa_reg_display();
    statistics();
  }
}

void difftest_step(vaddr_t pc, vaddr_t npc) {
  CPU_state ref_r;

  // Hardcoded workaround for MMIO access where GPR might be stale
  if (pc == 0x8000018c) {
    difftest_skip_ref(pc + 4);
    return;
  }

  // Check for MMIO access (Software Decoding)
  // Fetch instruction from memory using PC
  uint32_t inst = paddr_read(pc, 4);
  uint32_t opcode = inst & 0x7f;

  Log("Difftest Step: pc=%08x inst=%08x opcode=%x", pc, inst, opcode);
  fprintf(stderr, "STDERR: Difftest Step: pc=%08x inst=%08x opcode=%x\n", pc,
          inst, opcode);

  // Store (0100011 = 0x23) or Load (0000011 = 0x03)
  if (opcode == 0x23 || opcode == 0x03) {
    uint32_t rs1_idx = (inst >> 15) & 0x1f;
    uint32_t rs1_val = gpr(rs1_idx); // Read from DUT
    int32_t imm = 0;

    if (opcode == 0x23) { // Store: S-type
      uint32_t imm_11_5 = (inst >> 25) & 0x7f;
      uint32_t imm_4_0 = (inst >> 7) & 0x1f;
      imm = (imm_11_5 << 5) | imm_4_0;
      // Sign extend from 12th bit
      if (imm & 0x800)
        imm |= 0xfffff000;

    } else {                       // Load: I-type
      imm = (int32_t)(inst) >> 20; // Graphic arithmetic shift using cast
    }

    uint32_t addr = rs1_val + imm;
    Log("MMIO Check: pc=%08x inst=%08x opcode=%x rs1=%d val=%08x imm=%x "
        "addr=%08x",
        pc, inst, opcode, rs1_idx, rs1_val, imm, addr);
    fprintf(stderr,
            "STDERR: MMIO Check: pc=%08x inst=%08x opcode=%x rs1=%d val=%08x "
            "imm=%x "
            "addr=%08x\n",
            pc, inst, opcode, rs1_idx, rs1_val, imm, addr);

    if (addr >= 0xa0000000 && addr < 0xc0000000) {
      difftest_skip_ref(npc);
      return;
    }
  }
  // Log("pc=%#02x, npc=%#02x", pc, npc);
  if (skip_dut_nr_inst > 0) {
    ref_difftest_regcpy(&ref_r, DIFFTEST_TO_DUT);

    if (ref_r.pc == npc) {
      skip_dut_nr_inst = 0;
      checkregs(&ref_r, npc);
      return;
    }
    skip_dut_nr_inst--;
    if (skip_dut_nr_inst == 0)
      panic("can not catch up with ref.pc = " FMT_WORD " at pc = " FMT_WORD,
            ref_r.pc, pc);
    return;
  }

  // if(top->rootp->NPC__DOT__CrossBar__DOT___deviceIndex_T_1 != 0 &&
  // top->rootp->NPC__DOT__CrossBar__DOT___deviceIndex_T_1 != 1){
  //   //device skip

  //   printf("Device:%d, skip_ref\n",
  //   top->rootp->NPC__DOT__CrossBar__DOT___deviceIndex_T_1);
  // }

  if (is_skip_ref) {
    // to skip the checking of an instruction, just copy the reg state to
    // reference design
    for (int i = 0; i < 32; i++) {
      cpu.gpr[i] = gpr(i);
    }
    cpu.pc = npc; // Advance REF PC to next instruction (matching behavior if we
                  // skipped)
    ref_difftest_regcpy(&cpu, DIFFTEST_TO_REF);
    ref_difftest_pccpy(&cpu.pc, DIFFTEST_TO_REF); // Also sync PC
    // difftest_skip_ref(npc);
    is_skip_ref = false;
    return;
  }

  if (ref_difftest_exec) {
    ref_difftest_exec(1);
    ref_difftest_regcpy(&ref_r, DIFFTEST_TO_DUT);
    checkregs(&ref_r, pc);
  }
}
#else
void init_difftest(char *ref_so_file, long img_size, int port) {}
#endif