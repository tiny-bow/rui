
#include <stddef.h>

extern void *rui_c_alloc(size_t size);
#define STBTT_malloc(x,u)  ((void)(u),rui_c_alloc(x))
extern void rui_c_free(void *ptr);
#define STBTT_free(x,u)    ((void)(u),rui_c_free(x))

extern void rui_c_panic(char const *msg);
#define STBTT_assert(_Assertion)                         \
  do {                                                  \
    if ((_Assertion) == 0)                              \
      rui_c_panic("Assertion " #_Assertion " failed!"); \
  } while (0)

extern double rui_c_floor(double x);
#define STBTT_ifloor(x)   ((int) rui_c_floor(x))
extern double rui_c_ceil(double x);
#define STBTT_iceil(x)    ((int) rui_c_ceil(x))

extern double rui_c_sqrt(double x);
#define STBTT_sqrt(x)      rui_c_sqrt(x)
extern double rui_c_pow(double x, double y);
#define STBTT_pow(x,y)     rui_c_pow(x,y)

extern double rui_c_fmod(double x, double y);
#define STBTT_fmod(x,y)    rui_c_fmod(x,y)

extern double rui_c_cos(double x);
#define STBTT_cos(x)       rui_c_cos(x)
extern double rui_c_acos(double x);
#define STBTT_acos(x)      rui_c_acos(x)

extern double rui_c_fabs(double x);
#define STBTT_fabs(x)      rui_c_fabs(x)

extern size_t rui_c_strlen(const char * str);
#define STBTT_strlen(x)      rui_c_strlen(x)

extern void *rui_c_memcpy(void *dest, const void * src, size_t n);
#define STBTT_memcpy(dest, src, n)      rui_c_memcpy(dest, src, n)
extern void *rui_c_memset(void *dest, int x, size_t n);
#define STBTT_memset(dest, x, n)      rui_c_memset(dest, x, n)

