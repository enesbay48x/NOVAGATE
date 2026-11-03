import json, struct, io, numpy as np
from PIL import Image

CT = {5120:np.int8,5121:np.uint8,5122:np.int16,5123:np.uint16,5125:np.uint32,5126:np.float32}
NC = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}

class GLB:
    def __init__(self, path):
        d = open(path,'rb').read()
        _,_,length = struct.unpack('<4sII', d[:12]); off=12
        self.bin=b''
        while off < length:
            cl, ct = struct.unpack('<II', d[off:off+8]); off+=8
            ch = d[off:off+cl]; off+=cl
            if ct==0x4E4F534A: self.js=json.loads(ch)
            elif ct==0x004E4942: self.bin=ch
        self.path=path
    # ---- data access
    def bv_bytes(self,i):
        bv=self.js['bufferViews'][i]; o=bv.get('byteOffset',0)
        return self.bin[o:o+bv['byteLength']]
    def accessor(self,i):
        a=self.js['accessors'][i]; bv=self.js['bufferViews'][a['bufferView']]
        dt=np.dtype(CT[a['componentType']]); n=NC[a['type']]
        base=bv.get('byteOffset',0)+a.get('byteOffset',0)
        stride=bv.get('byteStride') or dt.itemsize*n
        cnt=a['count']
        raw=np.frombuffer(self.bin,dtype=np.uint8,count=(cnt-1)*stride+dt.itemsize*n,offset=base)
        out=np.empty((cnt,n),dtype=dt)
        for k in range(cnt) if False else []: pass
        idx=(np.arange(cnt)[:,None]*stride+np.arange(dt.itemsize*n)[None,:])
        out=raw[idx].view(dt).reshape(cnt,n)
        if a.get('normalized'):
            out=out.astype(np.float32)/np.iinfo(dt).max
        return out if n>1 else out[:,0]
    def image(self,i):
        im=self.js['images'][i]
        return Image.open(io.BytesIO(self.bv_bytes(im['bufferView'])))
    # ---- scene graph
    def local_matrix(self,n):
        if 'matrix' in n: return np.array(n['matrix'],dtype=np.float64).reshape(4,4).T
        T=np.eye(4); R=np.eye(4); S=np.eye(4)
        if 'translation' in n: T[:3,3]=n['translation']
        if 'rotation' in n:
            x,y,z,w=n['rotation']
            R[:3,:3]=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
        if 'scale' in n: S[0,0],S[1,1],S[2,2]=n['scale']
        return T@R@S
    def world_matrices(self):
        nodes=self.js['nodes']; parent={}
        for i,n in enumerate(nodes):
            for c in n.get('children',[]): parent[c]=i
        cache={}
        def W(i):
            if i in cache: return cache[i]
            m=self.local_matrix(nodes[i]); 
            if i in parent: m=W(parent[i])@m
            cache[i]=m; return m
        return [W(i) for i in range(len(nodes))], parent
    def prims(self):
        """yield (node_idx, prim, pos(N,3), nrm, uv, idx(M,3)) in LOCAL mesh space"""
        for ni,n in enumerate(self.js['nodes']):
            if 'mesh' not in n: continue
            for p in self.js['meshes'][n['mesh']]['primitives']:
                at=p['attributes']; pos=self.accessor(at['POSITION']).astype(np.float64)
                nrm=self.accessor(at['NORMAL']).astype(np.float64) if 'NORMAL' in at else None
                uv=self.accessor(at['TEXCOORD_0']).astype(np.float64) if 'TEXCOORD_0' in at else None
                idx=self.accessor(p['indices']).astype(np.int64).reshape(-1,3) if 'indices' in p else np.arange(len(pos)).reshape(-1,3)
                yield ni,p,pos,nrm,uv,idx
    def world_bounds(self):
        W,_=self.world_matrices(); lo=np.full(3,1e18); hi=np.full(3,-1e18)
        for ni,p,pos,*_ in self.prims():
            wp=(W[ni][:3,:3]@pos.T).T+W[ni][:3,3]; lo=np.minimum(lo,wp.min(0)); hi=np.maximum(hi,wp.max(0))
        return lo,hi
    def anchors(self):
        W,_=self.world_matrices(); out={}
        for i,n in enumerate(self.js['nodes']):
            nm=n.get('name','')
            if nm.startswith(('engine_','laserpoint_','light_position')) : out[nm]=W[i][:3,3].copy()
        return out

def save_glb(js, bin_chunks_by_bv, path):
    """bin_chunks_by_bv: list of bytes, one per bufferView (already ordered). Rebuilds offsets."""
    out=bytearray(); bvs=js['bufferViews']
    for i,bv in enumerate(bvs):
        while len(out)%4: out.append(0)
        data=bin_chunks_by_bv[i]; bv['byteOffset']=len(out); bv['byteLength']=len(data); bv['buffer']=0
        out+=data
    while len(out)%4: out.append(0)
    js['buffers']=[{'byteLength':len(out)}]
    jb=json.dumps(js,separators=(',',':')).encode()
    while len(jb)%4: jb+=b' '
    total=12+8+len(jb)+8+len(out)
    with open(path,'wb') as f:
        f.write(struct.pack('<4sII',b'glTF',2,total))
        f.write(struct.pack('<II',len(jb),0x4E4F534A)); f.write(jb)
        f.write(struct.pack('<II',len(out),0x004E4942)); f.write(bytes(out))
