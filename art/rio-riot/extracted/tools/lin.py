import sys, collections, itertools, struct
d=open(sys.argv[1],'rb').read()
a=int(sys.argv[2],16); b=int(sys.argv[3],16)
ws=[struct.unpack(sys.argv[5] if len(sys.argv)>5 else '<I',d[i:i+4])[0] for i in range(a,b,4)]
c=collections.Counter(ws)
S=[w for w,_ in c.most_common(int(sys.argv[4]) if len(sys.argv)>4 else 60)]
print(len(S))
s=set(S); hits=0; ahits=0
for x,y,z in itertools.combinations(S,3):
    if x^y^z in s and x^y^z not in (x,y,z): hits+=1
for x,y in itertools.combinations(S,2):
    for z in S:
        w=(x+y-z)&0xffffffff
        if w in s and z not in (x,y) and w not in (x,y,z): ahits+=1
print('xor-quads',hits,'add-quads',ahits)
