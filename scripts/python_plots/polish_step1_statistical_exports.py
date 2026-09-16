#!/usr/bin/env python3
"""Polish saved step-1 statistical PNGs without recomputing numerical objects.

The complete single ECDF is supplied by the cache-only Julia exporter. Other
assets are edited only in recorded text regions, then optional header rows
are removed. The old grid legend overlaps an uncached curve, so its position
is preserved: moving it cannot faithfully reveal the obscured data from PNG.
"""
import argparse
import json
import shutil
from pathlib import Path
from PIL import ImageDraw
from relabel_step1_ecdf_exports import np, Image, draw_label, sha256
from refine_step1_statistical_exports import read_original, save_png

GRID_BOXES = {
    "grid_cdf_selected_1x3.png": {
        "green": [(551,737,667,807),(1804,737,1900,807),(3097,737,3212,807)],
        "blue": [(661,798,776,868),(1944,798,2040,868),(3252,798,3368,868)],
        "orange": [(459,789,574,868),(1699,789,1814,868),(3001,789,3116,868)],
    },
    "grid_cdf_4x3.png": {
        "green": [(463,469,568,530),(1469,469,1556,530),(2500,469,2605,530),(463,1073,568,1133),(1417,1073,1522,1133),(2371,1073,2476,1133),(504,1677,609,1737),(1525,1677,1630,1737),(2535,1677,2640,1737),(558,2280,663,2341),(1612,2280,1717,2341),(2645,2280,2750,2341)],
        "blue": [(550,525,654,585),(1567,525,1654,585),(2628,525,2733,585),(550,1129,654,1189),(1504,1129,1608,1189),(2458,1129,2563,1189),(597,1732,702,1792),(1629,1732,1734,1792),(2660,1732,2765,1792),(647,2336,752,2396),(1727,2336,1832,2396),(2798,2336,2903,2396)],
        "orange": [(383,515,488,585),(1379,515,1484,585),(2414,515,2519,585),(383,1118,488,1189),(1337,1118,1442,1189),(2291,1118,2396,1189),(425,1722,530,1793),(1444,1722,1549,1793),(2451,1722,2556,1793),(463,2326,568,2396),(1525,2326,1630,2396),(2564,2326,2669,2396)],
    },
}
# Historical displayed values, padded only. Do not replace them with the
# single-case cache's distinct crossings or calculate new crossings.
GRID_RATES = [
    ("0.0263","0.0275","0.0315"),("0.0453","0.0470","0.0560"),
    ("0.0819","0.0859","0.1086"),("0.0263","0.0275","0.0315"),
    ("0.0263","0.0275","0.0315"),("0.0263","0.0275","0.0315"),
    ("0.0453","0.0462","0.0528"),("0.0747","0.0764","0.0881"),
    ("0.0987","0.1016","0.1229"),("0.0628","0.0704","0.0755"),
    ("0.1115","0.1158","0.1325"),("0.1498","0.1512","0.1853"),
]
COLORS = {"orange": (0, r"$\mathbf{q}_k^{\star}$", "#E65100", "#FF6F00"),
          "green": (1, "ECDF", "#1B5E20", "#2E7D32"),
          "blue": (2, "Opt.", "#0D47A1", "#1565C0")}


def background(pixels, box):
    x0,y0,x1,y1=box
    colors,counts=np.unique(pixels[y0:y1,x0:x1,:3].reshape(-1,3),axis=0,return_counts=True)
    return tuple(int(c) for c in colors[counts.argmax()])


class Edit:
    def __init__(self, source, expected_hash):
        self.source=source
        self.original,self.before=read_original(source,expected_hash)
        self.after=self.before.copy()
        self.allowed=np.zeros(self.before.shape[:2],bool)
        self.records=[]

    def allow(self,box):
        x0,y0,x1,y1=box
        self.allowed[y0:y1,x0:x1]=True

    def label(self,box,text,size,**kwargs):
        self.allow(box)
        result=draw_label(self.after,box,text,round(self.original.info['dpi'][0]),size,**kwargs)
        self.records.append(result)

    def clear(self,box):
        self.allow(box)
        x0,y0,x1,y1=box
        self.after[y0:y1,x0:x1]=255

    def save(self,destination,remove_rows=None,pad_top=0):
        changed=np.any(self.before!=self.after,axis=2)
        assert not (changed & ~self.allowed).any()
        pixels=self.after
        if remove_rows is not None:
            lo,hi=remove_rows
            pixels=np.concatenate([pixels[:lo],pixels[hi:]],axis=0)
            # Deleting a header is permitted only within the edited title area.
            assert self.allowed[lo:hi].all()
            assert np.array_equal(pixels[lo:],self.after[hi:])
        if pad_top:
            pixels=np.pad(pixels,((pad_top,0),(0,0),(0,0)),constant_values=255)
        save_png(destination,pixels,self.original)
        return dict(filename=self.source.name,source_sha256=sha256(self.source),
                    output_sha256=sha256(destination),text_edits=self.records,
                    changed_pixels_outside_recorded_regions=0,
                    removed_header_rows=remove_rows,statistics_recomputed=False,
                    dimensions=[pixels.shape[1],pixels.shape[0]],
                    dpi=self.original.info['dpi'])


