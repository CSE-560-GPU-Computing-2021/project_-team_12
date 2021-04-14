import SimpleITK as sitk
import numpy as np
import matplotlib.pyplot as plt
from PIL import Image

vol = sitk.ReadImage("./color/color_512_512_352.mhd")
volArray = sitk.GetArrayFromImage(vol)
print(volArray.shape, volArray.dtype)
w_offset = 100;
h_offset = 100;
d_offset = 100;
w = 256;
h = 256;
d = 256;
print(w, h, d)
print("starting saving")
print(d)
for i in range(w):
	if i % 20 == 0:
		print(i)
		print(volArray[w_offset + i,h_offset:h_offset + h,d_offset:d_offset + d].shape)
	im = Image.fromarray(volArray[w_offset + i,h_offset:h_offset + h,d_offset:d_offset + d], 'RGB')
	file_name = "./color/img2/"+str(i)+".jpeg"
	im.save(file_name)