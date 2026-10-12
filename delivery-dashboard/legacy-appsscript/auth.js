/* เข้าสู่ระบบสำหรับ Dashboard / ปฏิทิน / หน้า QR  (ผู้ใช้อยู่ในชีต Users : สิทธิ์ edit หรือ view) */
window.Auth = (function () {
  const CFG = window.APP_CONFIG || {}, DEMO = !CFG.API_URL, KEY = 'deliveryPlanAuth';
  let mem = null, pending = null;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  // Apps Script ตอบเป็นหน้า HTML เมื่อสคริปต์มีปัญหาหรือยังไม่ได้ Deploy เวอร์ชันใหม่ ให้แสดงข้อความที่อ่านเข้าใจแทน error ของ JSON
  async function readJson(promise) {
    const text = await (await promise).text();
    try { return JSON.parse(text); }
    catch (e) {
      const m = text.match(/<title>([^<]*)<\/title>/i), body = text.replace(/<style[\s\S]*?<\/style>|<script[\s\S]*?<\/script>|<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
      const err = new Error('เชื่อมต่อระบบไม่ได้ชั่วคราว (' + ((m && m[1].trim()) || body.slice(0, 60) || 'ไม่ทราบสาเหตุ') + ')');
      err.temporary = true; throw err;
    }
  }
  // Google ตอบเป็นหน้า "ไม่พบเพจ" หรือเน็ตสะดุดเป็นครั้งคราว: ลองใหม่ให้เองก่อนแจ้งข้อผิดพลาด (ใช้กับการอ่านข้อมูลและการเข้าสู่ระบบ ซึ่งเรียกซ้ำได้ไม่มีผลข้างเคียง)
  async function again(fn, n) {
    for (let i = 0; ; i++) {
      try { return await fn(); }
      catch (e) { if (i >= n - 1) throw e; await new Promise(r => setTimeout(r, [800, 2000, 4000][i] || 4000)); }
    }
  }

  function get() {
    if (DEMO) return { token: '', user: 'demo', name: 'โหมดตัวอย่าง', role: 'edit' };
    if (mem) return mem;
    try { mem = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { }
    return mem;
  }
  function set(v) { mem = v; try { if (v) localStorage.setItem(KEY, JSON.stringify(v)); else { localStorage.removeItem(KEY); localStorage.removeItem('deliveryPlanSnap'); localStorage.removeItem('deliveryPlanMonth'); } } catch (e) { } }
  const canEdit = () => { const a = get(); return !!a && a.role === 'edit'; };

  // แสดงหน้าต่างเข้าสู่ระบบ คืนค่าเมื่อเข้าสู่ระบบสำเร็จ
  function login(note) {
    if (pending) return pending;
    pending = new Promise(resolve => {
      const d = document.createElement('dialog');
      d.style.cssText = 'background:#131c2e;color:#eaf0fa;border:1px solid #3a4a72;border-radius:14px;padding:22px;width:min(380px,92vw);font:16px/1.5 "Sarabun","Noto Sans Thai",Tahoma,sans-serif';
      const inp = 'width:100%;box-sizing:border-box;font:inherit;color:#eaf0fa;background:#1a2540;border:1px solid #2a3756;border-radius:10px;padding:10px 12px;margin:4px 0 12px';
      d.innerHTML = `<form method="dialog" id="authForm">
        <h2 style="margin:0 0 4px;font-size:20px">เข้าสู่ระบบ Delivery Plan</h2>
        <p style="margin:0 0 14px;color:#8e9bb3;font-size:14px">${esc(note || 'ใช้ชื่อผู้ใช้และรหัสผ่านที่ผู้ดูแลกำหนดให้')}</p>
        <label>ชื่อผู้ใช้<input id="authUser" autocomplete="username" autocapitalize="none" style="${inp}" required></label>
        <label>รหัสผ่าน<input id="authPass" type="password" autocomplete="current-password" style="${inp}" required></label>
        <div id="authMsg" role="alert" style="color:#ff8a98;min-height:1.4em;font-size:14px;margin-bottom:8px"></div>
        <button id="authBtn" type="submit" style="width:100%;font:inherit;font-weight:700;padding:11px;border:0;border-radius:10px;background:#4aa8ff;color:#06101f;cursor:pointer">เข้าสู่ระบบ</button>
      </form>`;
      document.body.appendChild(d);
      d.addEventListener('cancel', e => e.preventDefault());         // ต้องเข้าสู่ระบบก่อนจึงปิดได้
      d.querySelector('#authForm').addEventListener('submit', async e => {
        e.preventDefault();
        const msg = d.querySelector('#authMsg'), btn = d.querySelector('#authBtn');
        btn.disabled = true; msg.textContent = 'กำลังตรวจสอบ…';
        try {
          const body = JSON.stringify({ action: 'login', user: d.querySelector('#authUser').value.trim(), password: d.querySelector('#authPass').value });
          const r = await again(() => readJson(fetch(CFG.API_URL, { method: 'POST', body })), 3);
          if (!r.ok) throw new Error(r.error);
          set({ token: r.token, user: r.user, name: r.name, role: r.role, weak: !!r.weak });
          d.close(); d.remove(); pending = null; resolve(get());
        } catch (err) { msg.textContent = err.message || 'เข้าสู่ระบบไม่สำเร็จ'; btn.disabled = false; }
      });
      d.showModal();
    });
    return pending;
  }

  /* อ่านข้อมูลเมื่อ Google ตอบช้าหรือตอบผิดเป็นบางครั้ง (เวลาที่โค้ดของเราใช้จริงไม่ถึง 1 วินาที):
     - คำขอแรกไม่ถูกยกเลิก ปล่อยให้รอจนตอบ (สูงสุด 60 วินาที) จึงไม่ช้ากว่าการเรียกครั้งเดียวแบบเดิม
     - ถ้ายังไม่ตอบใน 4 วินาที ส่งคำขอสำรอง 1 ครั้ง และอีก 1 ครั้งที่ 12 วินาที ใช้คำตอบที่มาถึงก่อน
     - คำขอที่ตอบผิด (หน้า "ไม่พบเพจ") จะถูกส่งใหม่แทนทันที รวมไม่เกิน 5 คำขอต่อการโหลดหนึ่งครั้ง
     การอ่านข้อมูลเรียกซ้ำได้ไม่มีผลข้างเคียง จึงใช้วิธีนี้ได้ */
  function getFast(url, stat) {
    return new Promise((resolve, reject) => {
      const ctrls = [], timers = [];
      let done = false, live = 0, lastErr = null;
      const finish = (fn, v) => { if (done) return; done = true; timers.forEach(clearTimeout); ctrls.forEach(c => c.abort()); stat.slow = Math.max(0, stat.n - stat.bad - 1); fn(v); };
      const one = () => {
        if (done || stat.n >= 5) return;
        stat.n++; live++;
        const c = new AbortController(); ctrls.push(c);
        readJson(fetch(url, { signal: c.signal })).then(r => finish(resolve, r), e => {
          if (done) return;
          live--; stat.bad++; lastErr = e;
          if (stat.n < 5) timers.push(setTimeout(one, 300));
          else if (!live) finish(reject, lastErr);
        });
      };
      one();
      timers.push(setTimeout(one, 4000), setTimeout(one, 12000));
      timers.push(setTimeout(() => finish(reject, lastErr || new Error('เชื่อมต่อระบบไม่ได้ชั่วคราว (Google ไม่ตอบภายใน 60 วินาที)')), 60000));
    });
  }
  // หน้าเดียวกันขอข้อมูลชุดเดียวกันซ้ำระหว่างที่ยังรอคำตอบอยู่ ให้ใช้คำขอเดิม ไม่ส่งซ้อน (ลดภาระฝั่ง Google)
  const inflight = new Map();
  function getOnce(url, stat) {
    if (!inflight.has(url)) { const p = getFast(url, stat); inflight.set(url, p); const clear = () => inflight.delete(url); p.then(clear, clear); }
    return inflight.get(url);
  }

  // เรียก API ที่ต้องเข้าสู่ระบบ ถ้ายังไม่เข้าหรือหมดอายุ จะขึ้นหน้าต่างเข้าสู่ระบบแล้วลองใหม่ให้เอง
  async function call(method, data) {
    for (let i = 0; i < 3; i++) {
      const a = get() || await login();
      const t0 = Date.now();
      const stat = { n: 0, bad: 0, slow: 0 };
      const r = method === 'GET'
        ? await getOnce(CFG.API_URL + '?' + new URLSearchParams(Object.assign({}, data, { token: a.token })), stat)
        : await readJson(fetch(CFG.API_URL, { method: 'POST', body: JSON.stringify(Object.assign({}, data, { token: a.token })) }));
      // เวลาโหลด: ทั้งหมด (ที่ผู้ใช้รอ) และเฉพาะส่วนที่ Apps Script ใช้ประมวลผล ไว้ดูว่าช้าที่ขั้นไหน
      r.took = ` · โหลด ${((Date.now() - t0) / 1000).toFixed(1)} วิ (ระบบ ${r.ms != null ? (r.ms / 1000).toFixed(1) : '-'}` +
        (stat.n > 1 ? ` · เรียก ${stat.n} ครั้ง ตอบผิด ${stat.bad} ช้าเกิน ${stat.slow}` : '') + ')';
      if (!r.ok && r.error === 'AUTH') { set(null); await login('กรุณาเข้าสู่ระบบอีกครั้ง'); continue; }
      return r;
    }
    return { ok: false, error: 'เข้าสู่ระบบไม่สำเร็จ' };
  }

  // แสดงชื่อผู้ใช้ สิทธิ์ และปุ่มออกจากระบบ ในกล่องที่กำหนด
  function badge(el) {
    const a = get();
    if (!el) return;
    if (!a || DEMO) { el.textContent = ''; return; }
    el.innerHTML = `${a.weak ? '<span style="color:#f6b93b" title="แก้รหัสผ่านในชีต Users แล้วเข้าสู่ระบบใหม่">⚠ ยังใช้รหัสผ่านเริ่มต้น</span> ' : ''}<span>${esc(a.name)} · ${a.role === 'edit' ? 'แก้ไขได้' : 'ดูอย่างเดียว'}</span> <button type="button" style="font:inherit;color:inherit;background:transparent;border:1px solid currentColor;border-radius:8px;padding:1px 10px;cursor:pointer;opacity:.85">ออกจากระบบ</button>`;
    el.querySelector('button').onclick = () => { set(null); location.reload(); };
  }

  return { get, canEdit, login, badge, getJson: q => call('GET', q), postJson: b => call('POST', b) };
})();

/* ช่องเลือกวันที่ที่แสดงเป็น "3 ต.ค. 2026" (ตัวเลือกวันที่ของเบราว์เซอร์ยังทำงานอยู่ข้างใต้) */
window.DateBox = (function () {
  const MON = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  const text = v => { const m = String(v || '').match(/^(\d{4})-(\d{2})-(\d{2})$/); return m ? `${Number(m[3])} ${MON[Number(m[2]) - 1]} ${m[1]}` : 'เลือกวันที่'; };
  function attach(input) {
    const box = document.createElement('span'), label = document.createElement('span');
    box.className = input.className; input.className = '';
    box.style.cssText = 'position:relative;display:inline-flex;align-items:center;gap:.5em;cursor:pointer;white-space:nowrap';
    label.textContent = text(input.value);
    input.parentNode.insertBefore(box, input);
    box.append(label, Object.assign(document.createElement('span'), { textContent: '▾', ariaHidden: 'true' }), input);
    input.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;opacity:0;cursor:pointer;border:0;padding:0;margin:0';
    box.addEventListener('click', () => { try { input.showPicker(); } catch (e) { input.focus(); } });
    input.addEventListener('change', () => { label.textContent = text(input.value); });
    input._dateLabel = label;
  }
  const sync = input => { if (input._dateLabel) input._dateLabel.textContent = text(input.value); };
  return { attach, sync, text };
})();
