#include "VNPC.h"
#include "VNPC___024root.h"
#include <debug.h>
#include <memory/host.h>
#include <memory/paddr.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

void statistics();
void isa_reg_display();

#ifdef CONFIG_TRACE
#define TRACE
#endif
#ifdef TRACE
#ifdef TRACE_FST
#include "verilated_fst_c.h"
VerilatedFstC *tfp = NULL;
#else
#include "verilated_vcd_c.h"
VerilatedVcdC *tfp = NULL;
#endif
#endif
VerilatedContext *contextp = NULL;
VNPC *top = NULL;
extern uint32_t npc_state;
extern uint32_t npc_halt_ret;
int trace_time = 0;
void step() {
  top->clock = 0;
  top->eval();
#ifdef TRACE
  if (trace_time++ < CONFIG_TRACE_MAX) {
    tfp->dump(contextp->time());
    contextp->timeInc(1);
    // printf("trace_time=%d\n",trace_time);
  }
#endif
  top->clock = 1;
  top->eval();
#ifdef TRACE
  if (trace_time++ < CONFIG_TRACE_MAX) {
    tfp->dump(contextp->time());
    contextp->timeInc(1);
    // printf("trace_time=%d\n",trace_time);
  }
#endif
}

void step_no_inst() {
  top->clock = 0;
  top->eval();
#ifdef TRACE
  if (trace_time++ < CONFIG_TRACE_MAX) {
    tfp->dump(contextp->time());
    contextp->timeInc(1);
  }
#endif
  top->clock = 1;
  top->eval();
#ifdef TRACE
  if (trace_time++ < CONFIG_TRACE_MAX) {
    tfp->dump(contextp->time());
    contextp->timeInc(1);
  }
#endif
}

void reset(int n) {
  top->reset = 1;
  while (n--) {
    step_no_inst();
  }
  top->reset = 0;
}

void sdb_mainloop();

void signal_handler(int sig) {
  Log("\n\n[NPC] Caught signal %d (Ctrl+C), exiting...\n", sig);
  Log("=== Execution Statistics ===\n");
  statistics();
  Log("\n=== Register State ===\n");
  isa_reg_display();
#ifdef TRACE
  if (tfp) {
    tfp->close();
  }
#endif
  exit(0);
}

void init_monitor(int argc, char *argv[]);
int main(int argc, char *argv[]) {
  signal(SIGINT, signal_handler);

  contextp = new VerilatedContext;
  contextp->commandArgs(argc, argv);
  top = new VNPC;
#ifdef TRACE
#ifdef TRACE_FST
  tfp = new VerilatedFstC;
  contextp->traceEverOn(true);
  top->trace(tfp, 0);
  tfp->open("wave.fst");
#else
  tfp = new VerilatedVcdC;
  contextp->traceEverOn(true);
  top->trace(tfp, 0);
  tfp->open("wave.vcd");
#endif
#endif
  reset(10);
  init_monitor(argc, argv);
  sdb_mainloop();

#ifdef TRACE
  tfp->close();
  delete tfp;
#endif
  delete contextp;
  if (npc_state == 0 && npc_halt_ret == 0) {
    return 0;
  } else {
    return -1;
  }
}
