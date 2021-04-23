#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION

#include <iostream>
#include <ctime>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <climits>
#include <string>
#include <math.h>
#include <time.h>
#include <chrono> 
#include "define.h"
#include <cuda_runtime.h>
#include <curand_kernel.h>
#include <curand.h>

using namespace std;

#include "stb_image.h"
#include "stb_image_write.h"

#define ENABLE_TIMER 1

__device__ __host__ int MAX(int a, int b) {
  if (a > b){
    return a;
  }
  return b;
}
__device__ __host__ int MIN(int a, int b) {
  if (a < b){
    return a;
  }
  return b;
}

__device__ __host__ unsigned char* get_RGB(unsigned char* img_pixels, int img_no, int row, int col, int nchannels, int h, int w){
  unsigned bytePerPixel = nchannels;
  unsigned char* pixelOffset = img_pixels + (h*w*img_no + (row*w + col)) * bytePerPixel;
  return pixelOffset;
}

__device__ __host__ void storeXYasRGB(unsigned char* offset, int bx, int by, int bz)
{
    offset[0] = bx;
    offset[1] = by;
    offset[2] = bz;
}


__device__ __host__ void storeintasRGBA(unsigned char* offset, int tostore)
{
    offset[3] = tostore&0xff;
    offset[2] = (tostore&0xff00)>>8;
    offset[1] = (tostore&0xff0000)>>16;
    offset[0] = (tostore&0xff000000)>>24;
}

__device__ __host__ int dist1(unsigned char *a, unsigned char *b, int ax, int ay, int az, int bx, int by, int bz, int pw, int h, int w, int cutoff=INT_MAX) {
  // printf("PW %d\n", pw);
  int ans = 0;
  for (int dz = 0; dz < pw; dz ++) {
    for (int dy = 0; dy < pw; dy++) {
      for (int dx = 0; dx < pw; dx++) {
        unsigned char* ac = get_RGB(a, az + dz, ay+dy, ax+dx, 3, h, w);
        unsigned char* bc = get_RGB(b, bz + dz, by+dy, bx+dx, 3, h, w);
        int dr = ac[0] - bc[0];
        int dg = ac[1] - bc[1];
        int db = ac[2] - bc[2];
        ans += dr*dr + dg*dg + db*db;
      }
    }
    if (ans >= cutoff) { return cutoff; }
    if (ans < 0){ return cutoff; }
  }
  // printf("dist being entered\n");

  return ans;
}



__device__ __host__ int dist(unsigned char *a, unsigned char *b, int ax, int ay, int az, int bx, int by, int bz, int pw, int h, int w, int cutoff=INT_MAX) {
  // printf("PW %d\n", pw);
  int ans = 0;
  for (int dz = 0; dz < pw; dz ++) {
    for (int dy = 0; dy < pw; dy++) {
      for (int dx = 0; dx < pw; dx++) {
        unsigned char* ac = get_RGB(a, az + dz, ay+dy, ax+dx, 3, h, w);
        unsigned char* bc = get_RGB(b, bz + dz, by+dy, bx+dx, 3, h, w);
        int dr = ac[0] - bc[0];
        int dg = ac[1] - bc[1];
        int db = ac[2] - bc[2];
        ans += dr*dr + dg*dg + db*db;
      }
    }
    if (ans >= cutoff) { return cutoff; }
    if (ans < 0){ return cutoff; }
  }
  // printf("dist being entered\n");

  return ans;
}


__device__ __host__ void improve_guess(unsigned char *a, unsigned char *b, int ax, int ay, int az, int &xbest, int &ybest, int &zbest, int &dbest, int bx, int by, int bz, int pw, int h, int w) {
  // printf("PW %d\n", pw);
  
  int d = dist1(a, b, ax, ay, az, bx, by, bz, pw, h, w, dbest);
  // printf("dist is updating\n");
  if (d < dbest) {
    dbest = d;
    xbest = bx;
    ybest = by;
    zbest = bz;
  }
}

__device__  __host__ int XfromRGB(unsigned char* v){
    return v[0];
}

