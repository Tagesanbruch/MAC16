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
#include <debug.h>
#include <memory/paddr.h>
#include <regex.h>

#define LOGD \
  if (DEBUG) \
  Log
#define LOGD2 \
  if (DEBUG2) \
  Log
static int DEBUG = 0;
static int DEBUG2 = 0;
enum {
  TK_NOTYPE = 256,
  TK_EQ,
  TK_UEQ,
  TK_AND,
  TK_DEC,
  TK_HEX,
  TK_REG,
  DEREF
};
word_t isa_reg_str2val(const char *s, bool *success);
int atoi(const char* nptr) {
  int x = 0;
  while (*nptr == ' ') {
    nptr++;
  }
  while (*nptr >= '0' && *nptr <= '9') {
    x = x * 10 + *nptr - '0';
    nptr++;
  }
  return x;
}

word_t paddr_read(paddr_t addr, int len);
static struct rule {
  const char* regex;
  int token_type;
} rules[] = {
    {" +", TK_NOTYPE},              // spaces
    {"0[xX][0-9a-fA-F]+", TK_HEX},  // heximal
    {"\\$[0-9a-zA-Z]+", TK_REG},    // register
    {"[0-9]+", TK_DEC},             // decimal
    {"\\+", '+'},                   // plus
    {"\\-", '-'},                   // minus
    {"\\*", '*'},                   // multiply
    {"\\/", '/'},                   // divide
    {"\\(", '('},                   // left quote
    {"\\)", ')'},                   // right quote
    {"==", TK_EQ},                  // equal
    {"!=", TK_UEQ},                 // unequal
    {"&&", TK_AND},                 // and
};

#define NR_REGEX ARRLEN(rules)
static regex_t re[NR_REGEX] = {};

void init_regex() {
  int i;
  char error_msg[128];
  int ret;

  for (i = 0; i < NR_REGEX; i++) {
    ret = regcomp(&re[i], rules[i].regex, REG_EXTENDED);
    if (ret != 0) {
      regerror(ret, &re[i], error_msg, 128);
      panic("regex compilation failed: %s\n%s", error_msg, rules[i].regex);
    }
  }
}

#define TOKEN_LEN 128
#define TOKEN_NUM 65536

typedef struct token {
  int type;
  char str[TOKEN_LEN];
} Token;

static Token tokens[TOKEN_NUM] __attribute__((used)) = {};
static int nr_token __attribute__((used)) = 0;

static bool make_token(char* e, int* len) {
  for (int i = 0; i < TOKEN_NUM; ++i) {
    tokens[i].type = 0;
    memset(tokens[i].str, 0, TOKEN_LEN);
  }
  int position = 0;
  int cnt = 0;
  int cnt_t = 0;
  int i;
  regmatch_t pmatch;

  nr_token = 0;

  while (e[position] != '\0') {
    /* Try all rules one by one. */
    for (i = 0; i < NR_REGEX; i++) {
      if (regexec(&re[i], e + position, 1, &pmatch, 0) == 0 &&
          pmatch.rm_so == 0) {
        char* substr_start = e + position;
        int substr_len = pmatch.rm_eo;
        position += substr_len;
        switch (rules[i].token_type) {
          case TK_NOTYPE:
            break;
          case TK_HEX: {
            cnt++;
            word_t tmp_hex;
            sscanf(substr_start, "%x", &tmp_hex);
            tokens[cnt_t].type = TK_HEX;
            sprintf(tokens[cnt_t].str, "%u", tmp_hex);
            LOGD("tokens[%d].str=%s\n", cnt_t, tokens[cnt_t].str);
            cnt_t++;
          } break;
          case TK_DEC: {
            cnt++;
            tokens[cnt_t].type = TK_DEC;
            strncpy(tokens[cnt_t].str, substr_start, substr_len);
            LOGD("tokens[%d].str=%s\n", cnt_t, tokens[cnt_t].str);
            cnt_t++;
            break;
          }
          case TK_REG: {
            cnt++;
            tokens[cnt_t].type = TK_REG;
            strncpy(tokens[cnt_t].str, substr_start + 1, substr_len - 1);
            bool success;
            LOGD("tokens[%d].str=%s\n", cnt_t, tokens[cnt_t].str);
            word_t regval = isa_reg_str2val(tokens[cnt_t].str, &success);
            // word_t regval = 0;
            // Log("not complete implemented...");
            if (success) {
              sprintf(tokens[cnt_t].str, "%u", regval);
            } else {
              sprintf(tokens[cnt_t].str, "%u", 0xFFFF);
            }
            cnt_t++;
          } break;
          case '+': {
            cnt++;
            tokens[cnt_t].type = '+';
            cnt_t++;
          } break;
          case '-': {
            cnt++;
            tokens[cnt_t].type = '-';
            cnt_t++;
          } break;
          case '*': {
            cnt++;
            if (cnt_t == 0 || tokens[cnt_t - 1].type == '+' ||
                tokens[cnt_t - 1].type == '-' ||
                tokens[cnt_t - 1].type == '*' ||
                tokens[cnt_t - 1].type == '/' ||
                tokens[cnt_t - 1].type == TK_EQ ||
                tokens[cnt_t - 1].type == TK_UEQ ||
                tokens[cnt_t - 1].type == TK_AND ||
                tokens[cnt_t - 1].type == '(') {
              tokens[cnt_t].type = DEREF;
            } else {
              tokens[cnt_t].type = '*';
            }
            cnt_t++;
          } break;
          case '/': {
            cnt++;
            tokens[cnt_t].type = '/';
            cnt_t++;
          } break;
          case '(': {
            cnt++;
            tokens[cnt_t].type = '(';
            cnt_t++;
          } break;
          case ')': {
            cnt++;
            tokens[cnt_t].type = ')';
            cnt_t++;
          } break;
          case TK_EQ: {
            cnt++;
            tokens[cnt_t].type = TK_EQ;
            cnt_t++;
          } break;
          case TK_UEQ: {
            cnt++;
            tokens[cnt_t].type = TK_UEQ;
            cnt_t++;
          } break;
          case TK_AND: {
            cnt++;
            tokens[cnt_t].type = TK_AND;
            cnt_t++;
          } break;
          default:
            printf("no rules for token %d\n", i);
        }

        break;
      }
    }

    if (i == NR_REGEX) {
      printf("no match at position %d\n%s\n%*.s^\n", position, e, position, "");
      return false;
    }
  }
  *len = cnt;
  return true;
}

