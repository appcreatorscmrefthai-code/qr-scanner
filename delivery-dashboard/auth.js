/* เข้าสู่ระบบสำหรับ Dashboard / ปฏิทิน / หน้า QR / นำเข้าแผน  (ผู้ใช้อยู่ใน Supabase > Authentication, สิทธิ์อยู่ในตาราง profiles : edit หรือ view) */
window.Auth = (function () {
  const CFG = window.APP_CONFIG || {}, DEMO = !SB.ON, KEY = 'deliveryPlanAuth2';
  let pending = null, refreshing = null;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  // อ่านจาก localStorage ทุกครั้ง เพื่อให้หลายแท็บใช้การเข้าสู่ระบบชุดเดียวกัน
  function get() {
    if (DEMO) return { access: '', user: 'demo', name: 'โหมดตัวอย่าง', role: 'admin' };
    try { return JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { return null; }
  }
  function set(v) {
    try {
      if (v) localStorage.setItem(KEY, JSON.stringify(v));
      else ['deliveryPlanAuth2', 'deliveryPlanAuth', 'deliveryPlanSnap', 'deliveryPlanMonth'].forEach(k => localStorage.removeItem(k));
    } catch (e) { }
  }
  const canEdit = () => { const a = get(); return !!a && (a.role === 'edit' || a.role === 'admin'); };
  const isAdmin = () => { const a = get(); return !!a && a.role === 'admin'; };
  const ROLE_TH = { admin: 'ผู้ดูแล (ทำได้ทุกอย่าง)', edit: 'แก้ไขได้', viewer: 'ดูอย่างเดียว' };

  // เก็บผลการเข้าสู่ระบบ + อ่านชื่อและสิทธิ์จากตาราง profiles
  async function store(r) {
    const uid = r.user && r.user.id, email = (r.user && r.user.email) || '';
    const rows = await SB.call('/rest/v1/profiles?select=name,role,active&user_id=eq.' + encodeURIComponent(uid), { token: r.access_token });
    const p = rows && rows[0];
    if (!p || !p.active) { const e = new Error('บัญชีนี้ยังไม่ได้รับสิทธิ์ใช้งาน หรือถูกปิดการใช้งาน กรุณาติดต่อผู้ดูแล'); e.server = true; throw e; }
    const a = { access: r.access_token, refresh: r.refresh_token, exp: Date.now() + (r.expires_in || 3600) * 1000, uid, user: email, name: p.name || email.split('@')[0], role: p.role === 'admin' ? 'admin' : p.role === 'edit' ? 'edit' : 'viewer' };
    set(a);
    return a;
  }

  // แสดงหน้าต่างเข้าสู่ระบบ คืนค่าเมื่อเข้าสู่ระบบสำเร็จ
  function login(note) {
    if (pending) return pending;
    pending = new Promise(resolve => {
      const d = document.createElement('dialog');
      d.style.cssText = 'background:#131c2e;color:#eaf0fa;border:1px solid #3a4a72;border-radius:14px;padding:22px;width:min(380px,92vw);font:16px/1.5 "Sarabun","Noto Sans Thai",Tahoma,sans-serif';
      const inp = 'width:100%;box-sizing:border-box;font:inherit;color:#eaf0fa;background:#1a2540;border:1px solid #2a3756;border-radius:10px;padding:10px 12px;margin:4px 0 12px';
      d.innerHTML = `<form method="dialog" id="authForm">
        <h2 style="margin:0 0 4px;font-size:20px">เข้าสู่ระบบ Delivery Plan</h2>
        <p style="margin:0 0 14px;color:#8e9bb3;font-size:14px">${esc(note || 'ใช้ชื่อผู้ใช้ (หรืออีเมล) และรหัสผ่านที่ผู้ดูแลกำหนดให้')}</p>
        <label>ชื่อผู้ใช้หรืออีเมล<input id="authUser" autocomplete="username" autocapitalize="none" spellcheck="false" style="${inp}" required></label>
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
          // พิมพ์ชื่อสั้นได้ เช่น tv ระบบจะเติมโดเมนของบัญชีที่ไม่มีอีเมลจริงให้เอง
          const v = d.querySelector('#authUser').value.trim().toLowerCase();
          const email = v.includes('@') ? v : v + '@' + (CFG.LOGIN_DOMAIN || 'scmdelivery.local');
          const r = await SB.call('/auth/v1/token?grant_type=password', { body: { email, password: d.querySelector('#authPass').value } });
          const a = await store(r);
          d.close(); d.remove(); pending = null; resolve(a);
        } catch (err) {
          msg.textContent = err.status === 429 ? 'ลองเข้าสู่ระบบหลายครั้งเกินไป กรุณารอสักครู่แล้วลองใหม่'
            : err.status === 400 || err.status === 401 ? 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'
            : err.message || 'เข้าสู่ระบบไม่สำเร็จ';
          btn.disabled = false;
        }
      });
      d.showModal();
    });
    return pending;
  }

  // โทเคนที่ยังไม่หมดอายุ : ต่ออายุให้เองก่อนหมด ถ้าต่อไม่ได้จะให้เข้าสู่ระบบใหม่
  async function token(force) {
    let a = get();
    if (!a || !a.access) a = await login();
    if (!force && a.exp - 60000 > Date.now()) return a.access;
    if (!refreshing) refreshing = (async () => {
      const used = a.refresh;
      try {
        const r = await SB.call('/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: used } });
        return (await store(r)).access;
      } catch (e) {
        const b = get();                                              // แท็บอื่นอาจต่ออายุไปแล้ว ใช้ของแท็บนั้น
        if (b && b.refresh !== used && b.exp - 60000 > Date.now()) return b.access;
        if (!e.server) throw e;                                       // เน็ตสะดุด : ให้ผู้เรียกลองใหม่รอบหน้า
        set(null);
        return (await login('กรุณาเข้าสู่ระบบอีกครั้ง')).access;
      }
    })().finally(() => { refreshing = null; });
    return refreshing;
  }

  // เรียก API ด้วยโทเคนของผู้ใช้ ถ้าโทเคนถูกปฏิเสธจะต่ออายุแล้วลองอีกครั้ง
  async function authed(fn) {
    try { return await fn(await token()); }
    catch (e) {
      if (e.status !== 401 && e.message !== 'AUTH') throw e;
      if (e.message === 'AUTH') { set(null); await login('บัญชีนี้ถูกปิดการใช้งาน หรือการเข้าสู่ระบบหมดอายุ'); return fn(await token()); }
      return fn(await token(true));
    }
  }
  const rpc = (fn, args) => authed(t => SB.rpc(fn, args, { token: t }));

  const EMBED = 'select=*,pickup_log(*),road_log(*)';
  const toTask = r => SB.full(r, r.pickup_log, r.road_log);

  // รูปแบบเดียวกับที่หน้าเว็บใช้มาแต่เดิม : { ok, ... } หรือ { ok:false, error }
  async function getJson(q) {
    if (DEMO) return { ok: false, error: 'โหมดตัวอย่าง' };
    const t0 = Date.now();
    try {
      let out;
      if (q.action === 'month') out = { days: await rpc('month_summary', { p_month: q.month }) };
      else {
        const rows = await authed(t => SB.call(`/rest/v1/plan?${EMBED}&date=eq.${encodeURIComponent(q.date)}&order=schedule,task_code`, { token: t }));
        out = { date: q.date, tasks: rows.map(toTask) };
      }
      out.ok = true; out.took = ` · โหลด ${((Date.now() - t0) / 1000).toFixed(1)} วิ`;
      return out;
    } catch (e) { return { ok: false, error: e.message || String(e) }; }
  }
  async function postJson(b) {
    try {
      if (b.action === 'editPlan') {
        const r = await rpc('plan_edit', { p_code: b.taskCode, p_changes: b.changes || {} });
        const rows = await authed(t => SB.call(`/rest/v1/plan?${EMBED}&task_code=eq.${encodeURIComponent(b.taskCode)}`, { token: t }));
        return { ok: true, count: r.count, task: rows[0] ? toTask(rows[0]) : null };
      }
      if (b.action === 'syncPlan') return Object.assign({ ok: true }, await rpc('plan_sync', { p_rows: b.rows }));
      return { ok: false, error: 'ไม่รู้จักคำสั่ง: ' + b.action };
    } catch (e) { return { ok: false, error: e.message || String(e) }; }
  }

  // ลิงก์ชั่วคราว (1 ชั่วโมง) สำหรับเปิดรูปในที่เก็บรูป : คืนค่า { path: url }
  async function signUrls(paths) {
    const list = [...new Set((paths || []).filter(Boolean))], out = {};
    if (!list.length || DEMO) return out;
    const rows = await authed(t => SB.call('/storage/v1/object/sign/photos', { token: t, body: { expiresIn: 3600, paths: list } }));
    (rows || []).forEach(r => { const u = r.signedURL || r.signedUrl; if (u && !r.error) out[r.path] = SB.URL + '/storage/v1' + u; });
    return out;
  }

  // แสดงชื่อผู้ใช้ สิทธิ์ และปุ่มออกจากระบบ ในกล่องที่กำหนด
  function badge(el) {
    const a = get();
    if (!el) return;
    if (!a || DEMO) { el.textContent = ''; return; }
    el.innerHTML = `<span>${esc(a.name)} · ${ROLE_TH[a.role] || ROLE_TH.viewer}</span> <button type="button" style="font:inherit;color:inherit;background:transparent;border:1px solid currentColor;border-radius:8px;padding:1px 10px;cursor:pointer;opacity:.85">ออกจากระบบ</button>`;
    el.querySelector('button').onclick = async () => {
      try { await SB.call('/auth/v1/logout?scope=local', { method: 'POST', token: a.access }); } catch (e) { }
      set(null); location.reload();
    };
  }

  // ลบรูปในที่เก็บรูป (เฉพาะ admin) paths = รายการ path ของรูป
  async function removePhotos(paths) {
    const list = [...new Set((paths || []).filter(Boolean))];
    if (!list.length || DEMO) return;
    await authed(t => SB.call('/storage/v1/object/photos', { method: 'DELETE', token: t, body: { prefixes: list } }));
  }

  return { get, canEdit, isAdmin, removePhotos, login, badge, getJson, postJson, rpc, signUrls };
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
