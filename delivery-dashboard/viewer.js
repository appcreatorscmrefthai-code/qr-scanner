/* ดูรูปแบบเลื่อนได้ (ใช้ร่วมกัน Dashboard / ฟอร์มมือถือ) : กดรูปย่อแล้วเปิดเต็มจอ เลื่อนดูรูปถัดไปในชุดเดียวกันได้
   - รูปย่อที่ต้องการให้เปิดด้วยตัวนี้ : <a href="ลิงก์รูป" data-vg="ชื่อชุด" data-cap="คำอธิบาย"> (ไม่มี href = ยังโหลดลิงก์ไม่เสร็จ จะข้ามไป)
   - ปุ่ม ‹ › / ลูกศรซ้ายขวาบนคีย์บอร์ด / ปัดซ้ายขวาบนมือถือ, Esc หรือ × ปิด
   - เปิดด้วย <dialog> จึงซ้อนบน Popup ของ Dashboard ได้ */
window.Viewer = (function () {
  let dlg, img, cap, cnt, orig, list = [], at = 0, x0 = null;
  const css = `
dialog.pv{position:fixed;inset:0;width:100vw;height:100vh;max-width:none;max-height:none;margin:0;padding:0;border:0;background:rgba(5,8,16,.96);color:#fff;overflow:hidden}
dialog.pv::backdrop{background:rgba(0,0,0,.8)}
.pv .st{position:absolute;inset:48px 0 44px;display:flex;align-items:center;justify-content:center}
.pv .st img{max-width:calc(100vw - 24px);max-height:100%;object-fit:contain;display:block;user-select:none;-webkit-user-drag:none}
.pv .tb{position:absolute;top:0;left:0;right:0;height:48px;display:flex;align-items:center;gap:12px;padding:0 10px 0 16px;font:600 15px/1.3 "Sarabun","Noto Sans Thai",sans-serif;background:linear-gradient(rgba(0,0,0,.55),transparent)}
.pv .tb .c{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.pv .tb a,.pv .tb button{color:#fff;text-decoration:none;font:inherit;background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.25);border-radius:8px;padding:.25em .7em;cursor:pointer}
.pv .tb button.x{font-size:20px;line-height:1;padding:.15em .55em}
.pv .nav{position:absolute;top:50%;transform:translateY(-50%);width:64px;height:120px;border:0;background:transparent;cursor:pointer;color:#ff7a1a;padding:0}
.pv .nav svg{width:44px;height:96px;filter:drop-shadow(0 1px 3px rgba(0,0,0,.8))}
.pv .nav:hover,.pv .nav:focus-visible{color:#ffa45c;outline:none}
.pv .nav[disabled]{opacity:.2;cursor:default}
.pv .pr{left:4px}.pv .nx{right:4px}
.pv .ft{position:absolute;bottom:0;left:0;right:0;height:44px;display:flex;align-items:center;justify-content:center;font:600 15px "Sarabun",sans-serif;color:#cbd5e1}
@media (max-width:600px){.pv .nav{width:44px}.pv .nav svg{width:30px;height:70px}}`;
  const arrow = d => `<svg viewBox="0 0 30 70" aria-hidden="true"><path d="${d}" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  function build() {
    if (dlg) return;
    const st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);
    dlg = document.createElement('dialog'); dlg.className = 'pv'; dlg.setAttribute('aria-label', 'ดูรูป');
    dlg.innerHTML = `<div class="tb"><span class="c"></span><a class="o" target="_blank" rel="noopener">เปิดรูปเต็ม ↗</a><button type="button" class="x" aria-label="ปิด">×</button></div>
      <div class="st"><img alt=""></div>
      <button type="button" class="nav pr" aria-label="รูปก่อนหน้า">${arrow('M26 3 L4 35 L26 67')}</button>
      <button type="button" class="nav nx" aria-label="รูปถัดไป">${arrow('M4 3 L26 35 L4 67')}</button>
      <div class="ft"></div>`;
    document.body.appendChild(dlg);
    img = dlg.querySelector('img'); cap = dlg.querySelector('.c'); cnt = dlg.querySelector('.ft'); orig = dlg.querySelector('.o');
    dlg.querySelector('.x').onclick = () => dlg.close();
    dlg.querySelector('.pr').onclick = () => go(-1);
    dlg.querySelector('.nx').onclick = () => go(1);
    dlg.querySelector('.st').onclick = e => { if (e.target !== img) dlg.close(); };
    dlg.addEventListener('keydown', e => {
      if (e.key === 'ArrowLeft') { e.preventDefault(); go(-1); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); go(1); }
    });
    dlg.addEventListener('touchstart', e => { x0 = e.touches.length === 1 ? e.touches[0].clientX : null; }, { passive: true });
    dlg.addEventListener('touchend', e => {
      if (x0 == null) return;
      const dx = e.changedTouches[0].clientX - x0; x0 = null;
      if (Math.abs(dx) > 50) go(dx < 0 ? 1 : -1);
    }, { passive: true });
  }
  function show() {
    const it = list[at];
    img.src = it.url; orig.href = it.url;
    cap.textContent = it.cap || '';
    cnt.textContent = `${at + 1} / ${list.length}`;
    dlg.querySelector('.pr').disabled = at === 0;
    dlg.querySelector('.nx').disabled = at === list.length - 1;
    [at - 1, at + 1].forEach(i => { if (list[i]) { const p = new Image(); p.src = list[i].url; } });     // โหลดรูปข้างเคียงไว้ก่อน
  }
  function go(step) { const n = at + step; if (n >= 0 && n < list.length) { at = n; show(); } }
  // items = [{ url, cap }]
  function open(items, start) {
    build();
    list = (items || []).filter(x => x && x.url);
    if (!list.length) return;
    at = Math.max(0, Math.min(list.length - 1, start || 0));
    show();
    if (!dlg.open) dlg.showModal();
  }
  // ผูกกับพื้นที่ที่มีรูปย่อ : กด <a data-vg> แล้วเปิดชุดรูปที่มี data-vg เดียวกัน (ภายใน root)
  function bind(root) {
    const el = typeof root === 'string' ? document.getElementById(root) : root;
    if (!el || el.dataset.pvBound) return;
    el.dataset.pvBound = '1';
    el.addEventListener('click', e => {
      const a = e.target.closest('a[data-vg]');
      if (!a || !el.contains(a) || e.ctrlKey || e.metaKey || e.shiftKey) return;
      e.preventDefault();
      if (!a.getAttribute('href')) return;                     // ลิงก์รูปยังไม่พร้อม
      const g = a.dataset.vg, all = [...el.querySelectorAll('a[data-vg]')].filter(x => x.dataset.vg === g && x.getAttribute('href'));
      open(all.map(x => ({ url: x.href, cap: x.dataset.cap || '' })), all.indexOf(a));
    });
  }
  return { open, bind };
})();
