import sys, os, re
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path('guide-screens')
ROOT.mkdir(exist_ok=True)
SCENES = [
 '03-password-mismatch','13-materials','24-memory-skills',
 '21-capstone-rubric','22-capstone-result','27-course-bottom',
 '28-preferences-language','30-agent-wizard','31-course-explanation','32-course-summary',
]
SCROLL={'13-materials':3,'24-memory-skills':12,'21-capstone-rubric':6,'22-capstone-result':26,'27-course-bottom':17,'28-preferences-language':12}
def semantics(page):
    pass

def mismatch(page):
    for y,value in [(335,'Айдана'),(405,'teacher@example.test'),(475,'demo-fractions-2026'),(588,'wrong')]:
        page.mouse.click(125,y)
        page.wait_for_timeout(160)
        page.keyboard.insert_text(value)
    page.mouse.click(42,670)
    page.mouse.move(248,660)
    for _ in range(4):
        page.mouse.wheel(0,400)
        page.wait_for_timeout(250)
    page.wait_for_timeout(250)

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
    if scene=='30-agent-wizard':
        p.mouse.click(190,522)
        p.wait_for_timeout(600)
    if scene in SCROLL:
        p.mouse.move(290,610)
        for _ in range(SCROLL[scene]):
            p.mouse.wheel(0, 350); p.wait_for_timeout(210)
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