__device__  __host__ int YfromRGB(unsigned char* v){
    return v[1];
}

__device__  __host__ int ZfromRGB(unsigned char* v){
    return v[2];
}

__device__  __host__ int netINT(unsigned char *v){
    return v[0]<<24 | v[1] << 16 | v[2] << 8 | v[3];
}


void map_patches(unsigned char *a, unsigned char *b, unsigned char *ann, unsigned char *out)
{
  int aew = w - patch_width + 1, aeh = h - patch_width + 1, aed = d - patch_width + 1;
  for (int az = 0; az < aed; az ++) {
    for (int ay = 0; ay < aeh; ay++) {
      for (int ax = 0; ax < aew; ax++) {
        unsigned char* map = get_RGB(ann, az, ay, ax, 3, h, w);
        int x = XfromRGB(map);
        int y = YfromRGB(map);
        int z = ZfromRGB(map);
        for (int dz = 0; dz < patch_width; dz ++) {
          for (int dy = 0; dy < patch_width; dy++) {
            for (int dx = 0; dx < patch_width; dx++) {
              if (z+dz >= d || y+dy >= h || x+dx >= w || az + dz >=  d || ay + dy >=  h || ax + dx >= w)
                continue;
              unsigned char* binputs = get_RGB(b, z + dz, y+dy, x+dx, 3, h, w);
              unsigned char* output = get_RGB(out, az + dz, ay+dy, ax+dx, 3, h, w);
              output[0] = binputs[0];
              output[1] = binputs[1];
              output[2] = binputs[2];
            }
          }
        }
      }
    }
  }
}


