import sys, os, re
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path('guide-screens')
ROOT.mkdir(exist_ok=True)
SCENES = [
 '01-sign-in','02-register','03-password-mismatch','04-recover',
 '05-welcome','06-preferences','07-name-assistant','08-agents','09-agent-editor',
 '10-dialogue','11-trace','12-agent-settings','13-materials','24-memory-skills',
 '25-approval','14-course','15-lesson','23-lesson-practice','26-course-quiz',
 '16-profile','17-app-settings','18-privacy','19-help',
 '20-capstone-prompt','21-capstone-rubric','22-capstone-result',
]
SCROLL={'13-materials':470,'24-memory-skills':1150,'21-capstone-rubric':650,'22-capstone-result':1450}
def semantics(page):
    el=page.locator('flt-semantics-placeholder')
    if el.count():
        try: el.first.click(force=True,timeout=900)
        except Exception: pass

def mismatch(page):
    for text,value in [('Имя','Айдана'),('Почта','teacher@example.test'),('Пароль','demo-fractions-2026'),('Повторите пароль','wrong')]:
        # CanvasKit exposes form affordances via its accessibility tree.
        loc=page.get_by_role('textbox',name=re.compile('^'+re.escape(text)+r'(?:$|\n)'))
        loc.first.click(timeout=1800)
        page.keyboard.insert_text(value)
    page.keyboard.press('Tab')
    page.mouse.click(355,216)

def capture(context, scene):
    p=context.new_page()
    p.on('pageerror',lambda e:print(f'PAGE_ERROR [{scene}] {e}',flush=True))
    p.goto(f'http://127.0.0.1:8765/?scene={scene}',wait_until='load',timeout=25000)
    p.locator('flutter-view').wait_for(state='attached',timeout=18000)
    p.wait_for_timeout(1900)
    semantics(p)
    p.wait_for_timeout(200)
    if scene=='03-password-mismatch':
        try: mismatch(p)
        except Exception as e:
            print(f'OPTIONAL_SCREEN_NOT_CAPTURED {scene}: {e}',flush=True)
            p.close(); return
    if scene in SCROLL:
        p.mouse.move(290,610)
        for _ in range((SCROLL[scene]+349)//350):
            p.mouse.wheel(0, min(350, SCROLL[scene])); p.wait_for_timeout(190)
    p.wait_for_timeout(250)
    p.screenshot(path=ROOT/f'{scene}.png',animations='disabled',full_page=False)
    print(f'CAPTURED {scene}',flush=True)
    p.close()

with sync_playwright() as pw:
    browser=pw.chromium.launch(channel='chrome',headless=True,args=['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader'])
    ctx=browser.new_context(viewport={'width':390,'height':844},device_scale_factor=2,locale='ru-RU')
    # The browser may only contact the local fixture, even if Flutter requests CDN resources.
    ctx.route('**/*',lambda route: route.continue_() if route.request.url.startswith(('http://127.0.0.1:8765/','data:','blob:')) else route.abort())
    failed=[]
    for scene in SCENES:
        try: capture(ctx,scene)
        except Exception as e: print(f'FAILED {scene}: {e}',flush=True); failed.append(scene)
    browser.close()
    if failed: print(f'Incomplete: {failed}',file=sys.stderr)
    if not list(ROOT.glob('*.png')): sys.exit(1)
