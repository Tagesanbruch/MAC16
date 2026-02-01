#ifndef TRACE_H
#define TRACE_H

#include <common.h>
#include <debug.h>
#define BUFFER_LEN 256

typedef struct {
  char* buffer[BUFFER_LEN];
  int start;
  int end;
  int length;
} RingBuffer;

RingBuffer* RingBuffer_create(int length);

size_t RingBuffer_write(RingBuffer* buffer, char* data);

size_t RingBuffer_read(RingBuffer* buffer, char* target, int n);

void RingBuffer_show(RingBuffer* buffer);

#endif