"""Ship upgrade pipeline: materials (PBR), missing-diffuse synthesis, nav-light additions.
All additions are placed in ONE extra node ('addon_navlights'); existing nodes/anchors are untouched."""
import io, os, sys, json, copy, glob, numpy as np
from PIL import Image, ImageFilter
from glbtool import GLB, save_glb

# ---------------- tunables ----------------
METAL_MAX       = 0.55   # max metalness baked into the B channel (keep <0.7 unless you have reflection probes / sky env)
ROUGH_MIN, ROUGH_MAX = 0.28, 0.82
EMISSIVE_STRENGTH = 1.6  # KHR_materials_emissive_strength (Godot: emission_energy_multiplier)
NAV_RADIUS_FRAC = 0.011  # nav-light radius as fraction of ship length
NAV_EMISSIVE    = 7.0

# hull tints for ships whose base-color texture is missing (sibling = copy mean color from that ship's diffuse)
MISSING_DIFFUSE = {
    'aegis-veteran':                 dict(sibling='aegis'),
    'goliath-double-winged':         dict(sibling='goliath'),
    'goliath-reversed-angled-wings': dict(sibling='goliath-angled-wings'),
    'tartarus':                      dict(tint=(176,182,194)),
    'mimesis':                       dict(tint=(150,152,166)),
    'pet-mirage':                    dict(tint=(150,158,168)),
    'pet-pusat':                     dict(tint=(150,158,168)),
}
ORGANIC = {'turkey','curcubitor','curcubitor-boss','kucurbium-boss','lordakia','lordakia-boss','lordakium','lordakium-boss',
           'lordakium-emperor','devourer','cubikon','sibelonit','saimon','saimon-boss'}
CRYSTAL = {'kristallin','kristallon','kristallon-emperor'}
def profile(name):
    return 'crystal' if name in CRYSTAL else 'organic' if name in ORGANIC else 'metal'
SKIP_NAV = {'aegis','aegis-veteran','citadel','bigboy','defcom','devolarium'}   # odd frames / untextured placeholders

def png_bytes(arr):
    b=io.BytesIO(); Image.fromarray(arr).save(b,'PNG',optimize=True); return b.getvalue()

def extracted_names(glbname, js):
    """Godot (extract textures) file names: <glb>_<image name>.png ; later duplicates get _<imageIndex>"""
    seen={}; out={}
    for i,im in enumerate(js.get('images',[])):
        nm=im.get('name',f'image{i}')
        if nm in seen: out[i]=f'{glbname}_{nm}_{i}.png'
        else: seen[nm]=i; out[i]=f'{glbname}_{nm}.png'
    return out

def img_arr(g,i,mode='RGBA'): return np.array(g.image(i).convert(mode))

def tex_img(js,ti): return None if ti is None else js['textures'][ti]['source']

def build_mr(spec_rgba, old_mr_rgb, prof='metal'):
    """spec alpha (gloss-like strength) -> proper roughness (G) + metalness (B). R=255 (unused AO slot)."""
    if spec_rgba is not None and spec_rgba[...,3].max()>0: s=spec_rgba[...,3].astype(np.float32)/255.
    else: s=1.0-old_mr_rgb[...,1].astype(np.float32)/255.
    used = s>0.02                                   # ignore empty UV space
    p = np.percentile(s[used],98) if used.any() else 1.0
    sn = np.clip(s/max(p,1e-3),0,1)
    rmin,rmax,mmax={'metal':(ROUGH_MIN,ROUGH_MAX,METAL_MAX),'organic':(0.45,0.85,0.0),'crystal':(0.10,0.42,0.0)}[prof]
    rough = np.clip(rmax-(rmax-rmin)*sn, rmin, rmax)
    metal = np.clip((sn-0.35)/0.45,0,1)**1.2*mmax
    # empty UV space: neutral
    rough[~used]=0.8; metal[~used]=0.0
    out=np.empty(s.shape+(3,),np.uint8)
    out[...,0]=255; out[...,1]=(rough*255).round(); out[...,2]=(metal*255).round()
    return out

