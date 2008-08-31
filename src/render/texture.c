/*
 * texture mapping routine.
 *
 * texture.c contains texture filtering codes.
 * Loading texture data is coded in texture_loader.c.
 *
 * $Id$
 *
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>


#ifdef HAVE_ZLIB
#include <zlib.h>        /* Blocked texture is saved with zlib comporession. */
#endif

#include "memory.h"
#include "log.h"
#include "texture.h"
#include "hash.h"
#include "render.h"

#define TEXBLOCKSIZE 64        /* block map size in miplevel 0. */
#define MAXMIPLEVEL  16        /* 16 can represent a mipmap for 65536x65536. */

typedef struct _texblock_t
{
    int          x, y;        /* upper-left position in original texture map. 
                               * (in miplevel 0)
                               */

    ri_vector_t *image;

} texblock_t;

typedef struct _blockedmipmap_t
{
    int nmiplevels;             /* The number of mipmap levels              */

    int width, height;          /* Original texture size                    */

    int nxblocks, nyblocks;     /* The number of texture blocks.
                                 * Counted in miplevel 0.
                                 * Thus e.g. miplevel 1 contains
                                 * (nxblocks/2) * (nyblocks/2) texture blocks.
                                 */

    texblock_t *blocks[MAXMIPLEVEL];    /* list of texture blocks
                                         * in each miplevel.
                                         */

} blockedmipmap_t;

//#define LOCAL_DEBUG
#undef LOCAL_DEBUG
#define USE_ZORDER 0

#define MAX_TEXTURE_PATH 1024

/* input x and y must be up to 2^16 */
#define MAP_Z2D(x, y) ((unsigned int)(g_z_table[(x) & 0xFF] | \
               (g_z_table[(y) & 0xFF] << 1)) | \
               ((unsigned int)((g_z_table[((x) >> 8) & 0xFF]) | \
                (g_z_table[((y) >> 8) & 0xFF] << 1)) << 16))

/* table for z curve order */
static unsigned short g_z_table[256];

static ri_hash_t    *texture_cache;
static FILE         *open_file(const char *filename);

/* store texel memory in scanline order -> z curve order. */ 
static void remapping(ri_texture_t *src);
static void build_z_table();


void
ri_texture_fetch(
    ri_vector_t         color_out,      /* [out] */
    const ri_texture_t *texture,
    ri_float_t          u,
    ri_float_t          v)
{
    int         i;
    int         idx;
    int         x, y;
    ri_float_t sx, sy;
    ri_float_t w[4];
    ri_float_t texel[4][4];
    ri_float_t px, py;
    ri_float_t dx, dy;

    sx = floor(u); sy = floor(v);

    u = u - sx; v = v - sy;

    if (u < 0.0) u = 0.0; if (u >= 1.0) u = 1.0;
    if (v < 0.0) v = 0.0; if (v >= 1.0) v = 1.0;

    px = u * (texture->width  - 1);
    py = v * (texture->height  - 1);

    x = (int)px; y = (int)py;

    dx = px - x; dy = py - y;

    w[0] = (1.0 - dx) * (1.0 - dy);
    w[1] = (1.0 - dx) *        dy ;
    w[2] =        dx  * (1.0 - dy);
    w[3] =        dx  *        dy ;

#if USE_ZORDER

    idx = MAP_Z2D(x, y);
    texel[0][0] = texture->data[4 * idx + 0];
    texel[0][1] = texture->data[4 * idx + 1];
    texel[0][2] = texture->data[4 * idx + 2];
    texel[0][3] = texture->data[4 * idx + 3];

    if (y < texture->height - 1 && x < texture->width - 1) {
        idx = MAP_Z2D(x, y+1);
        texel[1][0] = texture->data[4 * idx + 0];
        texel[1][1] = texture->data[4 * idx + 1];
        texel[1][2] = texture->data[4 * idx + 2];
        texel[1][3] = texture->data[4 * idx + 3];

        idx = MAP_Z2D(x+1, y);
        texel[2][0] = texture->data[4 * idx + 0];
        texel[2][1] = texture->data[4 * idx + 1];
        texel[2][2] = texture->data[4 * idx + 2];
        texel[2][3] = texture->data[4 * idx + 3];

        idx = MAP_Z2D(x+1, y+1);
        texel[3][0] = texture->data[4 * idx + 0];
        texel[3][1] = texture->data[4 * idx + 1];
        texel[3][2] = texture->data[4 * idx + 2];
        texel[3][3] = texture->data[4 * idx + 3];
    } else if (y < texture->height - 1) {
        idx = MAP_Z2D(x, y+1);
        texel[1][0] = texture->data[4 * idx + 0];
        texel[1][1] = texture->data[4 * idx + 1];
        texel[1][2] = texture->data[4 * idx + 2];
        texel[1][3] = texture->data[4 * idx + 3];

        for (i = 0; i < 4; i++) {
            texel[2][i] = 0.0;
            texel[3][i] = 0.0;
        }
    } else if (x < texture->width - 1) {
        idx = MAP_Z2D(x+1, y);
        texel[2][0] = texture->data[4 * idx + 0];
        texel[2][1] = texture->data[4 * idx + 1];
        texel[2][2] = texture->data[4 * idx + 2];
        texel[2][3] = texture->data[4 * idx + 3];

        for (i = 0; i < 4; i++) {
            texel[1][i] = 0.0;
            texel[3][i] = 0.0;
        }
    } else {
        for (i = 0; i < 4; i++) {
            texel[1][i] = 0.0;
            texel[2][i] = 0.0;
            texel[3][i] = 0.0;
        }
    }    

#else

    idx = y * texture->width + x;
    for (i = 0; i < 4; i++) {
        texel[0][i] = texture->data[4 * idx + i];
    }

    if (y < texture->height - 1 && x < texture->width - 1) {
        idx = (y + 1) * texture->width + x;
        for (i = 0; i < 4; i++) {
            texel[1][i] = texture->data[4 * idx + i];
        }

        idx = y * texture->width + x + 1;
        for (i = 0; i < 4; i++) {
            texel[2][i] = texture->data[4 * idx + i];
        }

        idx = (y + 1) * texture->width + x + 1;
        for (i = 0; i < 4; i++) {
            texel[3][i] = texture->data[4 * idx + i];
        }
    } else if (y < texture->height - 1) {
        idx = (y + 1) * texture->width + x;
        for (i = 0; i < 4; i++) {
            texel[1][i] = texture->data[4 * idx + i];
        }

        for (i = 0; i < 4; i++) {
            texel[2][i] = 0.0;
            texel[3][i] = 0.0;
        }
    } else if (x < texture->width - 1) {
        idx = y * texture->width + x + 1;
        for (i = 0; i < 4; i++) {
            texel[2][i] = texture->data[4 * idx + i];
        }

        for (i = 0; i < 4; i++) {
            texel[1][i] = 0.0;
            texel[3][i] = 0.0;
        }
    } else {
        for (i = 0; i < 4; i++) {
            texel[1][i] = 0.0;
            texel[2][i] = 0.0;
            texel[3][i] = 0.0;
        }
    }    

#endif
   
    for (i = 0; i < 4; i++) {
        color_out[i] = (ri_float_t)(
                  w[0] * texel[0][i] +
                  w[1] * texel[1][i] +
                  w[2] * texel[2][i] +
                  w[3] * texel[3][i]);
    }
}

