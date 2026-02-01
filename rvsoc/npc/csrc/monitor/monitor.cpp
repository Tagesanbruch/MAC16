#include <common.h>
#include <debug.h>
#include <elf.h>
#include <memory/paddr.h>
#include <stdio.h>
#include <stdlib.h>
#define LOGD                                                                   \
  if (DEBUG)                                                                   \
  Log
static int DEBUG = 0;
// static int DEBUG2 = 0;
void init_rand();
void init_log(const char *log_file);
void init_mem();
void init_difftest(char *ref_so_file, long img_size, int port);
void init_device() {}
void init_sdb();
void init_disasm(const char *triple);
void init_IRB();
void init_MRB();
void init_FRB();
FILE *log_fp = NULL;
bool log_enable = true;
void init_log(const char *log_file) {
  log_fp = stdout;
  if (log_file != NULL) {
    FILE *fp = fopen(log_file, "w");
    Assert(fp, "Can not open '%s'", log_file);
    log_fp = fp;
  }
  log_enable = log_file ? true : false;
  Log("Log is written to %s", log_file ? log_file : "stdout");
}

#define __GUEST_ISA__ riscv32e
static void welcome() {
  Log("Trace: %s", MUXDEF(CONFIG_TRACE, ANSI_FMT("ON", ANSI_FG_GREEN),
                          ANSI_FMT("OFF", ANSI_FG_RED)));
  IFDEF(CONFIG_TRACE,
        Log("If trace is enabled, a log file will be generated "
            "to record the trace. This may lead to a large log file. "
            "If it is not necessary, you can disable it in menuconfig"));
  Log("Build time: %s, %s", __TIME__, __DATE__);
  printf("Welcome to %s-NPC!\n",
         ANSI_FMT(xstr(__GUEST_ISA__), ANSI_FG_YELLOW ANSI_BG_RED));
  printf("For help, type \"help\"\n");
}

#ifndef CONFIG_TARGET_AM
#include <getopt.h>

void sdb_set_batch_mode();

static char *log_file = NULL;
static char *diff_so_file = NULL; // Set via --diff argument
static char *img_file = NULL;
static char *elf_file = NULL;
static int difftest_port = 1234;
static Elf32_Sym symbol;
static char *str_tab = NULL;
#define MAX_SYMTAB 2048
#define MAX_NAME 64
struct SymTab {
  char *name;
  size_t addr;
  size_t size;
};

static const uint32_t img[] = {
    0x00000413, 0x00009117, 0xffc10113, 0x00c000ef, 0x00000513,
    0x00008067, 0x80000537, 0xff010113, 0x03850513, 0x00112623,
    0xfe9ff0ef, 0x00050513, 0x00100073, 0x0000006f, 0x00000000,
    // 0x00000297,  // auipc t0,0
    // 0x00028823,  // sb  zero,16(t0)
    // 0x0102c503,  // lbu a0,16(t0)
    // 0x00100073,  // ebreak (used as nemu_trap)
    // 0xdeadbeef,  // some data
};

static struct SymTab symtab[MAX_SYMTAB];
static int num_symtab = 0;

static long load_prog(const char *img_file) {
  if (img_file == NULL) {
    Log("No image is given. Use the default build-in image.");
    memcpy(guest_to_host(RESET_VECTOR), img, sizeof(img));
#ifndef CONFIG_PMEM_DPIC
    memcpy(&top->rootp->NPC__DOT__IM__DOT__Memory_ext__DOT__Memory, img,
           sizeof(img));
#endif
    return 4096; // built-in image size
  }

  FILE *fp = fopen(img_file, "rb");
  Assert(fp, "Can not open '%s'", img_file);

  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);

  Log("The image is %s, size = %ld", img_file, size);

  fseek(fp, 0, SEEK_SET);

  int ret = fread(guest_to_host(RESET_VECTOR), size, 1, fp);
  Log("ret=%d, size=%ld\n", ret, size);
#ifndef CONFIG_PMEM_DPIC
  memcpy(&top->rootp->NPC__DOT__IM__DOT__Memory_ext__DOT__Memory,
         guest_to_host(RESET_VECTOR), size);
  Log("IM=%#02x, &IM=%#02lx\n",
      top->rootp->NPC__DOT__IM__DOT__Memory_ext__DOT__Memory,
      &top->rootp->NPC__DOT__IM__DOT__Memory_ext__DOT__Memory);
#endif
  fclose(fp);
  return size;
}