def synth_diffuse(spec_rgba, normal_rgb, glow_rgb, tint):
    h,w=normal_rgb.shape[:2]
    s=(spec_rgba[...,3].astype(np.float32)/255.) if spec_rgba is not None else np.full((h,w),0.4,np.float32)
    used=s>0.02; p=np.percentile(s[used],98) if used.any() else 1.0
    detail=np.clip(s/max(p,1e-3),0,1)
    n=(normal_rgb.astype(np.float32)/255.-0.5)*2
    edge=np.clip(np.hypot(n[...,0],n[...,1])*1.4,0,1)       # slope magnitude -> panel edges / ridges
    edge=np.array(Image.fromarray((edge*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32)/255.
    lum=0.42+0.70*detail**0.9
    lum=lum*(1-0.28*edge)
    col=np.array(tint,np.float32)[None,None,:]/255.*lum[...,None]
    g=glow_rgb.astype(np.float32)/255.
    col=col*(1-np.clip(g.max(axis=2,keepdims=True)*1.5,0,0.85))       # darken under lit areas so glow reads
    # calibrate: mean colour over the used UV area must equal the target tint
    cur=col[used].mean(0); tgt=np.array(tint,np.float32)/255.
    col=col*np.clip(tgt/np.maximum(cur,1e-3),0.4,3.0)[None,None,:]
    col[~used]=tgt*0.7
    return np.clip(col*255,0,255).astype(np.uint8)

# --------------- geometry helpers ---------------
def octa(r):
    v=np.array([[r,0,0],[-r,0,0],[0,r,0],[0,-r,0],[0,0,r],[0,0,-r]],np.float32)
    f=np.array([[0,2,4],[2,1,4],[1,3,4],[3,0,4],[2,0,5],[1,2,5],[3,1,5],[0,3,5]],np.uint16)
    n=v/np.linalg.norm(v,axis=1,keepdims=True)
    return v,n.astype(np.float32),f

def hull_points(g):
    W,_=g.world_matrices(); P=[]
    for ni,p,pos,*_ in g.prims():
        mname=g.js['materials'][p['material']]['name'] if 'material' in p else ''
        if mname.startswith('null~'): continue
        P.append((W[ni][:3,:3]@pos.T).T+W[ni][:3,3])
    return np.concatenate(P)

def nav_positions(P):
    lo=P.min(0); hi=P.max(0); L=hi[2]-lo[2]; r=NAV_RADIUS_FRAC*L
    def top_of(mask):
        idx=np.where(mask)[0]; return P[idx[np.argmax(P[idx,1])]]
    port = top_of(P[:,0]<=lo[0]+0.02*L)           # -X
    star = top_of(P[:,0]>=hi[0]-0.02*L)           # +X
    tail = top_of(P[:,2]>=hi[2]-0.01*L)           # rear (+Z)
    lift=np.array([0,0.6*r,0])
    inward=lambda p,sgn: p+np.array([sgn*0.7*r,0,0])
    return r, [('red',inward(port,+1)+lift),('green',inward(star,-1)+lift),('white',tail+lift+np.array([0,0,-0.7*r]))]

NAV_MATS={'red':([0.25,0.02,0.02,1],[1.0,0.05,0.05]),'green':([0.02,0.25,0.05,1],[0.05,1.0,0.15]),'white':([0.5,0.5,0.55,1],[1.0,0.95,0.9])}

def add_nav(js, chunks, positions, r):
    tn=js['nodes']; mats=js.setdefault('materials',[])
    prims=[]
    for color,pos in positions:
        v,n,f=octa(r); v=v+pos.astype(np.float32)
        bi=len(js['bufferViews']); chunks.append(v.tobytes()); js['bufferViews'].append({'buffer':0,'byteOffset':0,'byteLength':0,'target':34962})
        chunks.append(n.tobytes()); js['bufferViews'].append({'buffer':0,'byteOffset':0,'byteLength':0,'target':34962})
        chunks.append(f.reshape(-1).tobytes()); js['bufferViews'].append({'buffer':0,'byteOffset':0,'byteLength':0,'target':34963})
        ai=len(js['accessors'])
        js['accessors'] += [
          {'bufferView':bi,'componentType':5126,'count':6,'type':'VEC3','min':v.min(0).tolist(),'max':v.max(0).tolist()},
          {'bufferView':bi+1,'componentType':5126,'count':6,'type':'VEC3'},
          {'bufferView':bi+2,'componentType':5123,'count':24,'type':'SCALAR'}]
        mi=None
        for k,m in enumerate(mats):
            if m.get('name')==f'addon_nav_{color}': mi=k
        if mi is None:
            bc,em=NAV_MATS[color]; mi=len(mats)
            mats.append({'name':f'addon_nav_{color}','pbrMetallicRoughness':{'baseColorFactor':bc,'metallicFactor':0.0,'roughnessFactor':0.4},
                         'emissiveFactor':em,'extensions':{'KHR_materials_emissive_strength':{'emissiveStrength':NAV_EMISSIVE}}})
        prims.append({'attributes':{'POSITION':ai,'NORMAL':ai+1},'indices':ai+2,'material':mi,'mode':4})
    ensure_ext(js,'KHR_materials_emissive_strength')
    js['meshes'].append({'name':'addon_navlights','primitives':prims})
    ni=len(tn); tn.append({'name':'addon_navlights','mesh':len(js['meshes'])-1})
    js['scenes'][js.get('scene',0)]['nodes'].append(ni)

def ensure_ext(js,name):
    u=js.setdefault('extensionsUsed',[])
    if name not in u: u.append(name)

# --------------- per-ship ---------------
def process(path, outdir, sibling_mean=None, log=None):
    name=os.path.basename(path)[:-4]; g=GLB(path); js=copy.deepcopy(g.js)
    chunks=[g.bv_bytes(i) for i in range(len(js['bufferViews']))]
    newfiles={}; info=dict(name=name,mr=0,emissive=0,diffuse=False,nav=False)
    enames=extracted_names(name,js)
    mats=js.get('materials',[])
    if not any('images' in js and m.get('pbrMetallicRoughness',{}).get('metallicRoughnessTexture') for m in mats):
        pass
    done_mr={}; diffuse_cache={}
    for m in mats:
        pbr=m.setdefault('pbrMetallicRoughness',{}); ext=m.get('extensions',{})
        mr_t=pbr.get('metallicRoughnessTexture',{}).get('index'); mr_i=tex_img(js,mr_t)
        if mr_i is None: continue
        spec_t=ext.get('KHR_materials_specular',{}).get('specularTexture',{}).get('index'); spec_i=tex_img(js,spec_t)
        spec=img_arr(g,spec_i) if spec_i is not None else None
        if mr_i not in done_mr:
            new=build_mr(spec,img_arr(g,mr_i,'RGB'),profile(name)); b=png_bytes(new)
            chunks[js['images'][mr_i]['bufferView']]=b; newfiles[enames[mr_i]]=b; done_mr[mr_i]=True; info['mr']+=1
        pbr['metallicFactor']=1.0 if profile(name)=='metal' else 0.0
        # emissive
        em_t=m.get('emissiveTexture',{}).get('index'); em_i=tex_img(js,em_t)
        if em_i is not None:
            gm=img_arr(g,em_i,'RGB').mean()
            if profile(name)=='metal' and 1.0<gm<20.0:   # sparse light patches only; big glowing surfaces would blow out
                m.setdefault('extensions',{})['KHR_materials_emissive_strength']={'emissiveStrength':EMISSIVE_STRENGTH}; ensure_ext(js,'KHR_materials_emissive_strength'); info['emissive']+=1
        # missing base color -> synthesize
        if 'baseColorTexture' not in pbr and name in MISSING_DIFFUSE:
            cfg=MISSING_DIFFUSE[name]; tint=cfg.get('tint') or sibling_mean
            nm_t=m.get('normalTexture',{}).get('index'); nm_i=tex_img(js,nm_t)
            key=(spec_i,nm_i,em_i)
            if key not in diffuse_cache:
                normal=img_arr(g,nm_i,'RGB'); glow=img_arr(g,em_i,'RGB') if em_i is not None else np.zeros_like(normal)
                sp=spec
                if glow.shape!=normal.shape: glow=np.array(Image.fromarray(glow).resize(normal.shape[1::-1]))
                if sp is not None and sp.shape[:2]!=normal.shape[:2]: sp=np.array(Image.fromarray(sp).resize(normal.shape[1::-1]))
                d=png_bytes(synth_diffuse(sp,normal,glow,tint))
                bvi=len(js['bufferViews']); js['bufferViews'].append({'buffer':0,'byteOffset':0,'byteLength':0}); chunks.append(d)
                ii=len(js['images']); js['images'].append({'bufferView':bvi,'mimeType':'image/png','name':f'{name}_diffuse' if not diffuse_cache else f'{name}_diffuse_{len(diffuse_cache)+1}'})
                ti=len(js['textures']); js['textures'].append({'sampler':js['textures'][mr_t].get('sampler',0),'source':ii})
                diffuse_cache[key]=ti
                fn=f'{name}_{name}_diffuse.png' if len(diffuse_cache)==1 else f'{name}_{name}_diffuse_{len(diffuse_cache)}.png'
                newfiles[fn]=d
            pbr['baseColorTexture']={'index':diffuse_cache[key]}; pbr['baseColorFactor']=[1,1,1,1]; info['diffuse']=True
    # nav lights
    has_engine=any(n.get('name','').startswith('engine_') for n in js['nodes'])
    textured=info['mr']>0
    if has_engine and textured and name not in SKIP_NAV and profile(name)=='metal':
        P=hull_points(g); r,pos=nav_positions(P); add_nav(js,chunks,pos,r); info['nav']=True
    if info['mr'] or info['nav']:
        os.makedirs(outdir,exist_ok=True); save_glb(js,chunks,os.path.join(outdir,name+'.glb'))
        for fn,b in newfiles.items(): open(os.path.join(outdir,fn),'wb').write(b)
    return info

def mean_color(glbpath):
    g=GLB(glbpath)
    for m in g.js['materials']:
        t=m.get('pbrMetallicRoughness',{}).get('baseColorTexture',{}).get('index')
        if t is None: continue
        a=img_arr(g,tex_img(g.js,t),'RGB').astype(np.float32)
        st=m.get('extensions',{}).get('KHR_materials_specular',{}).get('specularTexture',{}).get('index'); si=tex_img(g.js,st)
        if si is not None:
            sp=img_arr(g,si)[...,3]
            if sp.shape!=a.shape[:2]: sp=np.array(Image.fromarray(sp).resize(a.shape[1::-1]))
            used=sp>5
        else: used=a.sum(2)>30
        return tuple(int(x) for x in a[used].mean(0))
    return (150,155,165)

NON_SHIP=('building-','asset-mmo','jumpgate','drone_','hitac')
if __name__=='__main__':
    src=sys.argv[1]; out=sys.argv[2]; only=sys.argv[3:] 
    files=sorted(glob.glob(os.path.join(src,'*.glb')))
    infos=[]
    for f in files:
        nm=os.path.basename(f)[:-4]
        if nm.startswith(NON_SHIP): continue
        if only and nm not in only: continue
        sib=None
        if nm in MISSING_DIFFUSE and 'sibling' in MISSING_DIFFUSE[nm]:
            sib=mean_color(os.path.join(src,MISSING_DIFFUSE[nm]['sibling']+'.glb'))
        infos.append(process(f,out,sib))
    json.dump(infos,open(os.path.join(out,'_report.json'),'w'),indent=1)
    for i in infos: print(i)
