import sys, collections
d=open(sys.argv[1],'rb').read()
start=int(sys.argv[2],16); colh=int(sys.argv[3]); c0=int(sys.argv[4]); c1=int(sys.argv[5])
BG=sys.argv[6]; FG=sys.argv[7]
def key(c,y):
    off=start+c*colh+y; wo=off&~3; return d[wo:wo+4].hex(), off-wo
votes=collections.defaultdict(lambda:[[0,0] for _ in range(4)])
cnt=collections.Counter()
for c in range(c0,c1):
    for y in range(colh):
        k,i=key(c,y); cnt[k]+=1
        for dc in (-1,1):
            for dy in (-1,0,1):
                if not (0<=y+dy<colh): continue
                k2,_=key(c+dc,y+dy)
                if k2==BG: votes[k][i][0]+=1 if dy==0 else 0.3
                elif k2==FG: votes[k][i][1]+=1 if dy==0 else 0.3
for k,n in cnt.most_common():
    if k in (BG,FG): continue
    v=votes[k]
    print(k,n//4 if n>=4 else n,' '.join(f"{(b[1]/(b[0]+b[1]) if b[0]+b[1] else -1):.2f}" for b in v), ' n=',' '.join(str(int(b[0]+b[1])) for b in v))