void
ri_texture_ibl_fetch(
    ri_vector_t         color_out,
    const ri_texture_t *texture,
    const ri_vector_t   dir)
{
    const ri_float_t pi = 3.1415926535;
    ri_float_t u, v;
    ri_float_t r;
    ri_float_t norm2;
    ri_vector_t ndir;

    ri_vector_copy(ndir, dir);
    ri_vector_normalize(ndir);

    if (ndir[2] >= -1.0 && ndir[2] < 1.0) {
        /* Angular Map is defined in left-handed coordinate,
         * RenderMan is defined in right-handed coordinate(default).
         * +z in dir corresponds to -z in angular map coord.
         * (actually, no sign flipping occur in this case)
         * TODO: consider ribs which defined the coords in left-handed.
         */
        r = (1.0 / pi) * acos(ndir[2]);
    } else {
        r = 0.0;
    }

    norm2 = ndir[0] * ndir[0] + ndir[1] * ndir[1];
    if (norm2 > 1.0e-6) {
        r /= sqrt(norm2);
    }
    
    u = ndir[0] * r;
    v = ndir[1] * r;

    u = 0.5 * u + 0.5;
    v = 0.5 - 0.5 * v;

    ri_texture_fetch(color_out, texture, u, v);
}

void
ri_texture_scale(ri_texture_t *texture, ri_float_t scale)
{
    int i;

    for (i = 0; i < texture->width * texture->height * 4; i++) {
        texture->data[i] *= scale;
    }
}


static void
build_z_table()
{
    unsigned int   i, j;
    unsigned int   bit;
    unsigned int   v;
    unsigned int   ret;
    unsigned int   mask = 0x1;
    int            shift;

    for (i = 0; i < 256; i++) {
        v = i;
        shift = 0;
        ret = 0;
        for (j = 0; j < 8; j++) {
            /* extract (j+1)'th bit */
            bit = (v >> j) & mask;

            ret += bit << shift;
            shift += 2;
        }

        g_z_table[i] = (unsigned short)ret;
    }
}

