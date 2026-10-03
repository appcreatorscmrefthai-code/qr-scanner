/* เข้าสู่ระบบสำหรับ Dashboard / ปฏิทิน / หน้า QR  (ผู้ใช้อยู่ในชีต Users : สิทธิ์ edit หรือ view) */
window.Auth = (function () {
  const CFG = window.APP_CONFIG || {}, DEMO = !CFG.API_URL, KEY = 'deliveryPlanAuth';
  let mem = null, pending = null;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  function get() {
    if (DEMO) return { token: '', user: 'demo', name: 'โหมดตัวอย่าง', role: 'edit' };
    if (mem) return mem;
    try { mem = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { }
    return mem;
  }
  function set(v) { mem = v; try { v ? localStorage.setItem(KEY, JSON.stringify(v)) : localStorage.removeItem(KEY); } catch (e) { } }
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
          const r = await (await fetch(CFG.API_URL, { method: 'POST', body: JSON.stringify({ action: 'login', user: d.querySelector('#authUser').value.trim(), password: d.querySelector('#authPass').value }) })).json();
          if (!r.ok) throw new Error(r.error);
          set({ token: r.token, user: r.user, name: r.name, role: r.role });
          d.close(); d.remove(); pending = null; resolve(get());
        } catch (err) { msg.textContent = err.message || 'เข้าสู่ระบบไม่สำเร็จ'; btn.disabled = false; }
      });
      d.showModal();
    });
    return pending;
  }

  // เรียก API ที่ต้องเข้าสู่ระบบ ถ้ายังไม่เข้าหรือหมดอายุ จะขึ้นหน้าต่างเข้าสู่ระบบแล้วลองใหม่ให้เอง
  async function call(method, data) {
    for (let i = 0; i < 3; i++) {
      const a = get() || await login();
      const r = method === 'GET'
        ? await (await fetch(CFG.API_URL + '?' + new URLSearchParams(Object.assign({}, data, { token: a.token })))).json()
        : await (await fetch(CFG.API_URL, { method: 'POST', body: JSON.stringify(Object.assign({}, data, { token: a.token })) })).json();
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
    el.innerHTML = `<span>${esc(a.name)} · ${a.role === 'edit' ? 'แก้ไขได้' : 'ดูอย่างเดียว'}</span> <button type="button" style="font:inherit;color:inherit;background:transparent;border:1px solid currentColor;border-radius:8px;padding:1px 10px;cursor:pointer;opacity:.85">ออกจากระบบ</button>`;
    el.querySelector('button').onclick = () => { set(null); location.reload(); };
  }

  return { get, canEdit, login, badge, getJson: q => call('GET', q), postJson: b => call('POST', b) };
})();
