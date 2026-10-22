# ストアの商品ページヘッダー（3840x1646、iOS 27〜）を描く。
# 背景のタイ語は字形の組み立てが要るので pango-view（brew install pango）で描き、薄く敷く。
#
#   tools/store_screenshots/fetch_fonts.sh
#   uv run --no-project --with pillow --with numpy python3 tools/store_screenshots/header.py ko build/store_shots/header_ko.png
#
# ASC に上げるときはアルファ無しの PNG にする（JPEG は処理に失敗する）。
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont
import numpy as np
W,H=3840,1646
lang,out=sys.argv[1:3]
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'..','..'))
FONTS=f'{ROOT}/tools/store_screenshots/fonts'
TMP=tempfile.mkdtemp()
open(f'{TMP}/fc.conf','w').write(f'<?xml version="1.0"?><fontconfig><dir>{ROOT}/google_fonts</dir><cachedir>{TMP}/cache</cachedir></fontconfig>')
env=dict(os.environ,FONTCONFIG_FILE=f'{TMP}/fc.conf',PANGOCAIRO_BACKEND='fc')
yy,xx=np.mgrid[0:H,0:W]
d=np.sqrt(((xx-W/2)/(W/2))**2+((yy-H/2)/(H/2))**2)/1.414
c0=np.array([251,248,241]);c1=np.array([233,228,219])
t=np.clip(d,0,1)[...,None]**1.2
bg=c0*(1-t)+c1*t
ink=np.zeros((H,W))
rows=[(-40,'วันนี้ฉันทำงานที่บ้าน  ไปกินข้าวกัน'),(-330,'สวัสดีค่ะ  ยินดีที่ได้รู้จัก  อากาศดีจังเลย'),(-170,'อร่อยมาก  เดี๋ยวเจอกันนะ  ฉันชอบมาก'),(-260,'ทำอะไร  ช่วยพูดช้าๆ หน่อย  รถติดมาก'),(-150,'ภาษาไทยสนุก  คิดถึงนะ  ฝนตกแล้ว'),(-40,'วันนี้ฉันทำงานที่บ้าน  ไปกินข้าวกัน')]
for i,(x,s) in enumerate(rows):
    p=f'{TMP}/row{i}.png'
    subprocess.run(['pango-view','-q','--margin=0','--font','Noto Sans Thai Bold 320px','--text',s,'-o',p],env=env,check=True)
    r=1-np.array(Image.open(p).convert('L'))/255.0
    prof=r.mean(1); body=np.where(prof>prof.max()*0.35)[0]; cy=(body.min()+body.max())/2
    y0=int(176+316*i-cy)
    h,w=r.shape
    ys,ye=max(y0,0),min(y0+h,H); xs,xe=max(x,0),min(x+w,W)
    if ye>ys and xe>xs: ink[ys:ye,xs:xe]=np.maximum(ink[ys:ye,xs:xe],r[ys-y0:ye-y0,xs-x:xe-x])
bg=bg*(1-ink[...,None]*0.045)
img=Image.fromarray(bg.clip(0,255).astype('uint8'),'RGB')
dr=ImageDraw.Draw(img)
# 見出し: 小さい1行目、2行目（強調しない部分, 金で強調する部分）。
cfg={'ja':('NotoSansJP','気づけば、','タイ語が','読めている'),
     'ko':('NotoSansKR','어느새,','태국어가 ','읽혀요')}
fam,top,main,acc=cfg[lang]
ft=ImageFont.truetype(f'{FONTS}/{fam}-Medium.otf',135)
fm=ImageFont.truetype(f'{FONTS}/{fam}-Bold.otf',215)
SLATE=(76,86,105);NAVY=(22,36,63);GOLD=(168,130,60)
def put(cy,parts,font):
    tw=sum(dr.textlength(s,font=font) for s,_ in parts)
    b=dr.textbbox((0,0),''.join(s for s,_ in parts),font=font)
    x=(W-tw)/2; y=cy-(b[1]+b[3])/2
    for s,c in parts:
        dr.text((x,y),s,font=font,fill=c); x+=dr.textlength(s,font=font)
put(748,[(top,SLATE)],ft)
put(1000,[(main,NAVY),(acc,GOLD)],fm)
img.save(out)
