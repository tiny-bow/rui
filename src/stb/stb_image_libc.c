
#include <stddef.h>

extern void *rui_c_alloc(size_t size);
#define STBI_MALLOC(sz) rui_c_alloc(sz)
#define STBIW_MALLOC(sz) rui_c_alloc(sz)

extern void rui_c_free(void *ptr);
#define STBI_FREE(p) rui_c_free(p)
#define STBIW_FREE(p) rui_c_free(p)

extern void *rui_c_realloc_sized(void *ptr, size_t oldsize, size_t newsize);
#define STBI_REALLOC_SIZED(p,oldsz,newsz) rui_c_realloc_sized(p,oldsz,newsz)
#define STBIW_REALLOC_SIZED(p,oldsz,newsz) rui_c_realloc_sized(p,oldsz,newsz)

extern void rui_c_panic(char const *msg);
#define STBI_ASSERT(_Assertion)                         \
  do {                                                  \
    if ((_Assertion) == 0)                              \
      rui_c_panic("Assertion " #_Assertion " failed!"); \
  } while (0)

#define STBIW_ASSERT(_Assertion)                         \
  do {                                                  \
    if ((_Assertion) == 0)                              \
      rui_c_panic("Assertion " #_Assertion " failed!"); \
  } while (0)

static int strcmp(const char *l, const char *r)
{
	for (; *l==*r && *l; l++, r++);
	return *(unsigned char *)l - *(unsigned char *)r;
}

static int strncmp(const char *_l, const char *_r, size_t n)
{
	const unsigned char *l=(void *)_l, *r=(void *)_r;
	if (!n--) return 0;
	for (; *l && *r && n && *l == *r ; l++, r++, n--);
	return *l - *r;
}

static int abs(int a)
{
	return a>0 ? a : -a;
}

extern double rui_c_pow(double x, double y);
static double pow(double x, double y)
{
    return rui_c_pow(x, y);
}

extern void *rui_c_memset(void *dest, int x, size_t n);
static void *memset(void * dest, int x, size_t n) {
	return rui_c_memset(dest, x, n);
}

extern void *rui_c_memcpy(void *dest, const void * src, size_t n);
static void *memcpy(void * dest, const void * src, size_t n) {
	return rui_c_memcpy(dest, src, n);
}

extern void *rui_c_memmove(void *dest, const void * src, size_t n);
#define STBIW_MEMMOVE(dest, src, n) rui_c_memmove(dest, src, n)
