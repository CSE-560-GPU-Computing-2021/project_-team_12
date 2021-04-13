import SimpleITK as sitk
import numpy as np
import matplotlib.pyplot as plt
from PIL import Image
import sys


outfolder = sys.argv[1]

w = 64
h = 256
d = 128

outArray = []

for i in range(w):
    outpath = outfolder + str(i) + ".jpeg"
    outimg = Image.open(outpath)
    outarr = np.array(outimg)
    outArray.append(outarr)

a = np.array(outArray)
print(a.shape)
vol = sitk.GetImageFromArray(a)
sitk.WriteImage(vol, outfolder+"brain.mhd")