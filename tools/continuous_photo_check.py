#!/usr/bin/env python3
"""Licensed Commons photo sampling for YCam. Ordinary photos cannot prove factory color accuracy."""
import argparse, hashlib, io, json, os, re, sys, time, urllib.parse, urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
import numpy as np
from PIL import Image, ImageOps
import style_check as ycam

ROOT=Path(__file__).resolve().parent.parent
API="https://commons.wikimedia.org/w/api.php"
USER_AGENT="YCam-Color-Research/1.0 (https://github.com/yimweixiang06-create/YCam; public)"
SCENES=[
    "blue sky clouds","sunset landscape","portrait human face","people outdoors",
    "green leaves trees","flowers garden","architecture buildings","city street",
    "night city lights","low light photography","mountain landscape","ocean beach",
    "animals wildlife","interior room","snow winter landscape","black and white photograph",
    "food photography","market street photography","waterfall river","autumn trees"]
MIMES={"image/jpeg","image/png","image/webp"}
MAX_BYTES=1500000

def api_pages(term, offset):
    params={"action":"query","format":"json","formatversion":2,"generator":"search",
            "gsrsearch":term,"gsrnamespace":6,"gsrlimit":50,"gsroffset":offset,
            "prop":"imageinfo","iiprop":"url|mime|sha1|extmetadata","iiurlwidth":320}
    url=API+"?"+urllib.parse.urlencode(params)
    request=urllib.request.Request(url,headers={"User-Agent":USER_AGENT,"Accept":"application/json"})
    with urllib.request.urlopen(request,timeout=12) as stream:
        return json.load(stream).get("query",{}).get("pages",[])

def permitted_license(info):
    meta=info.get("extmetadata") or {}
    raw=(meta.get("LicenseShortName",{}).get("value") or "").lower().strip()
    val=re.sub(r"[\s_]+","-",raw)
    forbidden=("by-nc","by-nd","no-derivatives","non-commercial")
    allowed=("cc0" in val or "public-domain" in val or "public domain" in raw or
             bool(re.search(r"cc-by(?:-sa)?(?:-|\b)",val)))
    return bool(allowed and not any(x in val for x in forbidden)),raw

def download_pixels(url,timeout):
    parsed=urllib.parse.urlparse(url)
    if parsed.scheme!="https" or parsed.hostname not in {"upload.wikimedia.org","commons.wikimedia.org"}:
        raise ValueError("Image host not approved")
    req=urllib.request.Request(url,headers={"User-Agent":USER_AGENT})
    with urllib.request.urlopen(req,timeout=timeout) as stream:
        if stream.headers.get("Content-Type","").split(";")[0].strip() not in MIMES:
            raise ValueError("Image MIME not approved")
        content=stream.read(MAX_BYTES+1)
    if len(content)>MAX_BYTES:
        raise ValueError("Photo exceeds byte limit")
    with Image.open(io.BytesIO(content)) as image:
        if image.format not in {"JPEG","PNG","WEBP"}:
            raise ValueError("Photo format not approved")
        im=ImageOps.exif_transpose(image).convert("RGB")
        im.thumbnail((48,48))
        if min(im.size)<16:
            raise ValueError("Photo too small")
        return np.asarray(im,dtype=np.float64).reshape(-1,3)/255,hashlib.sha256(content).hexdigest()

