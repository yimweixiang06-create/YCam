#!/usr/bin/env python3
"""Per-image 10M candidate screening, 113 deduplicated iPhone16Pro uploads.

Each image has nine actual RGB samples (3x3) derived privately from the user's
screenshots/photos. The public repository contains only compressed sample RGB.
Reference is the GROUP MEDIAN of approximately scene-matched screenshots,
not a verified Standard iPhone16Pro capture nor a YCam paired render.
A candidate evaluation is a six-parameter quadratic RGB proxy score,
NOT a Core Image render. Do not modify Styles.swift from these diagnostics.
"""
import argparse,base64,datetime,json,os,pathlib,time,zlib
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parent.parent
DATA=ROOT/"calibration/iphone16pro_recovered_113_photo_samples.b85"
OUT=ROOT/"reports/iphone16pro_50m/images_10m.json"
CUTOFF=datetime.datetime(2026,11,18,7,0,tzinfo=datetime.timezone.utc)
GROUPS=["Apple_screenshot_whitepaper","Apple_screenshot_RGB_chart",
        "RGB_chart_screen_photo","YCam_app_UI"]
LIMITS=np.array([.018,.026,.030,.030,.030,.024],dtype=float)

def load():
    data=zlib.decompress(base64.b85decode(DATA.read_text(encoding="utf8").strip()))
    assert len(data)%34==0
    photos=[]
    for k in range(0,len(data),34):
        typ=data[k+6]; assert typ<len(GROUPS)
        photos.append({"id":data[k:k+6].hex(),"group":GROUPS[typ],
                       "rgb":np.frombuffer(data[k+7:k+34],dtype=np.uint8).reshape(9,3).copy()/255.})
    assert len(photos)==113
    return photos

def fit_matrices(b,obs):
    luma=b@np.array([.2126,.7152,.0722])
    J=np.zeros((9,3,6),dtype=float)
    J[:,:,0]=b*1.3
    J[:,:,1]=(b-.5)*1.1
    J[:,:,2]=(b-luma[:,None])*.9
    J[:,:,3]=[.15,.015,-.15]
    J[:,:,4]=[.07,-.12,.07]
    J[:,:,5]=-.45*np.maximum(b-.70,0.)
    diff=obs-b
    w=np.where(b.max(axis=1)>.98,.5,1.)[:,None]
    pairs=[]
    for sl in (slice(0,6),slice(6,9)):
        mat=(J[sl]*w[sl,:,None]).reshape(-1,6)
        goal=(diff[sl]*w[sl]).reshape(-1)
        pairs.append((mat.T@mat,-(mat.T@goal),float(goal@goal)))
    return pairs

def score_one(image,reference,run_no,seconds):
    (H,g,c),(Hv,gv,cv)=fit_matrices(reference,image["rgb"])
    Hr=H+np.eye(6)*.02
    try: center=np.clip(-np.linalg.solve(Hr,g),-LIMITS,LIMITS)
    except np.linalg.LinAlgError:center=np.zeros(6)
    rng=np.random.default_rng(int(image["id"],16)^run_no)
    found=np.zeros(6);best=c
    goal=10_000_000;count=0
    started=time.monotonic()
    while count<goal and time.monotonic()-started<seconds:
        n=min(200_000,goal-count)
        pts=rng.uniform(-1,1,(n,6))*LIMITS
        near=int(n*.7)
        pts[:near]=np.clip(center+rng.normal(0,.15,(near,6))*LIMITS,-LIMITS,LIMITS)
        values=np.einsum("ni,ij,nj->n",pts,Hr,pts,optimize=True)+2*(pts@g)+c
        idx=int(np.argmin(values))
        if float(values[idx])<best:
            best=float(values[idx]);found=pts[idx].copy()
        count+=n
    heldout=float(found@Hv@found+2*(gv@found)+cv)
    return {"image_id":image["id"],"reference_type":image["group"],
        "actual_candidate_comparisons":count,"requested_candidate_comparisons":goal,
        "status":"COMPLETE" if count==goal else "PARTIAL",
        "training_rgb_proxy_sse_before":round(c,8),
        "training_rgb_proxy_sse_after":round(best,8),
        "heldout_rgb_proxy_sse_before":round(cv,8),
        "heldout_rgb_proxy_sse_after":round(heldout,8),
        "heldout_proxy_improved":bool(heldout<cv),
        "suggested_delta_NOT_APPLIED":np.round(found,7).tolist(),
        "usable_as_official_apple_fidelity":False}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--images-per-run",type=int,default=10)
    parser.add_argument("--seconds",type=int,default=140)
    parser.add_argument("--offset",type=int,default=None)
    a=parser.parse_args()
    assert 1<=a.images_per_run<=12
    imgs=load()
    now=datetime.datetime.now(datetime.timezone.utc)
    rn=int(os.getenv("GITHUB_RUN_NUMBER","1"))
    start=(a.offset if a.offset is not None else (rn-1)*a.images_per_run)%len(imgs)
    batch=[imgs[(start+i)%len(imgs)] for i in range(a.images_per_run)]
    report={"schema":1,"run_id":os.getenv("GITHUB_RUN_ID","local"),
        "started_utc":now.isoformat(),"stop_utc":CUTOFF.isoformat(),
        "total_distinct_images":len(imgs),"images_selected":len(batch),
        "requested_per_image":10_000_000,"actual_candidate_comparisons":0,
        "physical_photos_rendered":0,"verified_Apple_YCam_pairs":0,
        "style_recipes_modified":False,"photos_uploaded_to_GitHub":False,
        "method":"Approximate 6-parameter RGB matching against 3x3 scene-relative group-median photo samples; NO official ISP claim.",
        "per_image":[]}
    if now>=CUTOFF:
        report["status"]="CUTOFF_NO_COMPUTE"
    else:
        medians={k:np.median(np.array([v["rgb"] for v in imgs if v["group"]==k]),axis=0) for k in GROUPS}
        starttime=time.monotonic()
        for img in batch:
            left=a.seconds-(time.monotonic()-starttime)
            if left<.3:break
            row=score_one(img,medians[img["group"]],rn,left)
            report["actual_candidate_comparisons"]+=row["actual_candidate_comparisons"]
            report["per_image"].append(row)
            print(img["id"],img["group"],f"{row['actual_candidate_comparisons']:,} actual comparisons",flush=True)
        report["elapsed_seconds"]=round(time.monotonic()-starttime,3)
        report["status"]="FULL_TARGET" if len(report["per_image"])==len(batch) and all(x["status"]=="COMPLETE" for x in report["per_image"]) else "PARTIAL"
    OUT.parent.mkdir(parents=True,exist_ok=True)
    OUT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    msg=f"{len(report['per_image'])}/{a.images_per_run} images; {report['actual_candidate_comparisons']:,} actually scored; {report['status']}"
    print(msg,flush=True)
    summary=os.getenv("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary,"a",encoding="utf8") as f:
            f.write("\n## Recovered iPhone16Pro image-by-image checks\n\n"+msg+"\n\n"
              "Scores are mathematical RGB image-feature proxies, **not Apple ISP or YCam full-image renders**. "
              "Camera recipes remain unchanged; unmatched capture settings cannot justify 1:1 color reproduction.\n")
if __name__=="__main__":main()
