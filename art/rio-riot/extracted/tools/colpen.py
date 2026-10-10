# column-major penguin: column = colbytes bytes, ppb pixels per byte; output transposed so columns are vertical
import sys, hashlib
from PIL import Image
d=open(sys.argv[1],'rb').read()
a=int(sys.argv[2],16); b=int(sys.argv[3],16); colbytes=int(sys.argv[4]); ppb=int(sys.argv[5]); out=sys.argv[6]
Z=bytes.fromhex('8a979871'); F=bytes.fromhex('ff50ed1f')
ncol=(b-a)//colbytes; H=colbytes*ppb
im=Image.new('RGB',(ncol,H)); px=im.load()
for c in range(ncol):
    for y in range(H):
        off=a+c*colbytes+y//ppb; wo=off&~3; x=d[wo:wo+4]
        if x==Z: col=(255,255,255)
        elif x==F: col=(200,230,200)
        else:
            hh=hashlib.md5(x).digest(); col=(hh[0]//2,hh[1]//2,hh[2]//2)
        px[c,y]=col
im=im.resize((ncol*3,H*3),Image.NEAREST); im.save(out); print(ncol,H)