def recipes_from_swift():
    s=(ROOT/"Styles.swift").read_text(encoding="utf-8")
    styles=s.split("enum CameraStyle:",1)[1].split("// MARK: - 人像光效",1)[0]
    filters=s.split("enum AppleFilter:",1)[1]
    def parse(s):
        section=s.split("var recipe: LookRecipe {",1)[1].split("\n    }\n",1)[0]
        out={}
        for name,body in re.findall(r"case \.(\w+): return LookRecipe\((.*)\)\s*$",section,re.M):
            recipe=dict(ycam.IDENT)
            for part in ycam.split_top(body):
                k,v=[z.strip() for z in part.split(":",1)]
                recipe[k]=tuple(float(t) for t in v[4:-1].split(",")) if v.startswith("rgb(") else float(v)
            out[name]=recipe
        return out
    a,b=parse(styles),parse(filters)
    if len(a)!=28 or len(b)!=10:
        raise ValueError("Expected 28 styles and 10 filters; got %d and %d"%(len(a),len(b)))
    return list(a.items())+[("filter:"+name,recipe) for name,recipe in b.items()]

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--target",type=int,default=200)
    p.add_argument("--seconds",type=int,default=150)
    p.add_argument("--offline",action="store_true")
    a=p.parse_args()
    if a.target!=200: raise ValueError("This check is configured for 200 real photos per run")
    reportdir=ROOT/"reports"/"continuous"
    reportdir.mkdir(parents=True,exist_ok=True)
    state=ROOT/".cache"/"ycam_photo_seen.json"
    state.parent.mkdir(parents=True,exist_ok=True)
    restored=state.exists()
    try:
        history=json.loads(state.read_text()) if restored else []
        if not isinstance(history,list): raise ValueError("history is not a list")
    except (OSError,ValueError):
        history=[]
        restored=False
    seen=set(history[-80000:])
    effect_pairs=recipes_from_swift()
    effect_names=[name for name,_ in effect_pairs]
    recipes=dict(effect_pairs)
    lut_names=ycam.lut_names()
    luts={name:ycam.load_lut(lut) for name,lut in lut_names.items()}
    counts=Counter()
    rejects=Counter()
    samples=[]
    deadline=time.monotonic()+a.seconds
    slot=int(time.time()//300)
    scenes=SCENES[slot%len(SCENES):]+SCENES[:slot%len(SCENES)]
    if not a.offline:
        for index,query in enumerate(scenes):
            if len(samples)>=a.target or time.monotonic()>=deadline: break
            offset=((slot//len(scenes)+index)%8)*50
            try: pages=api_pages(query,offset)
            except Exception as e:
                rejects["search_"+type(e).__name__]+=1
                continue
            for page in pages:
                if len(samples)>=a.target or time.monotonic()>=deadline: break
                info=(page.get("imageinfo") or [{}])[0]
                if info.get("mime") not in MIMES:
                    rejects["mime"]+=1
                    continue
                allowed,license_name=permitted_license(info)
                if not allowed:
                    rejects["unknown_or_restricted_license"]+=1
                    continue
                file_id=info.get("sha1")
                if not file_id or file_id in seen:
                    rejects["duplicate_or_missing_id"]+=1
                    continue
                url=info.get("thumburl")
                if not url:
                    rejects["missing_thumbnail"]+=1
                    continue
                try:
                    pixels,sha256=download_pixels(url,min(10,max(2,deadline-time.monotonic())))
                    name=min(effect_names,key=lambda n:(counts[n],effect_names.index(n)))
                    if name in luts:
                        output=ycam.lut_apply(luts[name],pixels)
                    else:
                        output=ycam.transform(pixels,ycam.effective(recipes[name]))
                    de=float(np.linalg.norm(ycam.lab(output)-ycam.lab(pixels),axis=1).mean())
                    clipping=float(((output<0.003)|(output>0.997)).any(axis=1).mean())
                    if not np.isfinite(de) or not np.isfinite(clipping):
                        raise ValueError("Non-finite color metrics")
                except Exception as e:
                    rejects["image_or_metrics_"+type(e).__name__]+=1
                    continue
                seen.add(file_id)
                counts[name]+=1
                samples.append({
                    "title":page.get("title"),"source":info.get("descriptionurl"),
                    "license":license_name,"source_file_sha1":file_id,"download_sha256":sha256,
                    "search_theme":query,"assigned_effect":name,
                    "deltaE76_vs_input_not_accuracy_error":round(de,3),
                    "near_clipping_fraction":round(clipping,4),"verified_official_pair":False})
    # Cache restores recent accepted source IDs; a missing cache means only within-run novelty is established.
    state.write_text(json.dumps((history+[x["source_file_sha1"] for x in samples])[-80000:]),encoding="utf-8")
    report={
        "run_utc":datetime.now(timezone.utc).isoformat(),"target":a.target,
        "actual_valid_unique":len(samples),"seen_cache_restored":restored,
        "dedup_scope":"run plus restored recent history" if restored else "current run only",
        "category_count":len(effect_names),"counts":{name:counts[name] for name in effect_names},
        "reject_reasons":dict(rejects),"official_paired_references":0,
        "auto_color_change":False,"ipa_published":False,
        "warning":"Delta E is change from raw image to YCam approximation, NOT error versus Apple/Fuji/Kodak reference.",
        "samples":samples}
    (reportdir/"latest.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    tab="\n".join("| "+n+" | "+str(counts[n])+" |" for n in effect_names)
    md=("# YCam 每 5 分钟照片检查\n\n"+
        "- 目标：200 张；本轮实际取得、合法许可、去重并分析："+str(len(samples))+" 张。\n"+
        "- 去重范围："+report["dedup_scope"]+"。\n"+
        "- 官方同场景可信配对：0；不能据此自动调整 Swift/LUT 或发布 IPA。\n"+
        "- Delta E 是效果变化幅度，不是与原厂效果的准确度误差。\n"+
        "- 如不足 200，必须按实际数量报告，详情见 JSON 拒绝原因。\n\n"+
        "| 风格/滤镜 | 本轮有效照片数 |\n|---|---:|\n"+tab+"\n")
    (reportdir/"latest.md").write_text(md,encoding="utf-8")
    summary=os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary,"a",encoding="utf-8") as f: f.write(md)
    print("YCam photos %d/%d, categories %d, cache restored=%s"%(len(samples),a.target,len(effect_names),restored))
    print("Rejected:",dict(rejects))
    return 0

if __name__=="__main__":
    sys.exit(main())