int priority(int op) {
  if (op == TK_EQ || op == TK_UEQ || op == TK_AND)
    return 0;
  if (op == '+' || op == '-')
    return 1;
  if (op == '*' || op == '/')
    return 2;
  if (op == DEREF)
    return 3;
  return -1;
}

int mainop(int p, int q) {
  int prior = 3;
  int pos = 0;
  int hes = 0;
  for (int i = p; i <= q; i++) {
    if (tokens[i].type == '+' || tokens[i].type == '-' ||
        tokens[i].type == '*' || tokens[i].type == '/' ||
        tokens[i].type == TK_EQ || tokens[i].type == TK_UEQ ||
        tokens[i].type == TK_AND || tokens[i].type == DEREF) {
      if (hes > 0)
        continue;
      int prior_tmp = priority(tokens[i].type);
      if (prior >= prior_tmp) {
        prior = prior_tmp;
        pos = i;
      }
    } else if (tokens[i].type == '(') {
      hes++;
    } else if (tokens[i].type == ')') {
      if (hes == 0) {
        assert(0);
      }
      hes--;
    } else {
      continue;
    }
  }
  if (hes > 0) {
    assert(0);
  }
  return pos;
}

bool check_parentheses(int p, int q) {
  int len = q - p + 1;
  char stack[len];
  int top = -1;
  for (int i = p; i < q + 1; ++i) {
    if (tokens[i].type == '(') {
      stack[++top] = '(';
    } else if (tokens[i].type == ')') {
      if (top == -1 || stack[top] != '(') {
        return false;  // false
      } else {
        --top;
      }
    }
  }
  return true;  // true, existing heses
}

word_t eval(int p, int q, bool* success) {
  bool success_tmp = false;
  *success = true;
  if (p > q) {
    // Bad expression
    printf("Invalid eval input.\n");
    *success = false;
    return 0;
  } else if (p == q) {
    return atoi(tokens[p].str);
  }
  if (check_parentheses(p, q) == false) {
    printf("Invalid eval input.\n");
    *success = false;
    return 0;
  } else if ((tokens[p].type == '(' && tokens[q].type == ')') &&
             check_parentheses(p + 1, q - 1) == true) {
    LOGD2("heses reduced.\n");
    return eval(p + 1, q - 1, &success_tmp);
  } else {
    int op = 0;
    word_t val1 = 0;
    word_t val2 = 0;
    op = mainop(p, q);  // position of main operator
    LOGD2("Mainop=%d, p=%d, q=%d\n", op, p, q);
    if (tokens[op].type == DEREF) {
      val1 = eval(op + 1, q, &success_tmp);
      return paddr_read(val1, 4);
    }
    val1 = eval(p, op - 1, &success_tmp);
    val2 = eval(op + 1, q, &success_tmp);
    switch (tokens[op].type) {
      case '+':
        return val1 + val2;
      case '-':
        return val1 - val2;
      case '*':
        return val1 * val2;
      case '/':
        if (val2 != 0) {
          return val1 / val2;
        } else {
          // Log("Warning:divided by 0.\n");
          // return __INT32_MAX__;
          assert(0);
        }
      case TK_AND:
        return val1 && val2;
      case TK_EQ:
        return (val1 == val2);
      case TK_UEQ:
        return (val1 != val2);
      default:
        assert(0);
    }
  }
}

word_t expr(char* e, bool* success) {
  int len_token = 0;
  *success = true;
  if (!make_token(e, &len_token)) {
    *success = false;
    return 0;
  }
  for (int i = 0; i < len_token; i++) {
    LOGD2("Token[%d].type=%d, Token[%d].str=%s\n", i, tokens[i].type, i,
          tokens[i].str);
  }
  word_t val = eval(0, len_token - 1, success);
  if (*success == true) {
    return val;
  } else {
    printf("expression error.\n");
  }
  return 0;
}
