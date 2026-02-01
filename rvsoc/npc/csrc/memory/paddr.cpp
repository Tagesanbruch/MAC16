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

#include <assert.h>
#include <debug.h>
#include <device/mmio.h>
#include <memory/host.h>
#include <memory/paddr.h>
#include <stdlib.h>
#include <trace.h>
#define CONFIG_DEVICE 1
#include <common.h>
extern VNPC *top;
extern void difftest_skip_ref(uint32_t PC);

// #define CONFIG_PMEM_MALLOC 1
#ifdef CONFIG_PMEM_MALLOC
static uint8_t *pmem = NULL;
#else // CONFIG_PMEM_GARRAY
static uint8_t pmem[CONFIG_MSIZE] PG_ALIGN = {};
// static paddr_t paddr_last;
#endif
extern RingBuffer *MRB;

uint8_t *guest_to_host(paddr_t paddr) { return pmem + paddr - CONFIG_MBASE; }
paddr_t host_to_guest(uint8_t *haddr) { return haddr - pmem + CONFIG_MBASE; }

static word_t pmem_read(paddr_t addr, int len) {
// Log("pmem_read(%#02x, %d)", addr, len);
#ifdef CONFIG_MTRACE
  char *pstr = (char *)calloc(1, BUFFER_LEN);
  // sprintf(pstr, "Read:  %#-2x %#-2x", addr, pmem_read(addr, len));
  sprintf(pstr, "Read:  %#-2x", addr);
  RingBuffer_write(MRB, pstr);
  free(pstr);
#endif
  word_t ret = host_read(guest_to_host(addr), len);
  return ret;
}

static void pmem_write(paddr_t addr, int len, word_t data) {
// Log("pmem_write(%#02x, %d, %#02x)", addr, len, data);
#ifdef CONFIG_MTRACE
  char *pstr = (char *)calloc(1, BUFFER_LEN);
  sprintf(pstr, "Write: %#-2x %#-2x", addr, data);
  RingBuffer_write(MRB, pstr);
  free(pstr);
#endif
  host_write(guest_to_host(addr), len, data);
}

static void out_of_bound(paddr_t addr) {
  panic("address = " FMT_PADDR " is out of bound of pmem [" FMT_PADDR
        ", " FMT_PADDR "] at pc = " FMT_WORD,
        addr, PMEM_LEFT, PMEM_RIGHT, top->io_pc);
  // assert(0);
}

void init_mem() {
#if defined(CONFIG_PMEM_MALLOC)
  pmem = (uint8_t *)malloc(CONFIG_MSIZE);
  assert(pmem);
#endif
  IFDEF(CONFIG_MEM_RANDOM, memset(pmem, rand(), CONFIG_MSIZE));
  Log("physical memory area [" FMT_PADDR ", " FMT_PADDR "]", PMEM_LEFT,
      PMEM_RIGHT);
}

word_t paddr_read(paddr_t addr, int len) {
  // Log("paddr_read(%#02x, %d)", addr, len);
  if (likely(in_pmem(addr)))
    // Log("paddr_read(%#02x, %d, %#02x)", addr, len, pmem_read(addr, len));
    return pmem_read(addr, len);

  difftest_skip_ref(top->io_pc);
  IFDEF(CONFIG_DEVICE, return mmio_read(addr, len));

  out_of_bound(addr);
  return 0;
}

void paddr_write(paddr_t addr, int len, word_t data) {
  // Log("paddr_write(%#02x, %d, %#02x)", addr, len, data);
  if (likely(in_pmem(addr))) {
    pmem_write(addr, len, data);
    return;
  }

  difftest_skip_ref(top->io_pc);
  IFDEF(CONFIG_DEVICE, mmio_write(addr, len, data); return);
  out_of_bound(addr);
}

extern "C" void pmem_read_v(int raddr, int *rdata) {
  // Always read 4 bytes from the aligned address `raddr & ~0x3u`
  // This matches AXI behavior where generic reads return the full bus word.
  // The CPU (EXU) is responsible for shifting/masking based on the address
  // LSBs.
  *rdata = paddr_read(raddr & ~0x3u, 4);
}

extern "C" void pmem_write_v(int waddr, int wdata, char wmask) {
  // Always write `wdata` to the 4 bytes at the address `waddr & ~0x3u`
  // according to the write mask `wmask` Each bit in `wmask` represents a byte
  // mask in `wdata`, For example, `wmask = 0x3` means only the lowest 2 bytes
  // are written, other bytes in memory remain unchanged

  // Align address to 4 bytes for PMEM access
  int aligned_addr = waddr & ~0x3u;

  if (likely(in_pmem(aligned_addr))) {
    int pmem_data = paddr_read(aligned_addr, 4);
    int write_data = 0;
    for (int i = 0; i < 4; i++) {
      // Since we broadcasted wdata in EXU, the correct byte is already at byte
      // lane i
      if ((wmask >> i) & 1) {
        write_data |= (wdata & (0xff << (i * 8)));
      } else {
        write_data |= (pmem_data & (0xff << (i * 8)));
      }
    }
    paddr_write(aligned_addr, 4, write_data);
  } else {
    int len = (wmask == 1) ? 1 : (wmask == 3) ? 2 : (wmask == 15) ? 4 : 0;

    // For MMIO, peripherals might expect data right-aligned (LSB) if we use
    // standard mmio_write But our EXU broadcasts data. So if we write byte to
    // 0x1, wdata has 0xXX at bits 15:8. Standard mmio_read usually returns
    // value at LSB. mmio_write likely expects value at LSB too for byte access?
    // Let's unshift for MMIO to be safe, assuming mmio_write(addr, 1, val)
    // expects val at bits 7:0.
    int shift = 0;
    if (wmask == 1)
      shift = 0;
    else if (wmask == 2)
      shift = 8;
    else if (wmask == 4)
      shift = 16;
    else if (wmask == 8)
      shift = 24;
    else if (wmask == 3)
      shift = 0; // Halfword 0x0
    else if (wmask == 12)
      shift = 16; // Halfword 0x2

    int mmio_data = (wdata >> shift);

    // Use original waddr for MMIO to preserve offset
    difftest_skip_ref(top->io_pc);
    IFDEF(CONFIG_DEVICE, mmio_write(waddr, len, mmio_data); return);
    out_of_bound(waddr);
  }
}