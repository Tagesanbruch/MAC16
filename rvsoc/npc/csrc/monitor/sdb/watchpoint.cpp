/***************************************************************************************
 * Copyright (c) 2014-2022 Zihao Yu, Nanjing University
 *
 * NEMU is licensed under Mulan PSL v2.
 * You can use this software according to the terms and conditions of the Mulan PSL v2.
 * You may obtain a copy of Mulan PSL v2 at:
 *          http://license.coscl.org.cn/MulanPSL2
 *
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
 * EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
 * MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 *
 * See the Mulan PSL v2 for more details.
 ***************************************************************************************/

#include "sdb.h"
#include <common.h>
#include <debug.h>
#define NR_WP 32

typedef struct watchpoint
{
  int NO;
  struct watchpoint *next;
  char expression[32];
  uint32_t exprval;
  int used;
  /* TODO: Add more members if necessary */

} WP;

static WP wp_pool[NR_WP] = {};
static WP *head = NULL, *free_ = NULL;

void init_wp_pool()
{
  int i;
  for (i = 0; i < NR_WP; i++)
  {
    wp_pool[i].NO = i;
    wp_pool[i].next = (i == NR_WP - 1 ? NULL : &wp_pool[i + 1]);
    memset(wp_pool[i].expression , 0, 32);
    wp_pool[i].exprval = 0;
    wp_pool[i].used = 0;
  }
  head = NULL;
  free_ = wp_pool;
}

WP *new_wp()
{
  if (free_ == NULL)
  {
    assert(0);
  }
  head = free_;
  memset(head->expression, 0, sizeof(head->expression));
  head->exprval = 0;
  head->used = 1;
  free_ = free_->next;
  return head;
}

void free_wp(int no)
{
  if(no < 0 || no > NR_WP){
    assert(0);
  }
  WP wp = wp_pool[no];
  
  if(wp.used == 0){
    Log("Watchpoint %d was already unused.\n", no);
    return;
  }
  for (int i = 0; i < NR_WP; i++)
  {
    if(wp_pool[i].next == &wp){
      wp_pool[i].next = wp.next;
      break;
    }
  }
  wp_pool[no].next = free_;
  wp_pool[no].used = 0;
  memset(wp_pool[no].expression, 0, 32);
  wp_pool[no].exprval = 0;
  free_ = &wp_pool[no];
  Log("Watchpoint %d is freed successfully.\n", no);
}

int add_wp(char *e, bool *success)
{
  WP *wp_new = new_wp();
  if(wp_new == NULL){
    assert(0);
  }
  strcpy(wp_new->expression, e);
  wp_new->exprval = expr(e, success);
  head = wp_new;
  *success = true;
  return wp_new->NO;
}

void print_wp(){
  printf("Num     What                Value\n");
  bool success = 1;
  for(int i = 0; i < NR_WP; ++i){
    if(wp_pool[i].used == 0)continue;
    wp_pool[i].exprval = expr(wp_pool[i].expression, &success);
    printf("%-8d %-20s %-8u\n", wp_pool[i].NO, wp_pool[i].expression, wp_pool[i].exprval);
  }
}
static int first_update = 0;

int update_wp(word_t* pre, bool *success){
  int flag = 0;
  for(int i = 0; i < NR_WP;i++){
    if(wp_pool[i].used == 0) continue;
    wp_pool[i].exprval = expr(wp_pool[i].expression, success);
    if(*(pre+i) != wp_pool[i].exprval){
      flag = 1;//some eval changes
    }
    *(pre+i) = wp_pool[i].exprval;
  }
  if(first_update == 0){
    first_update = 1;
    flag = 0;
  }
  *success = true;
  // print_wp();
  return flag;
}