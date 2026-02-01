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
#include <common.h>
#include <cpu/decode.h>
#include <debug.h>
#include <memory/paddr.h>
#include <readline/history.h>
#include <readline/readline.h>
#include <sdb.h>
#include <trace.h>
static int is_batch_mode = false;
void step();
void init_regex();
void init_wp_pool();
static uint64_t g_timer = 0; // unit: us
uint64_t g_nr_guest_inst = 0;
// word_t pmem_read(paddr_t addr, int len);
extern word_t paddr_read(paddr_t addr, int len);
extern RingBuffer *IRB;
extern RingBuffer *MRB;
extern RingBuffer *FRB;
static int spaces = 0;
static word_t expval[32] = {0};
void print_wp();
void free_wp(int no);
int add_wp(char *e, bool *success);
/* We use the `readline' library to provide more flexibility to read from stdin.
 */
static void execute(uint64_t n);
static void exec_once(Decode *s, vaddr_t pc);
void isa_reg_display();
char *addr_func(size_t addr, int ret, int *inside);
word_t isa_reg_str2val(const char *s, bool *success);
uint32_t npc_state = 0;
uint32_t npc_halt_ret = 0;
uint32_t npc_halt_pc = 0;
int update_wp(word_t *pre, bool *success);
extern VNPC *top;
static int g_print_step = 0;
void difftest_step(vaddr_t pc, vaddr_t npc);
static int diff_ret = 0;
uint64_t get_time();

void statistics() {
  Log("host time spent = %ld us", g_timer);
  Log("total guest instructions = %d", g_nr_guest_inst);
  if (g_timer > 0)
    Log("simulation frequency = %ld inst/s",
        g_nr_guest_inst * 1000000 / g_timer);
  else
    Log("Finish running in less than 1 us and can not calculate the simulation "
        "frequency");
  IFDEF(CONFIG_ITRACE, RingBuffer_show(IRB));
  IFDEF(CONFIG_MTRACE, RingBuffer_show(MRB));
  IFDEF(CONFIG_FTRACE, RingBuffer_show(FRB));
}

void cpu_exec(uint64_t n) {
  if (CPU_HALT || top->rootp->NPC__DOT__CPU__DOT__abort) {
    // Log("Program ended.");
    return;
  }
  uint64_t timer_start = get_time();
  execute(n);
  uint64_t timer_end = get_time();
  g_timer += timer_end - timer_start;

  if (npc_state == 0 && CPU_HALT) {
    bool success;
    npc_halt_ret = isa_reg_str2val("a0", &success);
    isa_reg_display();
    statistics();
    Log("npc: %s at pc = " FMT_WORD,
        (npc_state == 1
             ? ANSI_FMT("ABORT", ANSI_FG_RED)
             : (npc_halt_ret == 0 ? ANSI_FMT("HIT GOOD TRAP", ANSI_FG_GREEN)
                                  : ANSI_FMT("HIT BAD TRAP", ANSI_FG_RED))),
        top->rootp->NPC__DOT__CPU__DOT__SNPC);
  }
}

static void trace_and_difftest(Decode *_this, vaddr_t dnpc) {
  // #ifdef CONFIG_ITRACE_COND
  // if (ITRACE_COND) {
  //   log_write("%s\n", _this->logbuf);
  // }
  // #endif
  if (g_print_step) {
    IFDEF(CONFIG_ITRACE, Log("%s", _this->logbuf));
  }
  IFDEF(CONFIG_DIFFTEST, difftest_step(_this->pc, _this->dnpc));
}

static void execute(uint64_t n) {
  Decode s;
  if (n < 10) {
    g_print_step = 1;
  } else {
    g_print_step = 0;
  }
  for (; n > 0; n--) {
    word_t pc_exe = top->rootp->NPC__DOT__CPU__DOT__SNPC;
    // Log("pc_exe=%#02x",pc_exe);
    exec_once(&s, pc_exe);
    g_nr_guest_inst++;
    trace_and_difftest(&s, pc_exe);
    if (top->rootp->NPC__DOT__CPU__DOT__abort) {
      npc_state = 1;
    }
    if (CPU_HALT) {
      break;
    }
    if (npc_state != 0) {
      break;
    }
#ifdef CONFIG_WATCHPOINT
    bool success = false;
    if (update_wp(expval, &success) == 1) {
      // npc_state = NEMU_STOP;
      Log("Watchpoint changes occurred.\n");
      break;
    }
#endif
    // IFDEF(CONFIG_DEVICE, device_update());
  }
}

