#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION

#include <iostream>
#include <ctime>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <climits>
#include <string>
#include "define.h"
// #include <bits/stdc++.h>

#include "stb_image.h"
#include "stb_image_write.h"

#define ENABLE_TIMER 1

int MAX(int a, int b) {
  if (a > b){
    return a;
  }
  return b;
}
int MIN(int a, int b) {
  if (a < b){
    return a;
  }
  return b;
}

using namespace std;

struct image
{
	int height;
	int width;
	int depth;
	int nchannels;
	unsigned char* img_pixels;

	image()
	{
		height = 0;
		width = 0;
		depth = 0;
		nchannels = 0;
	}

	image(int w, int h, int d, int n)
	{
		height = h;
		width = w;
		depth = d;
		nchannels = n;
	}

	unsigned char* getRGB(int img_no, int row, int col){
		unsigned bytePerPixel = nchannels;
		unsigned char* pixelOffset = img_pixels + (height*width*img_no + (row*width + col)) * bytePerPixel;
		return pixelOffset;
	}
};

void storeXYasRGB(unsigned char* offset, int bx, int by, int bz)
{
	offset[0] = bx;
	offset[1] = by;
	offset[2] = bz;
}


void storeintasRGBA(unsigned char* offset, int tostore)
{
	offset[3] = tostore&0xff;
	offset[2] = (tostore&0xff00)>>8;
	offset[1] = (tostore&0xff0000)>>16;
	offset[0] = (tostore&0xff000000)>>24;
}


int dist(image *a, image *b, int ax, int ay, int az, int bx, int by, int bz, int cutoff=INT_MAX) {
  int ans = 0;
  for (int dz = 0; dz < patch_width; dz ++) {
    for (int dy = 0; dy < patch_width; dy++) {
      for (int dx = 0; dx < patch_width; dx++) {
        unsigned char* ac = a->getRGB(az + dz, ay+dy, ax+dx);
        unsigned char* bc = b->getRGB(bz + dz, by+dy, bx+dx);
        int dr = ac[0] - bc[0];
        int dg = ac[1] - bc[1];
        int db = ac[2] - bc[2];
        ans += dr*dr + dg*dg + db*db;
      }
    }
    if (ans >= cutoff) { return cutoff; }
    if (ans < 0){ return cutoff; }
  }
  return ans;
}


void improve_guess(image *a, image *b, int ax, int ay, int az, int &xbest, int &ybest, int &zbest, int &dbest, int bx, int by, int bz) {
  int d = dist(a, b, ax, ay, az, bx, by, bz, dbest);
  if (d < dbest) {
    dbest = d;
    xbest = bx;
    ybest = by;
    zbest = bz;
  }
}

int XfromRGB(unsigned char* v){
	return v[0];
}

int YfromRGB(unsigned char* v){
	return v[1];
}

int ZfromRGB(unsigned char* v){
	return v[2];
}

int netINT(unsigned char *v){
	return v[0]<<24 | v[1] << 16 | v[2] << 8 | v[3];
}

// void map_back(image *a, image *b, image *ann, image *out)
// {
//   for (int x = 0; x < ann->width; x++)
//     for (int y = 0; y < ann->height; y++)
//     {
//       unsigned char* map = ann->getRGB(y, x);
//       int x_ = MIN(XfromRGB(map), ann->width);
//       int y_ = MIN(YfromRGB(map), ann->height);

//       unsigned char* binputs = b->getRGB(y_, x_);
//       unsigned char* output = out->getRGB(y, x);
//       output[0] = binputs[0];
//       output[1] = binputs[1];
//       output[2] = binputs[2];
//     }
// }