static void
remapping(ri_texture_t *src)
{
    unsigned int x, y;
    unsigned int i;
    unsigned int pow2n;
    unsigned int maxpixlen;
    unsigned int idx;
    ri_float_t        *newdata;

    if (src->width > src->height) {
        maxpixlen = src->width;
    } else {
        maxpixlen = src->height;
    } 

    /* find nearest 2^n value against maxpixlen.
     * I think there exists more sofisticated way for this porpose ...
     */
    pow2n = 1;
    for (i = 1; i < maxpixlen; i++) {
        if (maxpixlen <= pow2n) break;
        pow2n *= 2;
    }
    
    src->maxsize_pow2n = pow2n;

#ifdef LOCAL_DEBUG
    fprintf(stderr, "width = %d, height = %d\n", src->width, src->height);
    fprintf(stderr, "maxsize_pow2n = %d\n", src->maxsize_pow2n);
#endif

    newdata = (ri_float_t *)ri_mem_alloc(4 * sizeof(ri_float_t) *
                    src->maxsize_pow2n *
                    src->maxsize_pow2n);

    if (src->maxsize_pow2n > 65536) {
        fprintf(stderr,
            "texture size must be < 65536. maxsize_pow2n = %d\n",
            src->maxsize_pow2n);
        exit(-1);
    }

    for (i = 0;
         i < (unsigned int)(4 * src->maxsize_pow2n * src->maxsize_pow2n);
         i++) {
        newdata[i] = 0.0;
    }

    for (y = 0; y < (unsigned int)src->height; y++) {
        for (x = 0; x < (unsigned int)src->width; x++) {
            /* compute z curve order index for (x, y). */
            idx = MAP_Z2D(x, y);
#ifdef LOCAL_DEBUG
            fprintf(stderr, "(%d, %d) = %d\n", x, y, idx);
#endif

            newdata[4 * idx + 0] =
                src->data[4 *(y * src->width + x) + 0];
            newdata[4 * idx + 1] =
                src->data[4 *(y * src->width + x) + 1];
            newdata[4 * idx + 2] =
                src->data[4 *(y * src->width + x) + 2];
            newdata[4 * idx + 3] =
                src->data[4 *(y * src->width + x) + 3];
        }
    }    

    ri_mem_free(src->data);

    src->data = newdata;
}

void
make_texture(ri_rawtexture_t *rawtex)
{
    int s, t;
    int i;
    int blocksize = 0;

    int nxblocks = 0;    // Number of blocks in x-direction
    int nyblocks = 0;    // Number of blocks in y-direction

    ri_vector_t *image[MAXMIPLEVEL];    // block map images.
    
    for (i = 0; i < blocksize; i++) {
        blocksize = TEXBLOCKSIZE >> i;
        image[i] = (ri_vector_t *)ri_mem_alloc(sizeof(ri_vector_t) *
                blocksize * blocksize);
    }

    nxblocks = (int)ceil(rawtex->width / TEXBLOCKSIZE);
    nyblocks = (int)ceil(rawtex->height / TEXBLOCKSIZE);

    printf("w, h = %d, %d. nxblk, nyblk = %d, %d\n",
        rawtex->width, rawtex->height, nxblocks, nyblocks);

    for (t = 0; t < nyblocks; t++) {
        for (s = 0; s < nxblocks; s++) {

        }
    }
    
    
}

// Generate blocked mipmap from raw texture map.
// TODO: implement.
static blockedmipmap_t *
gen_blockedmipmap(const char *filename, ri_rawtexture_t *texture)
{
    int i;
    int w, h;
    int xblocks, yblocks;
    int miplevels;
    int minsize;
    int u, v;

    w = texture->width; h = texture->height;

    xblocks = (int)ceil(w / TEXBLOCKSIZE);
    yblocks = (int)ceil(h / TEXBLOCKSIZE);

    ri_log(LOG_INFO, "texsize = (%d, %d). blocks = (%d, %d)\n",
        w, h, xblocks, yblocks);

    minsize = (w < h) ? w : h;
    miplevels = (int)ceil(log((ri_float_t)minsize) / log(2.0));

    ri_log(LOG_INFO, "miplevels = %d\n", miplevels);

    for (i = 0; i < miplevels; i++) {

        for (v = 0; v < yblocks; v++) {
            for (u = 0; u < xblocks; u++) {
                
            }
        }

    }
    
    return NULL;    // not yet implemented.
}

#if 0 // TODO

// Write mipmap to disk with zlib compression.
static void
write_blockedmipmap(const char *filename, blockedmipmap_t *blkmipmap)
{
    int i, j;
    int u, v;
    int size;
    int xblocks, yblocks;

    gzFile *fp;
    
    fp = gzopen(filename, "wb");
    if (!fp) {
        
        ri_log(LOG_ERROR, "Can't write file [%s]", filename);
    }

    // Write header
    gzwrite(fp, &blkmipmap->nmiplevels, sizeof(int));
    gzwrite(fp, &blkmipmap->width, sizeof(int));
    gzwrite(fp, &blkmipmap->height, sizeof(int));
    gzwrite(fp, &blkmipmap->nxblocks, sizeof(int));
    gzwrite(fp, &blkmipmap->nyblocks, sizeof(int));
    
    size = sizeof(ri_float_t) * TEXBLOCKSIZE * TEXBLOCKSIZE;
    
    for (i = 0; i < blkmipmap->nmiplevels; i++) {

        xblocks = blkmipmap->nxblocks >> i;
        yblocks = blkmipmap->nyblocks >> i;

        for (v = 0; v < yblocks; v++) {
            for (u = 0; u < xblocks; u++) {

                j = v * xblocks + u;

                // Write texture block.
                gzwrite(fp, blkmipmap->blocks[i][j].image,
                    size);

            }
        }

    }

    gzclose(fp);
}
#endif
