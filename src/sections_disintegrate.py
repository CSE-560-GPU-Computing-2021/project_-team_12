import SimpleITK as sitk
import numpy as np
import matplotlib.pyplot as plt
from PIL import Image

vol = sitk.ReadImage("./color/color_512_512_352.mhd")
volArray = sitk.GetArrayFromImage(vol)
print(volArray.shape, volArray.dtype)
w_offset = 0;
h_offset = 0;
d_offset = 0;
w = 64;
h = 256;
d = 128;
print(w, h, d)
print("starting saving")
print(d)
for i in range(w):
	if i % 20 == 0:
		print(i)
		print(volArray[w_offset + i,h_offset:h_offset + h,d_offset:d_offset + d].shape)
	im = Image.fromarray(volArray[w_offset + i,h_offset:h_offset + h,d_offset:d_offset + d], 'RGB')
	file_name = "./color/img1/"+str(i)+".jpeg"
	im.save(file_name)