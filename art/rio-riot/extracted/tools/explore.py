# render region as column-major 1 byte/px with column height h, wrapped into strips; known codebook colors, unknown hashed
import sys, json, hashlib
import numpy as np
from PIL import Image
d=open(sys.argv[1],'rb').read()
a=int(sys.argv[2],16); b=int(sys.argv[3],16); h=int(sys.argv[4]); per=int(sys.argv[5]); m=json.load(open(sys.argv[6])); out=sys.argv[7]; sc=int(sys.argv[8]) if len(sys.argv)>8 else 3
pal={0:(235,245,235),1:(0,0,0),2:(255,140,0),3:(0,120,255),4:(160,0,160)}
ncol=(b-a)//h; strips=(ncol+per-1)//per
img=np.full((strips*(h+3),per,3),(255,0,0),dtype=np.uint8)
for c in range(ncol):
    sx=c%per; sy=(c//per)*(h+3)
    for y in range(h):
        off=a+c*h+y; wo=off&~3; k=d[wo:wo+4].hex(); i=off-wo
        if k in m: img[sy+y,sx]=pal[m[k][i]]
        else:
            hh=hashlib.md5(k.encode()).digest(); img[sy+y,sx]=(100+hh[0]%100,100+hh[1]%100,200+hh[2]%55)
Image.fromarray(img).resize((per*sc,strips*(h+3)*sc),Image.NEAREST).save(out)
print(ncol,strips)
