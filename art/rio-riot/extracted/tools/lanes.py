import sys, collections
d=open(sys.argv[1],'rb').read()
a=int(sys.argv[2],16); b=int(sys.argv[3],16)
w=[d[i:i+4] for i in range(a,b,4)]
c=collections.Counter(w)
print('distinct words',len(c))
for j in range(4):
    print('lane',j,'distinct bytes',len(set(x[j] for x in w)))
print(c.most_common(40))