static void load_elf() {
  if (elf_file == NULL) {
    Log("No elf is given. Reading dummy elf.");
    return;
    // elf_file = "prog/dummy.elf";
  }
  Log("Reading ELF:%s ...", elf_file);
  FILE *fp = fopen(elf_file, "rb");
  if (fp == NULL) {
    panic("File open failed...");
  }
  Elf32_Ehdr elf_header;
  int success;
  success = fread(&elf_header, 1, sizeof(Elf32_Ehdr), fp);

  if (memcmp(elf_header.e_ident, ELFMAG, SELFMAG) != 0) {
    fprintf(stderr, "Not an ELF file\n");
    fclose(fp);
    return;
  }

  if (elf_header.e_ident[EI_CLASS] != ELFCLASS32) {
    fprintf(stderr, "Not a 32-bit ELF file\n");
    fclose(fp);
    return;
  }

  if (elf_header.e_shoff == 0) {
    fprintf(stderr, "No section header table\n");
    fclose(fp);
    return;
  }

  Elf32_Shdr shdr, shdr_strtab;
  fseek(fp, elf_header.e_shoff, SEEK_SET);
  success = fread(&shdr, 1, sizeof(Elf32_Shdr), fp);
  while (shdr.sh_type != SHT_SYMTAB) {
    success = fread(&shdr, 1, sizeof(Elf32_Shdr), fp);
  }
  int num_symbols = shdr.sh_size / shdr.sh_entsize;
  fseek(fp, elf_header.e_shoff, SEEK_SET);
  success = fread(&shdr_strtab, 1, sizeof(Elf32_Shdr), fp);
  while (shdr_strtab.sh_type != SHT_STRTAB) {
    success = fread(&shdr_strtab, 1, sizeof(Elf32_Shdr), fp);
  }
  str_tab = (char *)calloc(1, shdr_strtab.sh_size);
  fseek(fp, shdr_strtab.sh_offset, SEEK_SET);
  success = fread(str_tab, sizeof(char), shdr_strtab.sh_size, fp);

  fseek(fp, shdr.sh_offset, SEEK_SET);
  for (int i = 0; i < num_symbols; i++) {
    success = fread(&symbol, 1, sizeof(Elf32_Sym), fp);
    LOGD("Symbol st_name:%#x", symbol.st_name);
    if (symbol.st_name != 0 && STT_FUNC == ELF32_ST_TYPE(symbol.st_info)) {
      LOGD("Symbol name: %s", str_tab + symbol.st_name);
      LOGD("Symbol value: 0x%x", symbol.st_value);
      LOGD("Symbol size: %u", symbol.st_size);
      LOGD("Symbol type: %u", ELF32_ST_TYPE(symbol.st_info));
      LOGD("Symbol bind: %u", ELF32_ST_BIND(symbol.st_info));
      LOGD("Symbol section index: %u", symbol.st_shndx);
      if (num_symtab > MAX_SYMTAB - 1) {
        assert(0);
      }
      symtab[num_symtab].addr = symbol.st_value;
      symtab[num_symtab].size = symbol.st_size;
      symtab[num_symtab].name = str_tab + symbol.st_name;
      num_symtab++;
    }
  }

  // Post-process: Calculate proper sizes for symbols with size=0
  // by using the distance to the next symbol
  for (int i = 0; i < num_symtab; ++i) {
    if (symtab[i].size == 0) {
      // Find the next symbol with a higher address
      size_t next_addr = 0xFFFFFFFF;
      for (int j = 0; j < num_symtab; ++j) {
        if (i != j && symtab[j].addr > symtab[i].addr &&
            symtab[j].addr < next_addr) {
          next_addr = symtab[j].addr;
        }
      }
      // If we found a next symbol, use the distance; otherwise use 4 bytes
      if (next_addr != 0xFFFFFFFF) {
        symtab[i].size = next_addr - symtab[i].addr;
        LOGD("Calculated size for %s: %lu bytes (0x%lx - 0x%lx)",
             symtab[i].name, symtab[i].size, symtab[i].addr, next_addr);
      } else {
        symtab[i].size = 4;
        LOGD("No next symbol found for %s, using 4 bytes", symtab[i].name);
      }
    }
  }

  Log("Loaded %d symbols from ELF", num_symtab);
  // free(str_tab);
  if (!success) {
    Log("Unsuccess reading elf...");
  }
  fclose(fp);
}
size_t addr_last = 0;
char *addr_func(size_t addr, int ret, int *inside) {
  // char* func = calloc(1, MAX_NAME);
  *inside = 0;
  LOGD("num_symtab=%d, addr=%#02lx", num_symtab, addr);
  if (ret) { // jalr--return
    for (int i = 0; i < num_symtab; ++i) {
      LOGD("symtab[i].addr=%#02lx, symtab[i].addr + symtab[i].size=%#02lx, "
           "addr_last=%#02lx",
           symtab[i].addr, symtab[i].addr + symtab[i].size, addr_last);
      if (addr >= symtab[i].addr && addr < symtab[i].addr + symtab[i].size) {
        addr_last = addr;
        return symtab[i].name;
      }
    }
  } else { // jal--not return, excluding j instruction inside function
    for (int i = 0; i < num_symtab; ++i) {
      LOGD("symtab[i].addr=%#02lx, symtab[i].addr + symtab[i].size=%#02lx, "
           "addr_last=%#02lx",
           symtab[i].addr, symtab[i].addr + symtab[i].size, addr_last);
      // Check if this is a jump within the same function (inside=1)
      if ((addr >= symtab[i].addr && addr < symtab[i].addr + symtab[i].size) &&
          (addr_last >= symtab[i].addr &&
           addr_last < symtab[i].addr + symtab[i].size)) {
        *inside = 1;
      }
      // Match if address is within the symbol's range
      if (addr >= symtab[i].addr && addr < symtab[i].addr + symtab[i].size) {
        addr_last = addr;
        return symtab[i].name;
      }
    }
  }

  return "???";
}