void map_patches(image *a, image *b, image *ann, image *out)
{
  int aew = a->width - patch_width + 1, aeh = a->height - patch_width + 1, aed = a->depth - patch_width + 1;
  for (int az = 0; az < aed; az ++) {
    for (int ay = 0; ay < aeh; ay++) {
      for (int ax = 0; ax < aew; ax++) {
        unsigned char* map = ann->getRGB(az, ay, ax);
        int x = XfromRGB(map);
        int y = YfromRGB(map);
        int z = ZfromRGB(map);
        for (int dz = 0; dz < patch_width; dz ++) {
          for (int dy = 0; dy < patch_width; dy++) {
            for (int dx = 0; dx < patch_width; dx++) {
              if (z+dz >= b->depth || y+dy >= b->height || x+dx >= b->width || az + dz >= out -> depth || ay + dy >= out -> height || ax + dx >= out->width)
                continue;
              unsigned char* binputs = b->getRGB(z + dz, y+dy, x+dx);
              unsigned char* output = out->getRGB(az + dz, ay+dy, ax+dx);
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


void patchmatch(image *a, image *b, image *ann, image *annd) {

  int aew = a->width - patch_width+1, aeh = a->height - patch_width + 1, aed = a->depth - patch_width + 1;       /* Effective width and height (possible upper left corners of patches). */
  int bew = b->width - patch_width+1, beh = b->height - patch_width + 1, bed = b->depth - patch_width + 1;
  printf ("%d %d %d %d %d %d\n", aew, aeh, aed, bew, beh, bed);
  for (int az = 0; az < aed; az++) {
    for (int ay = 0; ay < aeh; ay++) {
      for (int ax = 0; ax < aew; ax++){
        int bx = rand()%bew;
        int by = rand()%beh;
        int bz = rand()%bed;
        unsigned char* pixelOffset = ann->getRGB(az, ay, ax);
        storeXYasRGB(pixelOffset, bx, by, bz);
        unsigned char* distOffset = annd->getRGB(az, ay, ax);
        int distance = dist(a, b, ax, ay, az, bx, by, bz);
        storeintasRGBA(distOffset, distance);
      }
    }
  }

  for (int az = 0; az < aed; az++) {
    for (int ay = 0; ay < aeh; ay++) {
      for (int ax = 0; ax < aew; ax++){
        unsigned char* pixelOffset = ann->getRGB(az, ay, ax);
        int x = XfromRGB(pixelOffset);
        int y = YfromRGB(pixelOffset);
        int z = ZfromRGB(pixelOffset);
        if (x >= bew || y >= beh || z >= bed){
          cout << x << " " << y << " " << z << endl;
        }
      }
    }
  }


 for (int iter = 0; iter < patch_match_iters; iter++) {
    int zstart = 0, zend = aed, zchange = 1;
    int ystart = 0, yend = aeh, ychange = 1;
    int xstart = 0, xend = aew, xchange = 1;

    if (iter % 2 == 1) {
      zstart = zend-1; zend = -1; zchange = -1;
      ystart = yend-1; yend = -1; ychange = -1;
      xstart = xend-1; xend = -1; xchange = -1;
    }
    for (int az = zstart; az != zend; az += zchange){
      for (int ay = ystart; ay != yend; ay += ychange) {
        for (int ax = xstart; ax != xend; ax += xchange) { 
          unsigned char* v = ann->getRGB(az, ay, ax);
          int ybest = YfromRGB(v), xbest = XfromRGB(v), zbest = ZfromRGB(v);
          int dbest = netINT(annd->getRGB(az, ay, ax));

          // Propagation
          if ((unsigned) (ax - xchange) < (unsigned) aew) {
            unsigned char* vp = ann->getRGB(az, ay, ax-xchange);
            int xp = XfromRGB(vp) + xchange, yp = YfromRGB(vp), zp = ZfromRGB(vp);
            if ((unsigned) xp < (unsigned) bew) {
              improve_guess(a, b, ax, ay, az, xbest, ybest, zbest, dbest, xp, yp, zp);
            }
          }

          if ((unsigned) (ay - ychange) < (unsigned) aeh) {
            unsigned char* vp = ann->getRGB(az, ay-ychange, ax);
            int xp = XfromRGB(vp), yp = YfromRGB(vp) + ychange, zp = ZfromRGB(vp);
            if ((unsigned) yp < (unsigned) beh) {
              improve_guess(a, b, ax, ay, az, xbest, ybest, zbest, dbest, xp, yp, zp);
            }
          }

          if ((unsigned) (az - zchange) < (unsigned) aed) {
            unsigned char* vp = ann->getRGB(az-zchange, ay, ax);
            int xp = XfromRGB(vp), yp = YfromRGB(vp), zp = ZfromRGB(vp) + zchange;
            if ((unsigned) zp < (unsigned) bed) {
              improve_guess(a, b, ax, ay, az, xbest, ybest, zbest, dbest, xp, yp, zp);
            }
          }
          int rs_start = random_search_max_span;
          if (rs_start > MAX(MAX(b->width, b->height), b->depth)) { rs_start = MAX(MAX(b->width, b->height), b->depth); }
          for (int mag = rs_start; mag >= 1; mag /= 2) {
            int xmin = MAX(xbest-mag, 0), xmax = MIN(xbest+mag+1,bew);
            int ymin = MAX(ybest-mag, 0), ymax = MIN(ybest+mag+1,beh);
            int zmin = MAX(zbest-mag, 0), zmax = MIN(zbest+mag+1,bed);

            int xp = xmin;
            int yp = ymin;
            int zp = zmin;

            if (xmax > xmin)
            {
              xp = xmin+rand()%(xmax-xmin);
            }
            if (ymax > ymin)
            {
              yp = ymin+rand()%(ymax-ymin);
            }
            if (zmax > zmin)
            {
              zp = zmin+rand()%(zmax-zmin);
            }

            improve_guess(a, b, ax, ay, az, xbest, ybest, zbest, dbest, xp, yp, zp);
          }

          storeXYasRGB(ann->getRGB(az, ay, ax), xbest, ybest, zbest);
          storeintasRGBA(annd->getRGB(az, ay, ax), dbest);
        }
      }
    }
 }
}

double compute_error(image* output, image* a)
{
  double error = 0;

  for (int az = 0; az < a->depth; az++) {
    for (int ay = 0; ay < a->height; ay++) {
      for (int ax = 0; ax < a->width; ax++){
        unsigned char* pixelOffset = output->getRGB(az, ay, ax);
        unsigned char* pixelOffset_a = a->getRGB(az, ay, ax);
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
	int d = 64;
	int h = 256;
	int w = 128;
  if(argc < 3) {
    cout<<"Usage: " << argv[0] << " <image_file1>  <image_file2>\n";
    return 1;
    }

  // Read input image 1
  struct image* img1 = NULL;
  img1 = new image(w, h, d, 3);
	cout<<"Reading "<<argv[1]<<"... "<<endl;
	img1->img_pixels = (unsigned char*) malloc(sizeof(unsigned char)*img1->width*img1->height*img1->depth*img1->nchannels);
  for (int i = 0; i < d; i ++){
    int temp_width, temp_height, temp_nchannels;
    string path= argv[1]+ to_string(i) +".jpeg";
    unsigned char *img_in = stbi_load(path.c_str(), &temp_width, &temp_height, &temp_nchannels, 0);
    int start_idx = img1->width * img1 -> height * i * img1->nchannels;
    memcpy((void*)(img1 -> img_pixels + start_idx), img_in, sizeof(unsigned char)*temp_width*temp_height*temp_nchannels);
  }

  // Read input image 2
  struct image* img2 = NULL;
  img2 = new image(w, h, d, 3);
	cout<<"Reading "<<argv[2]<<"... "<<endl;
	img2->img_pixels = (unsigned char*) malloc(sizeof(unsigned char)*img2->width*img2->height*img2->depth*img2->nchannels);
  for (int i = 0; i < d; i ++){
    int temp_width, temp_height, temp_nchannels;
    string path= argv[2]+ to_string(i) +".jpeg";
    unsigned char *img_in = stbi_load(path.c_str(), &temp_width, &temp_height, &temp_nchannels, 0);
    int start_idx = img2->width * img2 -> height * i * img2->nchannels;
    memcpy((void*)(img2 -> img_pixels + start_idx), img_in, sizeof(unsigned char)*temp_width*temp_height*temp_nchannels);
  }

  cout << "inputs read" << endl;

  image* ann = NULL;
  image* annd = NULL;
  ann = new image(img1 -> width, img1 -> height, img1 -> depth ,3);
  annd = new image(img1 -> width, img1 -> height, img1 -> depth ,4);
  ann->img_pixels = (unsigned char*) malloc(sizeof(unsigned char)*img1->width*img1->height*img1->depth*3);
  annd->img_pixels = (unsigned char*) malloc(sizeof(unsigned char)*img1->width*img1->height*img1->depth*4);

  image* output = new image(img1->width, img1->height, img1 -> depth,3);
  output->img_pixels = (unsigned char*) malloc(sizeof(unsigned char)*img1->width*img1->height*img1->depth*3);

  cout << "Starting patch match" << endl;
  patchmatch(img1, img2, ann, annd);
  cout << "starting map patches" << endl;
  map_patches(img1, img2, ann, output);

  printf("%d %d %d\n",output->width, output->height, output->depth );

  string output_folder = "./color/out/";
  string ann_folder = "./color/ann/";
  string annd_folder = "./color/annd/";
  
  for (int i = 0; i < d; i ++){
    int ann_start_idx = ann->width * ann -> height * i * ann->nchannels;
    string ann_path= ann_folder+ to_string(i) +".png";
    stbi_write_png(ann_path.c_str(), ann->width, ann->height, 3, ann->img_pixels + ann_start_idx, ann->width*3);
    
    int annd_start_idx = annd->width * annd -> height * i * annd->nchannels;
    string annd_path= annd_folder+ to_string(i) +".png";
    stbi_write_png(annd_path.c_str(), annd->width, annd->height, 4, annd->img_pixels + annd_start_idx, annd->width*4);

    int output_start_idx = output->width * output -> height * i * output->nchannels;
    string output_path= output_folder+ to_string(i) +".png";
    stbi_write_png(output_path.c_str(), output->width, output->height, 3, output->img_pixels + output_start_idx, output->width*3);
  }
  
  return 0;
}