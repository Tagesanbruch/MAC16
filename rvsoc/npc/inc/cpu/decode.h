#include <common.h>

typedef struct Decode {
  vaddr_t pc;
  vaddr_t snpc; // static next pc
  vaddr_t dnpc; // dynamic next pc
  uint32_t isa;
  IFDEF(CONFIG_ITRACE, char logbuf[128]);
} Decode;