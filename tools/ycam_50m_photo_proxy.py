#!/usr/bin/env python3
"""Score 50 million six-parameter CIELAB photo-chart quadratic candidates.
This does NOT render 50 million images, prove Apple ISP color matching, or
modify any YCam recipe. Matrices come from user's iPhone16Pro captures only.
"""
import os,sys,re,time,json,pathlib,datetime,argparse
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parent.parent
SOURCE=ROOT/"calibration/iphone16pro_50m_sufficient_stats.json"
OUT=ROOT/"reports/iphone16pro_50m"
KEYS=("exposure","contrast","saturation","temperature","tint","whiteRoll")
def expand(q):
    m=np.zeros((6,6),float)
    i,j=np.triu_indices(6)
    a=np.asarray(q["Hupper"],dtype=float)
    assert len(a)==21
    m[i,j]=a;m[j,i]=a
    return m,np.asarray(q["g"],dtype=float),float(q["c"])
def source_matches(name,recipe):
    s=(ROOT/"Styles.swift").read_text(encoding="utf-8")
    rows=[l for l in s.splitlines() if l.strip().startswith("case ."+name+": return LookRecipe(")]
    if len(rows)!=1:return False
    for key,v in zip(KEYS,recipe):
        m=re.search(r"\b"+key+r":\s*(-?[0-9.]+)",rows[0])
        if not m or abs(float(m.group(1))-float(v))>.000002:return False
    return True
def save(report):
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/"latest.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    n=report["actual_surrogate_comparisons"]
    line=f"Actual surrogate candidate scores: {n:,}/50,000,000; status={report['status']}"
    print(line,flush=True)
    s=os.getenv("GITHUB_STEP_SUMMARY")
    if s:
        with open(s,"a",encoding="utf-8") as f:
            f.write("## iPhone 16 Pro color-chart checks\n\n"+line+"\n\n"
            "These are **first-order six-parameter mathematical color-model comparisons**, not "
            "50 million iPhone renders or Apple-fidelity measurements. No camera recipes were changed.\n")
    return 0
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--target",type=int,default=50_000_000)
    p.add_argument("--seconds",type=int,default=155)
    a=p.parse_args()
    if a.target!=50_000_000:raise SystemExit("This workflow requires 50M candidate target")
    d=json.loads(SOURCE.read_text(encoding="utf-8"))
    now=datetime.datetime.now(datetime.timezone.utc)
    cutoff=datetime.datetime.fromisoformat(d["deadline_utc"].replace("Z","+00:00"))
    report={"schema":1,"started_utc":now.isoformat(),"cutoff_utc":cutoff.isoformat(),
      "run_id":os.getenv("GITHUB_RUN_ID","local"),"github_sha":os.getenv("GITHUB_SHA"),
      "requested_surrogate_comparisons":a.target,"actual_surrogate_comparisons":0,
      "iPhone_photos_rendered":0,"new_photos_captured":0,"real_Apple_YCam_photo_pairs":0,
      "filters_modified":False,"model":"Six-parameter first-order weighted photo-chart CIELAB quadratic surrogate",
      "verified_style_to_photo_pairs":False,"limitations":d["limitations"],"styles":{}}
    if now>=cutoff:
        report["status"]="CUTOFF_REACHED_NO_CALIBRATION"
        return save(report)
    rng=np.random.default_rng(int(os.getenv("GITHUB_RUN_ID","20261117")))
    bounds=np.asarray(d["bounds"],dtype=float)
    started=time.monotonic()
    for name,item in d["styles"].items():
        goal=a.target//len(d["styles"])
        if not source_matches(name,item["base"]):
            report["styles"][name]={"status":"RECIPE_CHANGED_SINCE_REFERENCE","actual":0}
            continue
        H,g,c=expand(item["train"])
        Hv,gv,cv=expand(item["val"])
        center=np.clip(-np.linalg.solve(H,g),-bounds,bounds)
        best=np.zeros(6);bestscore=0.
        done=0
        while done<goal:
            if time.monotonic()-started>a.seconds:break
            n=min(250000,goal-done)
            points=rng.uniform(-1,1,(n,6))*bounds
            local=int(n*.70)
            points[:local]=np.clip(center+rng.normal(0,.20,(local,6))*bounds,-bounds,bounds)
            scores=np.einsum("ij,jk,ik->i",points,H,points,optimize=True)+2*(points@g)
            k=int(np.argmin(scores))
            if float(scores[k])<bestscore:best=points[k].copy();bestscore=float(scores[k])
            done+=n
        conservative=best*.20
        change=float(conservative@Hv@conservative+2*(conservative@gv))
        report["styles"][name]={"status":"COMPLETE" if done==goal else "PARTIAL",
          "actual":done,"requested":goal,"reference_image":item["photo"],
          "rgb_chart_positions":d["color_positions"],"train_positions":d["train_positions"],
          "heldout_positions":d["validation_positions"],
          "baseline_heldout_squared_lab_proxy":round(cv,6),
          "candidate_heldout_squared_lab_proxy":round(cv+change,6),
          "change_percent":round(change/cv*100,5),
          "candidate_parameter_delta_only":np.round(conservative,8).tolist(),
          "requires_full_CoreImage_and_real_photo_check":True}
        report["actual_surrogate_comparisons"]+=done
        print(name,done,"proxy validation",round(cv,4),"->",round(cv+change,4),flush=True)
    report["elapsed_compute_seconds"]=round(time.monotonic()-started,3)
    report["status"]="FULL_TARGET" if report["actual_surrogate_comparisons"]==a.target else "PARTIAL_OR_STALE_REFERENCE"
    return save(report)
if __name__=="__main__":sys.exit(main())
