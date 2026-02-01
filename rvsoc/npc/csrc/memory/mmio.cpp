#include <common.h>
#include <debug.h>
#include <trace.h>
#include <sys/time.h>

#ifdef CONFIG_DEVICE
// static struct timeval tv1, tv2;
static struct timespec tv1, tv2;

extern RingBuffer* MRB;
static void out_of_bound(paddr_t addr) {
  panic("address = " FMT_PADDR " is out of bound] at pc = " FMT_WORD,
        addr, top->io_pc);
  // assert(0);
}

word_t mmio_read(paddr_t addr, int len) {
#ifdef CONFIG_MTRACE
  char* pstr = (char*)calloc(1, BUFFER_LEN);
  // sprintf(pstr, "Read:  %#-2x %#-2x", addr, pmem_read(addr, len));
  sprintf(pstr, "ReadMMIO:  %#-2x", addr);
  RingBuffer_write(MRB, pstr);
  free(pstr);
#endif
  if (addr == CONFIG_RTC_MMIO + 4) {
    // word_t ret = io_read(addr, len);
    // gettimeofday(&tv2,NULL);
    // uint64_t td = (tv2.tv_sec*1000000 + tv2.tv_usec - (tv1.tv_sec*1000000 + tv1.tv_usec));
    clock_gettime(CLOCK_REALTIME, &tv2);
    uint64_t td = (tv2.tv_sec*1000000 + tv2.tv_nsec / 1000 - (tv1.tv_sec*1000000 + tv1.tv_nsec / 1000));
    uint32_t th = (td >> 32);
    return th;
  }else if (addr == CONFIG_RTC_MMIO) {
    // uint64_t td = (tv2.tv_sec*1000000 + tv2.tv_usec - (tv1.tv_sec*1000000 + tv1.tv_usec));
    uint64_t td = (tv2.tv_sec*1000000 + tv2.tv_nsec / 1000 - (tv1.tv_sec*1000000 + tv1.tv_nsec / 1000));
    uint32_t tl = (td & 0xffffffff);
    return tl;
  }
  // return 0xabcdef12;
  out_of_bound(addr);
  return 0;
}

void mmio_write(paddr_t addr, int len, word_t data) {
#ifdef CONFIG_MTRACE
  char* pstr = (char*)calloc(1, BUFFER_LEN);
  sprintf(pstr, "WriteMMIO: %#-2x %#-2x", addr, data);
  RingBuffer_write(MRB, pstr);
  free(pstr);
#endif
  if (addr == CONFIG_SERIAL_MMIO) {
    putchar(data);
    return;
  } else if(addr == CONFIG_RTC_MMIO){
    // gettimeofday(&tv1,NULL); //Start time
    clock_gettime(CLOCK_REALTIME, &tv1);
    return;
  } else if(addr == CONFIG_RTC_MMIO + 4){
    return;
  }
  out_of_bound(addr);
}
#endif