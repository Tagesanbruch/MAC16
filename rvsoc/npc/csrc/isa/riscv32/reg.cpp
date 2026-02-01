#include <common.h>
#include <debug.h>

const char *regs[] = {
  "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
  "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
  "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

const char *csr[] = {
  "mtvec", "mepc", "mcause", "mie", "mip", "mtval", "mscratch", "mstatus"
};

void isa_reg_display() {
    int length_regs;
    length_regs = 32;
    int cnt = 0;
    for(int i = 0;i < length_regs ;i++){
        word_t val;
        bool success = false;
        success = 1;
        val = gpr(i);
        if(success){
          printf(ANSI_FMT("%-2d %-8s %-#15x ", ANSI_FG_CYAN), i, reg_name(i), val);
          cnt++;
          if(cnt == 4){
            cnt = 0;
            printf("\n");
          }
        }else{
          printf("REG %s not found\n", reg_name(i));
        }
    }
    cnt = 8;
    while (cnt > 0){
      printf(ANSI_FMT("%-2d %-8s %-#15x ", ANSI_FG_CYAN), 8-cnt, csr[8-cnt], csr(8-cnt));
        cnt--;
      if(cnt==4){
        printf("\n");
      }
    }
    printf("\n");
}

word_t isa_reg_str2val(const char *s, bool *success) {
  *success = false;
  for (int i = 0; i < 32; ++i) {
    if (strcmp(s, regs[i]) == 0) {
      *success = true;
      return gpr(i);
    }else if (strcmp(s, "pc") == 0){
      *success = true;
      return top->io_pc;
    }
  }
  return 0;
}

const char* isa_reg_idx2str(int idx) {
  return regs[check_reg_idx(idx)];
}
