import sys
d=open(sys.argv[1],'rb').read()
a=int(sys.argv[2],16); b=int(sys.argv[3],16); win=int(sys.argv[4],16); step=int(sys.argv[5],16)
BGs={bytes.fromhex('ff50ed1f'),bytes.fromhex('8a979871')}
for s in range(a&~3,b,step):
    w=[d[i:i+4] for i in range(s,s+win,4)]; n=len(w); res=[]
    for lag in range(2,131):
        num=den=0
        for i in range(n-lag):
            x,y=w[i],w[i+lag]
            if x in BGs and y in BGs: continue
            den+=1; num+= x==y
        if den>=15: res.append((num/den,lag))
    res.sort(reverse=True)
    print(hex(s),' '.join(f"{l}:{r:.2f}" for r,l in res[:5]))
