# Viterbi segmentation of concatenated column-major images into constant-height runs
import sys, json
import numpy as np
d=open(sys.argv[1],'rb').read(); m=json.load(open(sys.argv[2]))
a=int(sys.argv[3],16); b=int(sys.argv[4],16); pen=float(sys.argv[5]) if len(sys.argv)>5 else 30
H=list(range(3,131))
arr=np.full(b-a+200,-1,dtype=int)
for o in range(a&~3,b+200,4):
    k=d[o:o+4].hex()
    if k in m:
        for i in range(4):
            if a<=o+i<b+200: arr[o+i-a]=m[k][i]
n=b-a
S=np.zeros((n,len(H)))
for j,h in enumerate(H):
    u=arr[:n]; v=arr[h:h+n]; ok=(u>=0)&(v>=0)&((u!=0)|(v!=0))
    S[:,j]=np.where(ok,np.where(u==v,1.0,-1.5),0.0)
# viterbi
score=S[0].copy(); back=np.zeros((n,len(H)),dtype=np.int32)
for t in range(1,n):
    best=score.argmax()
    stay=score; sw=score[best]-pen
    choose=sw>stay
    back[t]=np.where(choose,best,np.arange(len(H)))
    score=np.where(choose,sw,stay)+S[t]
path=np.zeros(n,dtype=int); path[-1]=score.argmax()
for t in range(n-1,0,-1): path[t-1]=back[t][path[t]]
segs=[]; s=0
for t in range(1,n+1):
    if t==n or path[t]!=path[s]:
        segs.append((a+s,a+t,H[path[s]])); s=t
for s,e,h in segs: print(hex(s),hex(e),e-s,'h',h,'cols',round((e-s)/h,1))