static void exec_once(Decode *s, vaddr_t pc) {
  // s->pc = pc;
  // s->snpc = pc;
  s->pc = CPU_SNPC; // Use writeback PC
  int cnt_pc = 0;
  int max_step = 1000;

  // Debug: Track entry state
  // IFDEF(CONFIG_ITRACE,
  //       Log("[exec_once] Start: WB_PC=0x%x, WB_inst=0x%x, halt=%d", CPU_SNPC,
  //           CPU_INST_OUT, CPU_HALT));
  // while(top->rootp->NPC__DOT__CPU__DOT__wbu__DOT__state != 2) //wb ready, but
  // need 1 step more
  while (top->rootp->NPC__DOT__CPU__DOT__wbu__DOT__io_RegBus_wen_0 != 1 &&
         !CPU_HALT) // wb ready, but need 1 step more
  {
    step();
    // printf("cnt=%d, wbu_state=%d\n", cnt_pc,
    // top->rootp->NPC__DOT__CPU__DOT__wbu__DOT__state);
    cnt_pc++;
    if (cnt_pc > max_step) {
      isa_reg_display();
      statistics();
    }
    assert(cnt_pc <= max_step);
  }
  if (!CPU_HALT) {
    step();
  }
  s->snpc = CPU_SNPC;    // Writeback PC (current completed instruction)
  s->dnpc = CPU_PC;      // Current fetch PC
  s->isa = CPU_INST_OUT; // Writeback instruction

  // Debug: Track exit state
  // IFDEF(CONFIG_ITRACE,
  //       Log("[exec_once] End: WB_PC=0x%x, WB_inst=0x%x, halt=%d, steps=%d",
  //           s->snpc, s->isa, CPU_HALT, cnt_pc));

#ifdef CONFIG_ITRACE
  // if (s->pc != s->dnpc) {
  char *p = s->logbuf;
  p += snprintf(p, sizeof(s->logbuf), FMT_WORD ":", s->snpc);
  int ilen = 4;
  int i;
  uint8_t *inst = (uint8_t *)&s->isa;
  for (i = ilen - 1; i >= 0; i--) {
    p += snprintf(p, 4, " %02x", inst[i]);
  }
  int ilen_max = MUXDEF(CONFIG_ISA_x86, 8, 4);
  int space_len = ilen_max - ilen;
  if (space_len < 0)
    space_len = 0;
  space_len = space_len * 3 + 1;
  memset(p, ' ', space_len);
  p += space_len;

#ifndef CONFIG_ISA_loongarch32r
  void disassemble(char *str, int size, uint64_t pc, uint8_t *code, int nbyte);
  disassemble(p, s->logbuf + sizeof(s->logbuf) - p, s->pc, (uint8_t *)&s->isa,
              ilen);
  // char* strring = sprintf("%#2x: %#2x %s", s->pc,)
  char *inst_str = (char *)calloc(1, 5);
  char *funclog_buf = (char *)calloc(1, BUFFER_LEN);
  inst_str = strncpy(inst_str, p, 4);
  int inside = 0;
  int _isret =
      inst[3] == 0x00 && inst[2] == 0x00 && inst[1] == 0x80 && inst[0] == 0x67;
  if (_isret) {
    inside = 0;
    char *func = addr_func(s->snpc, 1, &inside);
    // Log("Write FRB at %#02x",s->snpc);
    memset(funclog_buf, ' ', spaces);
    int bs = sprintf(funclog_buf + spaces, "ret %s", func);
    if (spaces > 0) {
      spaces -= 2;
    }
    // Log("pc:%#02x, snpc:%#02x", s->pc, s->snpc);
    RingBuffer_write(FRB, funclog_buf);
    assert(bs > 0);
  } else if (strcmp(inst_str, "jalr") == 0 ||
             strcmp(inst_str, "jal\t") ==
                 0) { // function return: jalr instruction & jal instruction
    inside = 0;
    char *func = addr_func(s->snpc, 0, &inside);
    // Log("Write FRB at %#02x",s->snpc);
    memset(funclog_buf, ' ', spaces);
    if (!inside) {
      int bs = sprintf(funclog_buf + spaces, "call %s@[%#2x]", func, s->snpc);
      if (spaces < 90) {
        spaces += 2;
      }
      // Log("pc:%#02x, snpc:%#02x", s->pc, s->snpc);
      RingBuffer_write(FRB, funclog_buf);
      assert(bs > 0);
    }
  }
  free(inst_str);
  free(funclog_buf);
  int ret = RingBuffer_write(IRB, s->logbuf);
  assert(ret != 0);
  // Log("%s", s->logbuf);

#else
  p[0] = '\0'; // the upstream llvm does not support loongarch32r
#endif
  // }

#endif
}

