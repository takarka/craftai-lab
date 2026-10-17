// Сборка статической версии дизайна из исходников *.dc.html.
// Запуск:  node build.mjs   (из папки Builder/design/web)
// Результат: screens/*.html, flow.html, boards.js — всё открывается без сервера и без Claude.
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const src = join(here, '..');
const out = join(here, 'screens');
mkdirSync(out, { recursive: true });

const canvas = JSON.parse(readFileSync(join(src, 'canvas.json'), 'utf8'));
const id = (f) => f.replace('.dc.html', '');

// Значения шаблона у компонента «Персонаж» (уровень 5 — все модули включены)
const tpl = { level: 5, o1: 1, o2: 1, o3: 1, o4: 1, o5: 1 };

// Скрипт для вложенных страниц: клик по ссылке на другой экран в просмотрщике
// переносит холст к нужной доске; при открытии файла отдельно — обычная навигация.
const bridge = `<script>
(function(){
  var framed = window.top !== window;
  document.documentElement.className += framed ? ' framed' : ' solo';
  document.addEventListener('click', function(e){
    var a = e.target.closest && e.target.closest('a[href]');
    if(!a || !framed) return;
    var m = a.getAttribute('href').match(/(?:^|\\/)([A-Za-z0-9]+)\\.html$/);
    if(!m) return;
    e.preventDefault();
    window.top.postMessage({ craftGo: m[1] }, '*');
  });
})();
</script>`;

const baseCss = `<style>
html.solo{background:#E9EDF5}
html.solo body{display:flex;justify-content:center;padding:24px 16px;min-height:100vh;box-sizing:border-box}
html.framed body{margin:0}
</style>`;

function strip(html, { flow = false } = {}) {
  let h = html
    .replace(/<script[^>]*>[\s\S]*?<\/script>/g, '')
    .replace(/<\/?(helmet|x-dc)>/g, '')
    .replace(/\{\{(\w+)\}\}/g, (_, k) => (k in tpl ? tpl[k] : ''));
  // ссылки на соседние экраны: X.dc.html -> X.html (из flow — в screens/)
  h = h.replace(/href="([A-Za-z0-9]+)\.dc\.html"/g, (_, n) => `href="${flow ? 'screens/' : ''}${n}.html"`);
  h = h.replace('<head>', '<head>\n<meta name="viewport" content="width=device-width,initial-scale=1">');
  h = h.replace('</head>', `${baseCss}\n</head>`).replace('</body>', `${bridge}\n</body>`);
  return h;
}

// 1. Экраны
const boards = [];
for (const file of canvas.order) {
  const name = id(file);
  if (name === 'Flow') continue;
  const raw = readFileSync(join(src, file), 'utf8');
  writeFileSync(join(out, name + '.html'), strip(raw));
}

// 2. Flow: миниатюры из хранилища артефакта заменяем живыми экранами
{
  let h = readFileSync(join(src, 'Flow.dc.html'), 'utf8');
  const k = 112 / 390;
  h = h.replace(/<img class="(th(?: dl)?)" src="\/_blob\/[0-9a-f]+"[^>]*alt="([A-Za-z0-9]+)[^"]*"[^>]*>/g, (_, cls, n) =>
    `<div class="${cls}" style="width:112px;height:242px;overflow:hidden;background:#fff"><iframe src="screens/${n}.html" title="${n}" tabindex="-1" style="width:390px;height:844px;border:0;transform:scale(${k.toFixed(4)});transform-origin:0 0;pointer-events:none"></iframe></div>`);
  if (/_blob/.test(h)) throw new Error('Flow: остались ссылки на _blob');
  writeFileSync(join(here, 'flow.html'), strip(h, { flow: true }));
}

// 3. Данные холста для просмотрщика
for (const file of canvas.order) {
  const b = canvas.boards[file];
  const name = id(file);
  boards.push({ id: name, title: b.title, x: b.x, y: b.y, w: b.w, h: b.h,
    url: name === 'Flow' ? 'flow.html' : `screens/${name}.html` });
}
const titles = Object.values(canvas.notes).filter((n) => n.kind === 'title1')
  .map((n) => ({ text: n.text, x: n.x, y: n.y }));
writeFileSync(join(here, 'boards.js'),
  `// Сгенерировано build.mjs из canvas.json — не править руками\nwindow.CB_TITLE=${JSON.stringify(canvas.title)};\nwindow.CB_BOARDS=${JSON.stringify(boards, null, 1)};\nwindow.CB_TITLES=${JSON.stringify(titles, null, 1)};\n`);
console.log('ok:', boards.length, 'досок,', readdirSync(out).length, 'экранов');