__global__ void patchmatch(unsigned char *a, unsigned char *b, unsigned char *ann_to_use, unsigned char *annd_to_use, unsigned char *other, unsigned char *annd_other, int height, int width, int depth, int pw)
{
  // printf("LAUNCHED\n");
  int ax = threadIdx.x + blockDim.x*blockIdx.x;
  int ay = threadIdx.y + blockDim.y*blockIdx.y;
  int az = threadIdx.z + blockDim.z*blockIdx.z;
  int xchange = 1;
  int ychange = 1;
  int zchange = 1;
  int aew = width - pw + 1, aeh = height - pw + 1, aed = depth - pw + 1;
  int bew = width - pw + 1, beh = height - pw + 1, bed = depth - pw + 1;

  if (ax < aew && ay < aeh && az < aed)
  {
  unsigned char* v = get_RGB(ann_to_use, az, ay, ax, 3, height, width);
  int ybest = YfromRGB(v), xbest = XfromRGB(v), zbest = ZfromRGB(v);
  int dbest = netINT(get_RGB(annd_to_use, az, ay, ax,4, height, width));



  // Propagation
  if ((unsigned) (ax - xchange) < (unsigned) aew) {
    unsigned char* vp = get_RGB(ann_to_use, az, ay, ax-xchange, 3, height, width);
    int xp = XfromRGB(vp) + xchange, yp = YfromRGB(vp), zp = ZfromRGB(vp);
    if ((unsigned) xp < (unsigned) bew) {
      improve_guess(a, b, ax, ay, az, xbest, ybest, zbest, dbest, xp, yp, zp, pw, height, width);      
    }
    
  }

  if ((unsigned) (ay - ychange) < (unsigned) aeh) {
    unsigned char* vp = get_RGB(ann_to_use, az, ay-ychange, ax, 3, height, width);
    int xp = XfromRGB(vp), yp = YfromRGB(vp) + ychange, zp = ZfromRGB(vp);
    if ((unsigned) yp < (unsigned) beh) {
      improve_guess(a, b, ax, ay, az, xbest, ybest, zbest, dbest, xp, yp, zp, pw, height, width);
    }
  }

  if ((unsigned) (az - zchange) < (unsigned) aed) {
    unsigned char* vp = get_RGB(ann_to_use, az-zchange, ay, ax, 3, height, width);
    int xp = XfromRGB(vp), yp = YfromRGB(vp), zp = ZfromRGB(vp) + zchange;
    if ((unsigned) zp < (unsigned) bed) {
      improve_guess(a, b, ax, ay, az, xbest, ybest, zbest, dbest, xp, yp, zp, pw, height, width);
    }
  }

  if ((unsigned) (ax + xchange) < (unsigned) aew) {
    unsigned char* vp = get_RGB(ann_to_use, az, ay, ax + xchange, 3, height, width);
    int xp = XfromRGB(vp) - xchange, yp = YfromRGB(vp), zp = ZfromRGB(vp);
    if ((unsigned) xp < (unsigned) bew) {
      improve_guess(a, b, ax, ay, az, xbest, ybest, zbest, dbest, xp, yp, zp, pw, height, width);
    }
  }

  if ((unsigned) (ay + ychange) < (unsigned) aeh) {
    unsigned char* vp = get_RGB(ann_to_use,az, ay + ychange, ax, 3, height, width);
    int xp = XfromRGB(vp), yp = YfromRGB(vp) - ychange, zp = ZfromRGB(vp);
    if ((unsigned) yp < (unsigned) beh) {
      improve_guess(a, b, ax, ay, az, xbest, ybest, zbest, dbest, xp, yp, zp, pw, height, width);
    }
  }

  if ((unsigned) (az + zchange) < (unsigned) aed) {
    unsigned char* vp = get_RGB(ann_to_use, az + zchange, ay, ax, 3, height, width);
    int xp = XfromRGB(vp), yp = YfromRGB(vp), zp = ZfromRGB(vp) - zchange;
    if ((unsigned) zp < (unsigned) bed) {
      improve_guess(a, b, ax, ay, az, xbest, ybest, zbest, dbest, xp, yp, zp, pw, height, width);
    }
  }

  // Propagation done!

  int rs_start = INT_MAX;
  if (rs_start > MAX(MAX(width, height), depth)) { rs_start = MAX(MAX(width, height), depth); }
  for (int mag = rs_start; mag >= 1; mag /= 2) {
    int xmin = MAX(xbest-mag, 0), xmax = MIN(xbest+mag+1,bew);
    int ymin = MAX(ybest-mag, 0), ymax = MIN(ybest+mag+1,beh);
    int zmin = MAX(zbest-mag, 0), zmax = MIN(zbest+mag+1,bed);

    int xp = xmin;
    int yp = ymin;
    int zp = zmin;

    if (xmax > xmin)
    {
      xp = xmin;
    }
    if (ymax > ymin)
    {
      yp = ymin;
    }
    if (zmax > zmin)
    {
      zp = zmin;
    }
    improve_guess(a, b, ax, ay, az, xbest, ybest, zbest, dbest, xp, yp, zp, pw, height, width);
  }

  storeXYasRGB(get_RGB(other, az, ay, ax, 3, height, width), xbest, ybest, zbest);
  storeintasRGBA(get_RGB(annd_other, az, ay, ax, 4, height, width), dbest);
}
}

double compute_error(unsigned char* output, unsigned char* a)
{
  double error = 0;

  for (int az = 0; az < d; az++) {
    for (int ay = 0; ay < h; ay++) {
      for (int ax = 0; ax < w; ax++){
        unsigned char* pixelOffset = get_RGB(output, az, ay, ax, 3, h, w);
        unsigned char* pixelOffset_a = get_RGB(a, az, ay, ax, 3, h, w);
        int r = pixelOffset[0] - pixelOffset_a[0];
        int g = pixelOffset[1] - pixelOffset_a[1];
        int b = pixelOffset[2] - pixelOffset_a[2];

        double pixelError = r*r + g*g + b*b;

        error += sqrt(pixelError);
      }
    }
  }

  return error;
}