static char *rl_gets() {
  static char *line_read = NULL;
  if (line_read) {
    free(line_read);
    line_read = NULL;
  }

  line_read = readline("(npc) ");

  if (line_read && *line_read) {
    add_history(line_read);
  }

  return line_read;
}

static int cmd_c(char *args) {
  if (args != NULL) {
    Log("c <pc>: run to <pc>");
    char str[32];
    sprintf(str, "$pc==0x%s", args);
    bool success = true;
    int wp_num = add_wp(str, &success);
    if (success == false) {
      Log("Failed to add watchpoint.\n");
      return 0;
    }
    Log("Add the %d watchpoint %s\n", wp_num, str);
  }
  cpu_exec(-1);
  return 0;
}

static int cmd_q(char *args) {
  // set_npc_state(NEMU_QUIT, 0x80000000, 0);
  //  npc_state.state = NEMU_QUIT;
  //  cpu_exec(-1);
  //  exit(0);
  return -1;
}

static int cmd_x(char *args) {
  char *str;
  char *exprstr;
  int n;
  int length = strlen(args);
  word_t exprval;
  str = (char *)malloc(length + 1);
  strcpy(str, args);
  char *str_end = str + strlen(str);
  char *Nstr = strtok(str, " ");
  n = atoi(Nstr);
  if (n == 0) {
    printf("Invalid input for N.\n");
    free(str);
    return 0;
  }
  exprstr = Nstr + strlen(Nstr) + 1;
  if (exprstr >= str_end) {
    exprstr = NULL;
  }
  // expression value calculate
  // exprval = strtol(exprstr, NULL, 16);
  bool success = false;
  exprval = expr(exprstr, &success);
  if (success == false) {
    printf("Invalid input for EXPR.\n");
    free(str);
    return 0;
  }
  for (int i = 0; i < n; i++) {
    // word_t memval = 1;
    word_t memval = paddr_read(exprval + 4 * i, 4);
    printf("%-#10x: %-12d %#010x\n", exprval + 4 * i, memval, memval);
  }
  free(str);
  return 0;
}

static int cmd_info(char *args) {
  // printf("%s\n", args);
  // printf("%d\n", strcmp(args, "r"));
  // RingBuffer_show
  if (args == NULL) {
    printf("Invalid input for info command.\n");
    return 0;
  }
  if (strcmp(args, "r") == 0) {
    // prints register status
    isa_reg_display();
    // ;
  } else if (strcmp(args, "w") == 0) {
    // prints watchpoints status
    print_wp();
  } else if (strcmp(args, "t") == 0) {
    // prints trace status
    IFDEF(CONFIG_ITRACE, RingBuffer_show(IRB));
    IFDEF(CONFIG_MTRACE, RingBuffer_show(MRB));
    IFDEF(CONFIG_FTRACE, RingBuffer_show(FRB));
  } else {
    printf("Invalid input for info command.\n");
    return 0;
  }
  return 0;
}

static int cmd_cy(char *args) {
  int n;
  if (args == NULL) {
    n = 1;
  } else {
    n = atoi(args);
    if (n == 0) {
      printf("Error input for n.\n");
      return 0;
    }
  }
  for (int i = 0; i < n; ++i) {
    step();
  }
  return 0;
}

