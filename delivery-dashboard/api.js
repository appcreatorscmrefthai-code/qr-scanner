/* ตัวเชื่อมกับ Supabase ใช้ร่วมกันทุกหน้า (เรียกตรงด้วย fetch ไม่ใช้ไลบรารีเพิ่ม หน้าเว็บจึงโหลดเร็วบนมือถือ)
   - apikey = Publishable key (เปิดเผยได้ สิทธิ์ถูกควบคุมด้วยกฎในฐานข้อมูล)
   - token  = โทเคนของผู้ใช้ที่เข้าสู่ระบบ (เฉพาะ Dashboard / ปฏิทิน / QR / นำเข้าแผน) ฟอร์มมือถือไม่ใช้ */
window.SB = (function () {
  const CFG = window.APP_CONFIG || {};
  const URL0 = String(CFG.SUPABASE_URL || '').replace(/\/+$/, ''), KEY = CFG.SUPABASE_KEY || '';
  const ON = !!(URL0 && KEY);
  const VER = '2026.10.06-s1';

  // เรียก API หนึ่งครั้ง : สำเร็จคืนข้อมูล, ไม่สำเร็จ throw Error (e.status = รหัส HTTP, e.server = true เมื่อเซิร์ฟเวอร์ปฏิเสธเอง)
  async function call(path, opt) {
    opt = opt || {};
    const headers = Object.assign({ apikey: KEY }, opt.headers || {});
    if (opt.token) headers.Authorization = 'Bearer ' + opt.token;
    let body = opt.body;
    if (body !== undefined && !(body instanceof Blob) && typeof body !== 'string') { body = JSON.stringify(body); headers['Content-Type'] = 'application/json'; }
    const res = await fetch(URL0 + path, { method: opt.method || (body === undefined ? 'GET' : 'POST'), headers, body, keepalive: !!opt.keepalive, signal: opt.signal });
    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch (e) { }
    if (!res.ok) {
      const msg = (data && (data.message || data.msg || data.error_description || data.error)) || ('เชื่อมต่อระบบไม่สำเร็จ (' + res.status + ')');
      const err = new Error(String(msg));
      err.status = res.status; err.server = res.status >= 400 && res.status < 500; err.code = data && (data.code || data.error_code || data.statusCode);
      throw err;
    }
    return data;
  }
  const rpc = (fn, args, opt) => call('/rest/v1/rpc/' + fn, Object.assign({ body: args || {} }, opt || {}));

  /* ---------- แปลงแถวในฐานข้อมูลเป็นรูปแบบที่หน้าเว็บใช้ ---------- */
  function task(p) {
    const stops = [];
    for (let k = 1; k <= 3; k++) if (p['stop' + k]) stops.push({ slot: k, name: p['stop' + k], arrival: p['arr' + k] || '', map: p['map' + k] || '', receiver: p['rec' + k] || '' });
    // ถ้าไม่ได้กรอกจุดที่ 1-3 ให้ใช้ Detail เป็นจุดส่งเดียว
    if (!stops.length) stops.push({ slot: 1, name: p.detail || p.task_code, arrival: p.arr1 || '', map: '', receiver: '' });
    return {
      taskCode: p.task_code, date: p.date, detail: p.detail || '', client: p.client || '', transport: p.transport || '', pickup: p.schedule || '',
      company: p.company || '', vehicleType: p.vehicle_type || '', plate: p.plate || '', driver: p.driver || '', phone: p.phone || '',
      round: p.round || '', roundTrip: /กลับ/.test(p.round || ''), stops,
      status: p.status || '', canceled: /cancel|ยกเลิก/i.test(p.status || ''), key: p.key || '', updatedAt: p.updated_at || ''
    };
  }
  const pickLog = l => ({ id: l.id, time: l.time, note: l.note || '', photos: l.photos || [] });
  const roadLog = l => ({ id: l.id, time: l.time, type: l.type, stop: l.stop || 0, plate: l.plate || '', oldPlate: l.old_plate || '', note: l.note || '',
    eta: [l.eta1 || '', l.eta2 || '', l.eta3 || ''], road: l.road || [], unload: l.unload || [], finish: !!l.finish });
  const byId = (a, b) => a.id - b.id;

  // สรุปสถานะจาก Log : เช็คอิน, ออกรถ, ถึงหน้างาน/ลงงานเสร็จของแต่ละจุด, เวลาที่คาดว่าจะถึง
  function state(t) {
    const n = t.stops.length;
    const s = { checkin: null, depart: t.pickupLog ? t.pickupLog.time : '', arrive: [], done: [], eta: [], lastRoad: '', roadCount: 0, returned: '' };
    for (let i = 0; i < n; i++) { s.arrive.push(''); s.done.push(''); s.eta.push(''); }
    t.logs.forEach(l => {
      const i = l.stop - 1;
      if (l.type === 'checkin' && !s.checkin) s.checkin = { time: l.time, plate: l.plate };
      if (l.type === 'road') { s.lastRoad = l.time; s.roadCount++; }
      if (l.type === 'road' || l.type === 'eta') for (let k = 0; k < n; k++) if (l.eta[k]) s.eta[k] = l.eta[k];
      if (l.type === 'return' && !s.returned) s.returned = l.time;
      if (l.type === 'arrive' && i >= 0 && i < n && !s.arrive[i]) s.arrive[i] = l.time;
      if (l.type === 'unload' && i >= 0 && i < n && !s.done[i]) { s.done[i] = l.time; if (!s.arrive[i]) s.arrive[i] = l.time; }
    });
    return s;
  }
  // แถวแผน + Log ของงานนั้น -> งานพร้อมสถานะ
  function full(planRow, pickRows, roadRows) {
    const t = task(planRow);
    const pick = (pickRows || []).slice().sort(byId);
    t.pickupLog = pick.length ? pickLog(pick[pick.length - 1]) : null;      // ใช้รายการล่าสุด
    t.logs = (roadRows || []).slice().sort(byId).map(roadLog);
    t.state = state(t);
    return t;
  }

  return { ON, VER, URL: URL0, call, rpc, task, full, state };
})();
