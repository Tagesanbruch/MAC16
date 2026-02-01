/***************************************************************************************
 * Copyright (c) 2014-2022 Zihao Yu, Nanjing University
 *
 * NEMU is licensed under Mulan PSL v2.
 * You can use this software according to the terms and conditions of the Mulan
 *PSL v2. You may obtain a copy of Mulan PSL v2 at:
 *          http://license.coscl.org.cn/MulanPSL2
 *
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY
 *KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
 *NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 *
 * See the Mulan PSL v2 for more details.
 ***************************************************************************************/

#ifndef __COMMON_H__
#define __COMMON_H__

#include "VNPC.h"
#include "VNPC___024root.h"
#include <conf.h>
#include <inttypes.h>
#include <macro.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
// #include <debug.h>

#if CONFIG_MBASE + CONFIG_MSIZE > 0x100000000ul
#define PMEM64 1
#endif
typedef MUXDEF(CONFIG_ISA64, uint64_t, uint32_t) word_t;
typedef MUXDEF(CONFIG_ISA64, int64_t, int32_t) sword_t;
#define FMT_WORD MUXDEF(CONFIG_ISA64, "0x%016" PRIx64, "0x%08" PRIx32)

typedef word_t vaddr_t;
typedef MUXDEF(PMEM64, uint64_t, uint32_t) paddr_t;
#define FMT_PADDR MUXDEF(PMEM64, "0x%016" PRIx64, "0x%08" PRIx32)
typedef uint16_t ioaddr_t;

#define gpr(idx)                                                               \
  (idx == 0    ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_0   \
   : idx == 1  ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_1   \
   : idx == 2  ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_2   \
   : idx == 3  ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_3   \
   : idx == 4  ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_4   \
   : idx == 5  ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_5   \
   : idx == 6  ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_6   \
   : idx == 7  ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_7   \
   : idx == 8  ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_8   \
   : idx == 9  ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_9   \
   : idx == 10 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_10  \
   : idx == 11 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_11  \
   : idx == 12 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_12  \
   : idx == 13 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_13  \
   : idx == 14 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_14  \
   : idx == 15 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_15  \
   : idx == 16 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_16  \
   : idx == 17 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_17  \
   : idx == 18 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_18  \
   : idx == 19 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_19  \
   : idx == 20 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_20  \
   : idx == 21 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_21  \
   : idx == 22 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_22  \
   : idx == 23 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_23  \
   : idx == 24 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_24  \
   : idx == 25 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_25  \
   : idx == 26 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_26  \
   : idx == 27 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_27  \
   : idx == 28 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_28  \
   : idx == 29 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_29  \
   : idx == 30 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_30  \
   : idx == 31 ? top->rootp->NPC__DOT__CPU__DOT__RegRegisterFile__DOT__reg_31  \
               : NULL)

// #define CSR(idx)
// (top->rootp->NPC__DOT__CPU__DOT__CSRRegisterFile__DOT__reg_##idx)
#define csr(idx)                                                               \
  (idx == 0   ? top->rootp->NPC__DOT__CPU__DOT__CSRFile__DOT__regs_0           \
   : idx == 1 ? top->rootp->NPC__DOT__CPU__DOT__CSRFile__DOT__regs_1           \
   : idx == 2 ? top->rootp->NPC__DOT__CPU__DOT__CSRFile__DOT__regs_2           \
   : idx == 3 ? top->rootp->NPC__DOT__CPU__DOT__CSRFile__DOT__regs_3           \
   : idx == 4 ? top->rootp->NPC__DOT__CPU__DOT__CSRFile__DOT__regs_4           \
   : idx == 5 ? top->rootp->NPC__DOT__CPU__DOT__CSRFile__DOT__regs_5           \
   : idx == 6 ? top->rootp->NPC__DOT__CPU__DOT__CSRFile__DOT__regs_6           \
   : idx == 7 ? top->rootp->NPC__DOT__CPU__DOT__CSRFile__DOT__regs_7           \
              : NULL)
// static inline int gpr(int idx) {
//   assert(idx >= 0 && idx < 32);
//   return GPR(idx);
// }

static inline int check_reg_idx(int idx) {
  assert(idx >= 0 && idx < 32);
  return idx;
}
extern VNPC *top;

static inline const char *reg_name(int idx) {
  extern const char *regs[];
  return regs[check_reg_idx(idx)];
}

// CPU state access macros for itrace
#define CPU_PC top->rootp->NPC__DOT__CPU__DOT__PC
#define CPU_SNPC top->rootp->NPC__DOT__CPU__DOT__WB_PC
#define CPU_INST_OUT top->rootp->NPC__DOT__CPU__DOT__WB_inst
#define CPU_HALT                                                               \
  top->rootp->NPC__DOT__CPU__DOT__halt // Direct access to ysyx_23060116's
                                       // internal halt register

#endif
