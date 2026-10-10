import sys, collections, hashlib
from PIL import Image
d=open(sys.argv[1],'rb').read()
a=int(sys.argv[2],16); b=int(sys.argv[3],16); width=int(sys.argv[4]); out=sys.argv[5]
scale=int(sys.argv[6]) if len(sys.argv)>6 else 4
Z=bytes.fromhex('8a979871'); F=bytes.fromhex('ff50ed1f')
w=[d[i:i+4] for i in range(a,b,4)]
h=(len(w)+width-1)//width
im=Image.new('RGB',(width,h),(255,0,255))
px=im.load()
for i,x in enumerate(w):
    if x==Z: c=(255,255,255)
    elif x==F: c=(0,0,0)
    else:
        hh=hashlib.md5(x).digest(); c=(hh[0]//2+64,hh[1]//2+64,hh[2]//2+64)
    px[i%width,i//width]=c
im=im.resize((width*scale,h*scale),Image.NEAREST)
im.save(out)
