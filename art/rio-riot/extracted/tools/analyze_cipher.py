# Rio Riot granite firmware: whole-file statistics that show the 32-bit ECB codebook structure.
# usage: python3 -I analyze_cipher.py granite-1.25.fw
import sys, math, collections
d=open(sys.argv[1],'rb').read()
def H(b):
    c=collections.Counter(b); n=len(b); return -sum(v/n*math.log2(v/n) for v in c.values())
print('size',len(d),'header',d[:16].hex())
for i in range(0,len(d),0x8000): print(f'{i:06x} H={H(d[i:i+0x8000]):.3f}')
w=collections.Counter(d[i:i+4] for i in range(0,len(d),4))
print('distinct aligned words',len(w))
for k,v in w.most_common(12):
    pos=[i for i in range(0,len(d),4) if d[i:i+4]==k]
    print(k.hex(),v,hex(pos[0]),hex(pos[-1]))
# a byte-wise XOR/substitution would map 0x00000000 to 4 equal bytes and keep lanes independent; it does not.
code=set(d[i:i+4] for i in range(0x4000,0x50000,4)); N=len(code)
for a in range(4):
    for b in range(a+1,4):
        c=collections.Counter((x[a],x[b]) for x in code); p=sum(v*(v-1)//2 for v in c.values())
        print('lanes',a,b,'pair collisions',p,'random expectation',round(N*(N-1)/2/65536))