def grid_cdf(source,destination,expected_hash):
    edit=Edit(source,expected_hash)
    selected='selected' in source.name
    width=edit.after.shape[1]
    header_end=170 if selected else 150
    edit.clear((0,0,width,header_end))
    edit.label((0,0,width,90),'Optimized-endpoint ECDFs',24 if selected else 26,weight='bold')
    if selected:
        for x0,x1,text in [(168,1155,'PoF ε = 0.0'),(1295,2282,'PoF ε = 0.01'),
                           (2421,3408,'CVaR γ = 0.1, α = 0.01')]:
            edit.label((x0,171,x1,223),text,14,weight='bold')
    # Preserve curve pixels beneath the old translucent legend. Its position
    # cannot be moved faithfully without the complete frozen plotting objects.
    box=(287,251,598,300) if selected else (276,225,587,274)
    edit.label(box,'95% CI, B=10000',11 if selected else 12,alignment='left')
    values=[GRID_RATES[i] for i in (0,1,7)] if selected else GRID_RATES
    # Match the original annotation drawing order where adjacent boxes overlap.
    for color in ('orange','green','blue'):
        boxes=GRID_BOXES[source.name][color]
        index,label,foreground,border=COLORS[color]
        for i,(x0,y0,x1,y1) in enumerate(boxes):
            bg=background(edit.before,(x0+4,y0+4,x1-4,y1-4))
            if i==1 and color in ('green','blue'):
                # Restore nine-point numeric type by widening just the two
                # formerly short boxes. Arrow anchors and stars do not move.
                grow=10 if selected else 9
                x0-=grow;x1+=grow
                edit.records.append(dict(box_xyxy=[x0-1,y0-1,x1+1,y1+1],operation='widen annotation box',pixels_each_side=grow))
            # Repaint each frame in the original drawing order as well, so
            # overlaps between adjacent annotation boxes keep clean borders.
            outer=(x0-1,y0-1,x1+1,y1+1)
            edit.allow(outer)
            patch=Image.fromarray(edit.after)
            draw=ImageDraw.Draw(patch)
            draw.rounded_rectangle((x0-1,y0-1,x1,y1),radius=2,
                                   fill=bg+(255,),outline=border,width=2)
            edit.after=np.asarray(patch).copy()
            edit.records.append(dict(box_xyxy=list(outer),operation='annotation frame',fontsize=9))
            edit.label((x0+3,y0+3,x1-3,y1-3),label+'\n'+values[i][index],9,
                       weight='bold',background=np.asarray(bg)/255,color=foreground)
    result=edit.save(destination,remove_rows=(90,165) if selected else (90,145))
    result.update(annotation_fontsize=9,legend_position='original upper left; curve-preservation limitation',
                  bootstrap_resamples=10000,marker_and_arrow_positions_unchanged=True)
    return result


def single_hist(source,destination,expected_hash):
    edit=Edit(source,expected_hash)
    # A taller title band increases type without shrinking the plotted panel.
    before=edit.before
    padded=np.pad(before,((20,0),(0,0),(0,0)),constant_values=255)
    edit.before=padded;edit.after=padded.copy();edit.allowed=np.zeros(padded.shape[:2],bool)
    edit.clear((0,0,1580,84))
    edit.label((110,0,1580,84),'Injection Rate Distribution (PoF ε = 0.01)',20,weight='bold')
    result=edit.save(destination)
    result['original_panel_translation_pixels']=[0,20]
    assert np.array_equal(edit.after[88:],before[68:])
    return result


def selected_hist(source,destination,expected_hash):
    edit=Edit(source,expected_hash)
    edit.clear((0,0,3304,96))
    edit.label((0,0,3304,96),'Distribution of Optimized Injection Rates',24,weight='bold')
    for x0,x1,text in [(144,1134,'PoF ε = 0.0'),(1220,2209,'PoF ε = 0.01'),
                       (2298,3288,'CVaR γ = 0.1, α = 0.01')]:
        edit.label((x0,98,x1,150),text,15,weight='bold')
    return edit.save(destination)


def full_hist(source,destination):
    edit=Edit(source,'f910ccc2cc81271663162b1a34755f6a9eae7ded64122dbde89599e3fc74b96a')
    edit.clear((0,0,2916,160))
    edit.label((0,0,2916,90),'Distribution of Optimized Injection Rates',26,weight='bold')
    box=(2456,2446,2895,2480)
    bg=background(edit.before,box)
    edit.label(box,'mean=0.3978 std=0.1870',11,background=np.asarray(bg)/255)
    return edit.save(destination,remove_rows=(90,160))


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('reviewed_v5_dir',type=Path)
    p.add_argument('single_ecdf_export_dir',type=Path)
    p.add_argument('new_output_dir',type=Path)
    args=p.parse_args()
    args.new_output_dir.mkdir(parents=True,exist_ok=False)
    manifest=json.loads((args.reviewed_v5_dir/'manifest.json').read_text())
    reports=[]
    for name,fn in [('grid_cdf_selected_1x3.png',grid_cdf),('grid_cdf_4x3.png',grid_cdf),
                    ('hist_POF_eps0.01.png',single_hist),('grid_histogram_selected_1x3.png',selected_hist)]:
        reports.append(fn(args.reviewed_v5_dir/name,args.new_output_dir/name,manifest[name]['sha256']))
    name='grid_histogram_4x3.png'
    reports.append(full_hist(args.reviewed_v5_dir.parent/name,args.new_output_dir/name))
    for name in ['cdf_POF_eps0.01.png','cache_provenance.toml']:
        shutil.copyfile(args.single_ecdf_export_dir/name,args.new_output_dir/name)
    (args.new_output_dir/'png_verification.json').write_text(json.dumps(reports,indent=2)+'\n')
    print('Saved six figures; recorded text regions and panel translations verified.')


if __name__=='__main__':
    main()
