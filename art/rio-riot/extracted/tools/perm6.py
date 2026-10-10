import sys, itertools, collections
import numpy as np
d=open(sys.argv[1],'rb').read()
start=int(sys.argv[2],16); colh=int(sys.argv[3]); c0=int(sys.argv[4]); c1=int(sys.argv[5]); BG,FG=sys.argv[6],sys.argv[7]
ncol=c1-c0
K=np.empty((colh,ncol),dtype=object); I=np.zeros((colh,ncol),dtype=int)
for c in range(ncol):
    for y in range(colh):
        off=start+(c0+c)*colh+y; wo=off&~3; K[y,c]=d[wo:wo+4].hex(); I[y,c]=off-wo
cnt=collections.Counter(K.flatten())
edges=[k for k,_ in cnt.most_common() if k not in (BG,FG)][:6]
print('edges',edges)
P=[(0,0,0,1),(0,0,1,1),(0,1,1,1),(1,0,0,0),(1,1,0,0),(1,1,1,0)]
best=[]
for perm in itertools.permutations(P):
    m={BG:(0,0,0,0),FG:(1,1,1,1)}; m.update(dict(zip(edges,perm)))
    img=np.full((colh,ncol),-1.0)
    for y in range(colh):
        for c in range(ncol):
            p=m.get(K[y,c]); 
            if p: img[y,c]=p[I[y,c]]
    msk=img>=0
    h=(img[:,1:]!=img[:,:-1])&msk[:,1:]&msk[:,:-1]
    v=(img[1:,:]!=img[:-1,:])&msk[1:,:]&msk[:-1,:]
    best.append((h.sum()+v.sum(),perm))
best.sort()
for s,p in best[:5]: print(s,p)
