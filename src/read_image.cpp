#include<iostream>
#include "define.h"
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

// This function needs modification, take care of it later
	unsigned char* getRGB(int row, int col){
		unsigned bytePerPixel = nchannels;
		unsigned char* pixelOffset = img_pixels + (row*width + col) * bytePerPixel;
		return pixelOffset;
	}
};


int main(){
    int size = w*h*d*3;
    
}