int main(int argc, char **argv) {

  // current assumption is that image sizes are same, update it later

  int height = h;
  int width = w;
  int depth = d;
  int nchannels = 3;
  unsigned char* img1_pixels;
  unsigned char* img2_pixels;


  
  if(argc < 3) {
    cout<<"Usage: " << argv[0] << " <image_file1>  <image_file2>\n";
    return 1;
    }
  // cout << w << h << d << endl;
  // Read input image 1
    img1_pixels = (unsigned char*) malloc(sizeof(unsigned char)*width*height*depth*nchannels);
  for (int i = 0; i < d; i ++){
    int temp_width, temp_height, temp_nchannels;
    string path= argv[1]+ to_string(i) +".jpeg";
    unsigned char *img_in = stbi_load(path.c_str(), &temp_width, &temp_height, &temp_nchannels, 0);
    int start_idx = width * height * i * nchannels;
    memcpy((void*)(img1_pixels + start_idx), img_in, sizeof(unsigned char)*temp_width*temp_height*temp_nchannels);
  }

  // Read input image 2
    img2_pixels = (unsigned char*) malloc(sizeof(unsigned char)*width*height*depth*nchannels);
  for (int i = 0; i < d; i ++){
    int temp_width, temp_height, temp_nchannels;
    string path= argv[2]+ to_string(i) +".jpeg";
    unsigned char *img_in = stbi_load(path.c_str(), &temp_width, &temp_height, &temp_nchannels, 0);
    int start_idx = width * height * i * nchannels;
    memcpy((void*)(img2_pixels + start_idx), img_in, sizeof(unsigned char)*temp_width*temp_height*temp_nchannels);
  }

  
  unsigned char* ann = (unsigned char*) malloc(sizeof(unsigned char)*width*height*depth*3);
  unsigned char* ann_buf = (unsigned char*) malloc(sizeof(unsigned char)*width*height*depth*3);
  unsigned char* annd = (unsigned char*) malloc(sizeof(unsigned char)*width*height*depth*4);
  unsigned char* annd_buf = (unsigned char*) malloc(sizeof(unsigned char)*width*height*depth*4);


  unsigned char* d_img1_pixels;
  unsigned char* d_img2_pixels;
  unsigned char* d_ann;
  unsigned char* d_annd;
  unsigned char* d_ann_buf;
  unsigned char* d_annd_buf;



  cudaMalloc((void**)&d_img1_pixels, sizeof(unsigned char)*width*height*depth*nchannels);
  cudaMalloc((void**)&d_img2_pixels, sizeof(unsigned char)*width*height*depth*nchannels);
  cudaMalloc((void**)&d_ann, sizeof(unsigned char)*width*height*depth*nchannels);
  cudaMalloc((void**)&d_annd, sizeof(unsigned char)*width*height*depth*4);
  cudaMalloc((void**)&d_ann_buf, sizeof(unsigned char)*width*height*depth*nchannels);
  cudaMalloc((void**)&d_annd_buf, sizeof(unsigned char)*width*height*depth*4);


  cudaMemcpy(d_img1_pixels, img1_pixels, sizeof(unsigned char)*width*height*depth*nchannels, cudaMemcpyHostToDevice);
  cudaMemcpy(d_img2_pixels, img2_pixels, sizeof(unsigned char)*width*height*depth*nchannels, cudaMemcpyHostToDevice);


  int aew = width - patch_width+1, aeh = height - patch_width + 1, aed = depth - patch_width + 1;       /* Effective width and height (possible upper left corners of patches). */
  int bew = width - patch_width+1, beh = height - patch_width + 1, bed = depth - patch_width + 1;
  printf ("%d %d %d %d %d %d\n", aew, aeh, aed, bew, beh, bed);
  for (int az = 0; az < aed; az++) {
    for (int ay = 0; ay < aeh; ay++) {
      for (int ax = 0; ax < aew; ax++){
        int bx = rand()%bew;
        int by = rand()%beh;
        int bz = rand()%bed;
        unsigned char* pixelOffset = get_RGB(ann, az, ay, ax, 3, h, w);
        unsigned char* bufOffsets = get_RGB(ann_buf, az, ay, ax, 3, h, w);
        storeXYasRGB(pixelOffset, bx, by, bz);
        storeXYasRGB(bufOffsets, bx, by, bz);
        unsigned char* distOffset = get_RGB(annd, az, ay, ax, 4, h, w);
        int distance = dist(img1_pixels, img2_pixels, ax, ay, az, bx, by, bz, patch_width, h, w);
        storeintasRGBA(distOffset, distance);
        unsigned char* distOffset_buf = get_RGB(annd_buf, az, ay, ax, 4, h, w);
        storeintasRGBA(distOffset_buf, distance);
      }
    }
  }

  printf("initialization done\n");

  cudaMemcpy(d_ann, ann, sizeof(unsigned char)*width*height*depth*3, cudaMemcpyHostToDevice);
    cudaMemcpy(d_ann_buf, ann_buf, sizeof(unsigned char)*width*height*depth*3, cudaMemcpyHostToDevice);
    cudaMemcpy(d_annd, annd, sizeof(unsigned char)*width*height*depth*4, cudaMemcpyHostToDevice);
    cudaMemcpy(d_annd_buf, annd_buf, sizeof(unsigned char)*width*height*depth*4, cudaMemcpyHostToDevice);

  // unsigned char* ann_to_use = NULL;
  // unsigned char* other = NULL;
  // unsigned char* annd_to_use = NULL;
  // unsigned char* annd_other = NULL;

    cudaEvent_t start_k, stop_k;
    cudaEventCreate(&start_k);
    cudaEventCreate(&stop_k);

  cudaEventRecord(start_k);

  for (int iter = 0; iter < patch_match_iters; iter++) {
    int zend = aed;
    int yend = aeh;
    int xend = aew;

    dim3 dimBlock(8, 8, 8);
    dim3 dimGrid(xend/8 + 1, yend/8 + 1, zend/8 + 1);
    // dim3 dimGrid(1, 1, 1);

    if (iter % 2 == 0){
      patchmatch<<< dimGrid, dimBlock >>>(d_img1_pixels, d_img2_pixels, d_ann, d_annd, d_ann_buf, d_annd_buf, height, width, depth, patch_width);
    }
    
    if (iter % 2 == 1) {
      patchmatch<<< dimGrid, dimBlock >>>(d_img1_pixels, d_img2_pixels, d_ann_buf, d_annd_buf, d_ann, d_annd, height, width, depth, patch_width);

    }
    // patchmatch<<<zend,yend,xend>>>(d_img1_pixels, d_img2_pixels, ann_to_use, annd_to_use, other, annd_other, height, width, depth, patch_width);
    cudaDeviceSynchronize();
 }

 cudaEventRecord(stop_k);



  cout << "Patch match done" << endl;

  cudaEventSynchronize(stop_k);

  float milliseconds = 0;
  cudaEventElapsedTime(&milliseconds, start_k, stop_k);
  printf("\tTime measured for patchmatch is %.2f milliseconds.\n", milliseconds);

 

  unsigned char* output = (unsigned char*) malloc(sizeof(unsigned char)*width*height*depth*3);
  cudaMemcpy(ann, d_ann, sizeof(unsigned char)*width*height*depth*3, cudaMemcpyDeviceToHost);

  map_patches(img1_pixels, img2_pixels, ann, output);
  
  string output_folder = "./color/out/";
  string ann_folder = "./color/ann/";
  string annd_folder = "./color/annd/";
  
  for (int i = 0; i < d; i ++){
    int ann_start_idx = width *  height * i * nchannels;
    string ann_path= ann_folder+ to_string(i) +".png";
    stbi_write_png(ann_path.c_str(), width, height, 3, ann + ann_start_idx, width*3);
    
    int annd_start_idx = width * height * i * nchannels;
    string annd_path= annd_folder+ to_string(i) +".png";
    stbi_write_png(annd_path.c_str(), width, height, 4, annd + annd_start_idx, width*4);

    int output_start_idx = width * height * i * nchannels;
    string output_path= output_folder+ to_string(i) +".png";
    stbi_write_png(output_path.c_str(), width, height, 3, output + output_start_idx, width*3);
  }

  double error = compute_error(output, img1_pixels);
  long pixels = d*w*h;
  double per_pixel_error = error/pixels;
  cout << "The Error computed is " << error << endl;
  cout << "Per pixel error is "<<per_pixel_error << endl;
  
  return 0;
}
