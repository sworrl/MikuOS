# export decoded column-major 1-byte/px images from the encrypted firmware using a recovered (partial) codebook
import sys, json, os
from PIL import Image
fw, cbf, specf, outdir = sys.argv[1:5]
d=open(fw,'rb').read(); m=json.load(open(cbf)); specs=json.load(open(specf))
os.makedirs(outdir,exist_ok=True)
# level -> RGBA. 0=A light background, 1=B ink, 2=Z (8a979871, probably 0x00: clear/transparent), 3=fourth level (unknown meaning)
PAL={0:(255,255,255,255),1:(0,0,0,255),2:(255,255,255,0),3:(128,128,128,255)}
meta=[]
for s in specs:
    a=int(s['start'],16); h=s['h']; c0=s.get('c0',0); c1=s['c1']; w=c1-c0
    im=Image.new('RGBA',(w,h)); px=im.load(); unk=0
    for c in range(c0,c1):
        for y in range(h):
            o=a+c*h+y; wo=o&~3; k=d[wo:wo+4].hex()
            if k in m: px[c-c0,y]=PAL[m[k][o-wo]]
            else:
                px[c-c0,y]=PAL[0] if s.get('unknown_as_bg') else (255,0,255,255); unk+=1
    for lv,col in s.get('remap',{}).items():
        pass
    im.save(os.path.join(outdir,s['name']+'.png'))
    im.resize((w*4,h*4),Image.NEAREST).save(os.path.join(outdir,s['name']+'@4x.png'))
    meta.append({'name':s['name'],'fw_offset':hex(a+c0*h),'width':w,'height':h,'layout':'column-major, 1 byte per pixel',
                 'unknown_pixels':unk,'confidence':s.get('confidence',''),'note':s.get('note','')})
json.dump(meta,open(os.path.join(outdir,'bitmaps.json'),'w'),indent=1)
print(json.dumps(meta,indent=0))
