#!/usr/bin/env python3
"""Read named HDF5 report fields without Julia nested-Dict reconstruction.

Bypasses JLD2 0.4.55's erroneous Dict{Symbol,AbstractDict} reconstruction of
scalar tolerance dictionaries. Stored numbers and type declarations are untouched.
"""
import argparse
import csv
import json
import re
from pathlib import Path
import h5py
import numpy as np

class Reader:
    def __init__(self, f, configuration):
        self.f=f; self.tolerances={}
        # Nested serialized tolerance dictionaries are inconsistent. Recover the
        # actual solver tolerances from its independent pre-run config snapshot.
        config=next(line for line in configuration.splitlines() if line.startswith("config="))
        num=r"([0-9.eE+\-]+)"
        for model in ("Reservoir","Injector"):
            match=re.search(":"+model+r" => Dict\{Symbol, Any\}\(:default => "+num+r", :mass_conservation => \(CNV = "+num+r", MB = "+num+r"\)\)",config)
            if not match: raise ValueError(f"Cannot verify {model} tolerances from configuration")
            self.tolerances[model]=dict(default=float(match[1]),CNV=float(match[2]),MB=float(match[3]))
        match=re.search(r":Facility => Dict\{Symbol, Any\}\(:default => "+num+r"\)",config)
        if not match: raise ValueError("Cannot verify facility tolerance")
        self.tolerances["Facility"]=dict(default=float(match[1]))
    def raw(self,x): return self.f[x][()] if isinstance(x,h5py.Reference) else x
    def text(self,x):
        x=self.raw(x); return x.decode() if isinstance(x,bytes) else str(x)
    def ordered(self,x):
        x=self.raw(x)
        return {self.text(k):v for k,v in zip(self.raw(x["keys"]),self.raw(x["vals"]))}
    def sequence(self,x):
        x=self.raw(x)
        if isinstance(x,np.void): return [x[k] for k in x.dtype.names]
        if isinstance(x,np.ndarray): return list(x.ravel())
        return [x]
    def dictionary(self,x):
        x=self.raw(x); rows=self.raw(x["kvvec"])
        d={}
        for row in rows:
            row=self.raw(row)
            d[self.text(row["first"])]=self.raw(row["second"])
        return d
    def worst(self,step):
        worst=(-float("inf"),"","","","",float("nan"),float("nan"))
        if "errors" not in step: return worst
        for model,eqs in self.ordered(step["errors"]).items():
            for eq in self.raw(eqs):
                eq=self.raw(eq);tols=self.tolerances[model]
                criteria=eq["criterions"]
                for name in criteria.dtype.names:
                    values=criteria[name];tol=float(tols.get(name,tols["default"]))
                    for phase,error in zip(self.sequence(values["names"]),self.sequence(values["errors"])):
                        error=float(self.raw(error));ratio=error/tol
                        if ratio>worst[0]: worst=(ratio,model,self.text(eq["name"]),name,self.text(phase),error,tol)
        return worst

def main():
    ap=argparse.ArgumentParser();ap.add_argument("root",type=Path);ap.add_argument("out",type=Path);a=ap.parse_args()
    miniout=a.out.with_name(a.out.stem+"_ministeps.csv")
    errors=[]
    with a.out.open("x",newline="") as f,miniout.open("x",newline="") as mf:
        w=csv.writer(f); mw=csv.writer(mf)
        w.writerow(["member","block","saved_step","time_days","ministep_attempts","successful_ministeps","failed_ministep_attempts","final_ministep_success","total_solver_seconds","min_internal_dt_days","max_internal_dt_days","newton_updates"])
        mw.writerow(["member","block","saved_step","attempt","start_day","dt_days","success","newton_updates","last_max_error_over_tolerance","worst_model","worst_equation","worst_criterion","worst_phase","last_error","criterion_tolerance"])
        for member in range(1,129):
            for block in range(1,13):
                path=a.root/"members"/f"{member:03}"/f"block_{block:02}.jld2"
                if not path.exists(): continue
                try:
                    with h5py.File(path) as h:
                        rd=Reader(h,(path.parent/"configuration.txt").read_text())
                        for step,ref in enumerate(h["reports"][:],1):
                            outer=rd.ordered(ref);mins=rd.raw(outer["ministeps"])
                            success=[];dts=[];nit=0;time=(block-1)*80+(step-1)*8
                            for attempt,mini in enumerate(mins,1):
                                m=rd.ordered(mini);ok=bool(rd.raw(m["success"]));dt=float(rd.raw(m["dt"]))/86400
                                ss=rd.raw(m["steps"])
                                n=sum("update_time" in rd.ordered(s) for s in ss)
                                last=rd.ordered(ss[-1]) if len(ss) else {}
                                worst=rd.worst(last)
                                if ok:
                                    assert bool(rd.raw(last["converged"])) and worst[0]<1,"Accepted step fails independent convergence check"
                                mw.writerow([member,block,step,attempt,time,dt,ok,n,*worst])
                                success.append(ok);dts.append(dt);nit+=n
                                if ok:time+=dt
                            w.writerow([member,block,step,(block-1)*80+step*8,len(mins),sum(success),len(mins)-sum(success),success[-1],float(rd.raw(outer["total_time"])),min(dts),max(dts),nit])
                            assert abs(time-((block-1)*80+step*8))<1e-7,"Accepted ministeps do not sum to saved time"
                except Exception as ex:
                    errors.append(dict(path=str(path),error=f"{type(ex).__name__}: {ex}"))
    a.out.with_name(a.out.stem+"_reader_validation.json").write_text(json.dumps(dict(
        method="Named HDF5 scalar/reference decoding; original files untouched. Tolerances recovered from independent runtime configuration because nested serialized tolerance dictionaries are inconsistent.",
        independent_checks="Accepted ministeps sum to each eight-day interval; compare Newton counts with original stdout",
        errors=errors),indent=2)+"\n")
    if errors: raise RuntimeError(errors)

if __name__=="__main__":main()
