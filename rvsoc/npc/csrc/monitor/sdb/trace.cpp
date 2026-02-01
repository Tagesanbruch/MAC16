#include <trace.h>

RingBuffer* IRB;
RingBuffer* MRB;
RingBuffer* FRB;
#ifdef CONFIG_TRACE
#define RingBuffer_available_data(B) \
  (((B)->end + 1) % B->length - (B)->start - 1)

RingBuffer* RingBuffer_create(int length) {
  RingBuffer* buffer = (RingBuffer*)calloc(1, sizeof(RingBuffer));
  // Log("sizeof(RingBuffer)=%d\n", sizeof(RingBuffer));
  buffer->start = 0;
  buffer->end = 0;
  buffer->length = length;
  for (int i = 0; i < length; ++i) {
    buffer->buffer[i] = (char*)calloc(1, BUFFER_LEN);
  }
  return buffer;
}

size_t RingBuffer_write(RingBuffer* buffer, char* data) {
  if (RingBuffer_available_data(buffer) == 0) {
    buffer->start = buffer->end = 0;
  }
  // Log("Start:%d, End:%d\n", buffer->start, buffer->end);
  size_t len = sizeof(data);
  // Log("data=%s", data);
  void* result = strcpy(buffer->buffer[buffer->end], data);
  assert(result != NULL);  // Failed to write data into buffer.
  buffer->end = (buffer->end == buffer->length - 1) ? 0 : buffer->end + 1;
  buffer->start =
      (buffer->start == buffer->end)
          ? ((buffer->start == buffer->length - 1) ? 0 : buffer->start + 1)
          : buffer->start;
  // RingBuffer_commit_write(buffer, length);
  return len;
}

size_t RingBuffer_read(RingBuffer* buffer, char* target, int n) {
  size_t len = sizeof(buffer->buffer[n]);
  void* result = strcpy(target, buffer->buffer[n]);
  assert(result != NULL);  // Failed to write buffer into data
  return len;
}

void RingBuffer_show(RingBuffer* buffer) {
  if(buffer->start == buffer -> end){
    Log("Ringbuffer no element.");
    return;
  }
  char* str = (char*)calloc(1, BUFFER_LEN);
  // Log("start:%d, end:%d",buffer->start, buffer->end);
  for (int i = buffer->start; i != buffer->end;) {
    // Log("i:%d",i);
    size_t len = RingBuffer_read(buffer, str, i);
    assert(len != 0);
    Log("%s", str);
    i++;
    if (i == buffer->length) {
      i = 0;
    }
  }
  // size_t len = RingBuffer_read(buffer, str, buffer->end);
  // assert(len!=0);
  // char* strarr = "-->";
  // strarr = strcat(strarr, str);
  // Log("%s", strarr);
  free(str);
}


void init_MRB() {
  MRB = RingBuffer_create(MRB_LENGTH);
  // Log("MRB Initialized.\n");
}

void init_IRB() {
  IRB = RingBuffer_create(IRB_LENGTH);
  // Log("IRB Initialized.\n");
}

void init_FRB() {
  FRB = RingBuffer_create(FRB_LENGTH);
  // Log("FRB Initialized.\n");
}
#endif