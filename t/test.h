#define DEFINED_CONSTANT 10

enum {
  ENUMERATED_CONSTANT = 20
};

static const int STATIC_CONSTANT = 30;

struct point
{
  int x, y;
};

struct msghdr
{
  int cmd;
  char vers;
  /* hope there's a hole here */
};