static int parse_args(int argc, char *argv[]) {
  const struct option table[] = {
      {"batch", no_argument, NULL, 'b'},
      {"log", required_argument, NULL, 'l'},
      {"elf", required_argument, NULL, 'e'},
      {"diff", required_argument, NULL, 'd'},
      {"port", required_argument, NULL, 'p'},
      {"help", no_argument, NULL, 'h'},
      {0, 0, NULL, 0},
  };
  int o;
  while ((o = getopt_long(argc, argv, "-bhl:d:p:e:", table, NULL)) != -1) {
    switch (o) {
    case 'b':
      sdb_set_batch_mode();
      break;
    case 'e':
      elf_file = optarg;
      // printf("elf_file=%s",elf_file);
      break;
    case 'p':
      sscanf(optarg, "%d", &difftest_port);
      break;
    case 'l':
      log_file = optarg;
      // printf("log_file=%s",log_file);
      break;
    case 'd':
      diff_so_file = optarg;
      break;
    case 1:
      img_file = optarg;
      return 0;
    default:
      printf("Usage: %s [OPTION...] IMAGE [args]\n\n", argv[0]);
      printf("\t-b,--batch              run with batch mode\n");
      printf("\t-l,--log=FILE           output log to FILE\n");
      printf("\t-e,--elf=FILE           load elf FILE\n");
      printf("\t-d,--diff=REF_SO        run DiffTest with reference REF_SO\n");
      printf("\t-p,--port=PORT          run DiffTest with port PORT\n");
      printf("\n");
      exit(0);
    }
  }
  return 0;
}

void init_monitor(int argc, char *argv[]) {
  /* Parse command-line arguments. */
  parse_args(argc, argv);

  /* Perform some global initialization. */

  IFDEF(CONFIG_BATCH, sdb_set_batch_mode());
  /* Set random seed. */
  init_rand();

  /* Open the log file. */
  init_log(log_file);

  /* Initialize memory. */
  init_mem();

  /* Initialize devices. */
  IFDEF(CONFIG_DEVICE, init_device());

  /* Perform ISA dependent initialization. */
  // init_isa();

  /* Load the image to memory. This will overwrite the built-in image. */
  long prog_size = load_prog(img_file);

  /* Open the log file. */
  load_elf();

  /* Initialize differential testing. */
  IFDEF(CONFIG_DIFFTEST, init_difftest(diff_so_file, prog_size, difftest_port));

  /* Initialize the Instruction Ring Buffer. */
  IFDEF(CONFIG_ITRACE, init_IRB());

  /* Initialize the Memory Ring Buffer. */
  IFDEF(CONFIG_MTRACE, init_MRB());

  /* Initialize the Function Buffer. */
  IFDEF(CONFIG_FTRACE, init_FRB());

  /* Initialize the simple debugger. */
  init_sdb();

  IFDEF(CONFIG_ITRACE, init_disasm("riscv32"));

  /* Display welcome message. */
  welcome();
}
#else // CONFIG_TARGET_AM
static long load_img() {
  extern char bin_start, bin_end;
  size_t size = &bin_end - &bin_start;
  Log("img size = %ld", size);
  memcpy(guest_to_host(RESET_VECTOR), &bin_start, size);
  return size;
}

void am_init_monitor() {
  init_rand();
  init_mem();
  init_isa();
  load_img();
  IFDEF(CONFIG_DEVICE, init_device());
  welcome();
}
#endif