static int cmd_si(char *args) {
  int n;
  if (args == NULL) {
    n = 1;
  } else {
    n = atoi(args);
    if (n == 0) {
      printf("Error input for n.\n");
      return 0;
    }
  }
  cpu_exec(n);
  return 0;
}

static int cmd_w(char *args) {
  // expression value calculate
  bool success = true;
  if (success == false) {
    printf("Invalid input for EXPR.\n");
    return 0;
  }
  int wp_num = add_wp(args, &success);
  Log("Add the %d watchpoint %s\n", wp_num, args);
  return 0;
}

static int cmd_d(char *args) {
  int n;
  if (args == NULL) {
    n = 0;
  } else {
    n = atoi(args);
    if (n < 0 || n > 31) {
      printf("Error input for n.\n");
      return 0;
    }
  }
  free_wp(n);
  return 0;
}

static int cmd_p(char *args) {
  word_t exprval;
  bool success = true;
  exprval = expr(args, &success);
  if (success == false) {
    printf("Invalid input for EXPR.\n");
    return 0;
  }
  printf("%-20s: %-#8x\n", args, exprval);
  return 0;
}

static int cmd_help(char *args);

static struct {
  const char *name;
  const char *description;
  int (*handler)(char *);
} cmd_table[] = {
    {"help", "Display information about all supported commands", cmd_help},
    {"c", "Continue the execution of the program", cmd_c},
    {"q", "Exit NEMU", cmd_q},
    {"si",
     "Run the execution by executes N of single steps. Usage: si <N>, N for "
     "default is 1 ",
     cmd_si},
    {"info",
     "Print status of program. Usage: info <SUBCMD>, while r for SUBCMD "
     "presents registers status, and w for SUBCMD presents watchpoint status",
     cmd_info},
    {"x",
     "Find the value of the expression EXPR, use the result as the starting "
     "memory address, and output N consecutive 4-bytes in hexadecimal. "
     "Usage: "
     "x <N> <EXPR>",
     cmd_x},
    {"w", "Halt the execution when the value of EXPR changed. Usage: w <EXPR>",
     cmd_w},
    {"d", "Delete the watchpoint N. Usage: d <N>", cmd_d},
    {"p", "Calculate the value of EXPR. Usage: p <EXPR>", cmd_p},
    {"cy", "Force CPU run N cycles. Usage: cy <N>", cmd_cy},
    /* TODO: Add more commands */

};

#define NR_CMD ARRLEN(cmd_table)

static int cmd_help(char *args) {
  /* extract the first argument */
  char *arg = strtok(NULL, " ");
  int i;

  if (arg == NULL) {
    /* no argument given */
    for (i = 0; i < NR_CMD; i++) {
      printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
    }
  } else {
    for (i = 0; i < NR_CMD; i++) {
      if (strcmp(arg, cmd_table[i].name) == 0) {
        printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
        return 0;
      }
    }
    printf("Unknown command '%s'\n", arg);
  }
  return 0;
}

void sdb_set_batch_mode() { is_batch_mode = true; }

void sdb_mainloop() {
  if (is_batch_mode) {
    cmd_c(NULL);
    return;
  }

  for (char *str; (str = rl_gets()) != NULL;) {
    char *str_end = str + strlen(str);

    /* extract the first token as the command */
    char *cmd = strtok(str, " ");
    if (cmd == NULL) {
      continue;
    }

    /* treat the remaining string as the arguments,
     * which may need further parsing
     */
    char *args = cmd + strlen(cmd) + 1;
    if (args >= str_end) {
      args = NULL;
    }

    // #ifdef CONFIG_DEVICE
    //     extern void sdl_clear_event_queue();
    //     sdl_clear_event_queue();
    // #endif

    int i;
    for (i = 0; i < NR_CMD; i++) {
      if (strcmp(cmd, cmd_table[i].name) == 0) {
        if (cmd_table[i].handler(args) < 0) {
          return;
        } //-1 exit
        break;
      }
    }

    if (i == NR_CMD) {
      printf("Unknown command '%s'\n", cmd);
    }
  }
}

void init_sdb() {
  /* Compile the regular expressions. */
  init_regex();

  /* Initialize the watchpoint pool. */
  init_wp_pool();
}
