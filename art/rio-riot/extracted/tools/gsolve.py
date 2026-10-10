# global ICM codebook solve over multiple column-major segments (Potts prior + bijectivity)
import sys, json, itertools, collections, random
import numpy as np
d=open(sys.argv[1],'rb').read(); m=json.load(open(sys.argv[2])); out=sys.argv[3]; L=int(sys.argv[4]); segs=sys.argv[5:]
fixed={k:tuple(v) for k,v in m.items()}
keys=[]; kid={}
grids=[]
for sg in segs:
    a,b,h=sg.split(':'); a=int(a,16); b=int(b,16); h=int(h); ncol=(b-a)//h
    K=np.zeros((h,ncol),dtype=int); I=np.zeros((h,ncol),dtype=int)
    for c in range(ncol):
        for y in range(h):
            off=a+c*h+y; wo=off&~3; k=d[wo:wo+4].hex()
            if k not in kid: kid[k]=len(keys); keys.append(k)
            K[y,c]=kid[k]; I[y,c]=off-wo
    grids.append((K,I))
nk=len(keys)
tab=np.zeros((nk,4),dtype=int)
isfixed=np.zeros(nk,bool)
for k,i in kid.items():
    if k in fixed: tab[i]=fixed[k]; isfixed[i]=True
occ=collections.defaultdict(list)
for g,(K,I) in enumerate(grids):
    for (y,c),k in np.ndenumerate(K): occ[k].append((g,y,c))
cands=[p for p in itertools.product(range(L),repeat=4)]
def local(k):
    # returns list of (pixelindex i, list of neighbor (g,y,c)) 
    pass
N4=((0,1),(0,-1),(1,0),(-1,0))
def energy_of(k,p):
    e=0.0
    for g,y,c in occ[k]:
        K,I=grids[g]; v=p[I[y,c]]; h,w=K.shape
        for dy,dc in N4:
            yy,cc=y+dy,c+dc
            if 0<=yy<h and 0<=cc<w:
                k2=K[yy,cc]; u=p[I[yy,cc]] if k2==k else tab[k2][I[yy,cc]]
                e+= (v!=u)*(1.0 if dc else 0.7)
    return e
used=collections.Counter(tuple(tab[i]) for i in range(nk) if isfixed[i])
unk=[i for i in range(nk) if not isfixed[i]]
unk.sort(key=lambda i:-len(occ[i]))
# init: most common neighbor level per byte index
for i in unk: tab[i]=(0,0,0,0)
for it in range(12):
    ch=0
    for i in unk:
        cur=tuple(tab[i])
        best=None
        for p in cands:
            pen=0 if p==cur else 0
            taken=sum(1 for j in range(nk) if j!=i and tuple(tab[j])==p and (isfixed[j] or j in unk[:])) 
            e=energy_of(i,p)+ 1000*(taken>0)
            if best is None or e<best[0]: best=(e,p)
        if best[1]!=cur: tab[i]=best[1]; ch+=1
    print('iter',it,'changed',ch,flush=True)
    if not ch: break
res={keys[i]:list(map(int,tab[i])) for i in range(nk)}
json.dump(res,open(out,'w'))
