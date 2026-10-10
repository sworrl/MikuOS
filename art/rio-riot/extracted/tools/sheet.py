# contact sheet: segments "start:end:h" rendered column-major with codebook, stacked vertically with labels
import sys, json, hashlib
import numpy as np
from PIL import Image, ImageDraw
d=open(sys.argv[1],'rb').read(); m=json.load(open(sys.argv[2])); out=sys.argv[3]; sc=int(sys.argv[4]); segs=sys.argv[5:]
pal={0:(235,245,235),1:(0,0,0),2:(255,140,0),3:(0,120,255),4:(160,0,160),5:(0,170,0),6:(170,170,170)}
ims=[]
for sg in segs:
    a,b,h=sg.split(':'); a=int(a,16); b=int(b,16); h=int(h)
    ncol=(b-a)//h
    img=np.full((h,ncol,3),(255,0,0),dtype=np.uint8)
    for c in range(ncol):
        for y in range(h):
            off=a+c*h+y; wo=off&~3; k=d[wo:wo+4].hex(); i=off-wo
            if k in m: img[y,c]=pal[m[k][i]]
            else:
                hh=hashlib.md5(k.encode()).digest(); img[y,c]=(150+hh[0]%100,60+hh[1]%60,200+hh[2]%55)
    ims.append((sg,Image.fromarray(img).resize((ncol*sc,h*sc),Image.NEAREST)))
Wd=max(i.size[0] for _,i in ims)+10; Ht=sum(i.size[1]+16 for _,i in ims)
sheet=Image.new('RGB',(max(Wd,300),Ht),(255,255,255)); dr=ImageDraw.Draw(sheet); y=0
for sg,i in ims:
    dr.text((2,y),sg,fill=(0,0,0)); sheet.paste(i,(0,y+12)); y+=i.size[1]+16
sheet.save(out); print(sheet.size)
