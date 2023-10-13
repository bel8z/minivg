#include <stdlib.h>

// TODO (Matteo): Provide allocation functions

// extern void *exportMalloc(size_t size);
// extern void *exportRealloc(void *ptr, size_t size);
// extern void exportFree(void *ptr);

// #define FONS_MALLOC exportMalloc
// #define FONS_REALLOC exportRealloc
// #define FONS_FREE exportFree
#define FONS_NO_STDIO 1
#define FONTSTASH_IMPLEMENTATION
#include <fontstash.h>

// #define STBI_ASSERT exportAssert
// #define STBI_MALLOC exportMalloc
// #define STBI_REALLOC exportRealloc
// #define STBI_FREE exportFree
#define STBI_NO_STDIO 1
#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>

// #define LAY_REALLOC exportRealloc
// #define LAY_MEMSET exportMemset
#define LAY_FLOAT 1
#define LAY_IMPLEMENTATION
#include <layout.h>