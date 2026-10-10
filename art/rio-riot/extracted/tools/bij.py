# bijective binary codebook completion via exhaustive permutation over the top unknown words
import sys, json, itertools, collections
import numpy as np
d=open(sys.argv[1],'rb').read()
start=int(sys.argv[2],16); colh=int(sys.argv[3]); c0=int(sys.argv[4]); c1=int(sys.argv[5]); m=json.load(open(sys.argv[6])); out=sys.argv[7]; ntop=int(sys.argv[8])
ncol=c1-c0
keys=[]; idx={}
Kid=np.zeros((colh,ncol),dtype=int); I=np.zeros((colh,ncol),dtype=int)
for c in range(ncol):
    for y in range(colh):
        off=start+(c0+c)*colh+y; wo=off&~3; k=d[wo:wo+4].hex()
        if k not in idx: idx[k]=len(keys); keys.append(k)
        Kid[y,c]=idx[k]; I[y,c]=off-wo
cnt=collections.Counter(Kid.flatten().tolist())
used=set(tuple(v) for v in m.values())
free=[p for p in itertools.product((0,1),repeat=4) if p not in used]
unk=[keys[i] for i,_ in cnt.most_common() if keys[i] not in m][:ntop]
print('free',free,'unk',unk)
base=np.full((len(keys),4),-1)
for k,v in m.items():
    if k in idx: base[idx[k]]=v
best=None
for perm in itertools.permutations(free,len(unk)):
    tab=base.copy()
    for k,p in zip(unk,perm): tab[idx[k]]=p
    img=tab[Kid,I]
    ok=img>=0
    h=((img[:,1:]!=img[:,:-1])&ok[:,1:]&ok[:,:-1]).sum()
    v=((img[1:]!=img[:-1])&ok[1:]&ok[:-1]).sum()
    e=h+0.5*v
    if best is None or e<best[0]: best=(e,perm)
print(best)
mm=dict(m); mm.update({k:list(p) for k,p in zip(unk,best[1])})
json.dump(mm,open(out,'w'))
