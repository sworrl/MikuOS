import sys, json
import numpy as np
d=open(sys.argv[1],'rb').read(); m=json.load(open(sys.argv[2]))
a=int(sys.argv[3],16); b=int(sys.argv[4],16)
arr=np.full(b-a+300,-1,dtype=int)
for o in range(a&~3,b+300,4):
    k=d[o:o+4].hex()
    if k in m:
        for i in range(4):
            if 0<=o+i-a<len(arr): arr[o+i-a]=m[k][i]
n=b-a; res=[]
for h in range(3,130):
    u=arr[:n]; v=arr[h:h+n]; ok=(u>=0)&(v>=0)&((u!=0)|(v!=0))
    if ok.sum()<10: continue
    res.append(((u[ok]==v[ok]).mean(),h,int(ok.sum())))
res.sort(reverse=True)
print([(h,round(r,3),n) for r,h,n in res[:10]])
