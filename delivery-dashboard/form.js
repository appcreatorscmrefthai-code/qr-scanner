/* ส่วนที่ใช้ร่วมกันของ pickup.html และ road.html */
(function () {
  const CFG = window.APP_CONFIG || {};
  const DEMO = !SB.ON;
  // ความเร็วบนมือถือ: ย่อรูปก่อนส่ง, เริ่มส่งรูปทันทีที่เลือก (ไม่รอกดปุ่ม), ส่งพร้อมกันหลายรูป
  const MAX_SIDE = 1024, QUALITY = 0.68, MB = 1024 * 1024, BATCH = 1, PARALLEL = 4;
  const taskKey = '';          // ลิงก์ QR ไม่ใช้รหัสลับแล้ว (คงพารามิเตอร์ไว้ให้ฟังก์ชันฝั่งฐานข้อมูลรุ่นเดียวกัน)
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const hhmm = iso => iso ? new Date(new Date(iso).getTime() + 7 * 3600e3).toISOString().slice(11, 16) : '';
  const fmt = iso => new Date(iso).toLocaleString('th-TH', { timeZone: 'Asia/Bangkok', dateStyle: 'medium', timeStyle: 'medium' });

  /* ---------- API (Supabase) : คืนค่า { ok:true, ... } หรือ { ok:false, error } เมื่อระบบปฏิเสธ, throw เมื่อเน็ตมีปัญหา (จะถูกลองใหม่) ---------- */
  function showVer() {
    let el = $('ver');
    if (!el) { el = document.createElement('div'); el.id = 'ver'; el.style.cssText = 'text-align:center;font-size:11px;color:#8a94a6;padding:10px 0 18px'; document.body.appendChild(el); }
    el.textContent = 'รุ่น ' + SB.VER;
  }
  const refused = e => { if (e && e.server) return { ok: false, error: e.message }; throw e; };
  function warm() { }                              // ไม่ต้องเตรียมโฟลเดอร์ล่วงหน้าแล้ว (คงไว้ให้หน้าเดิมเรียกได้)
  async function apiGet(q) {
    if (DEMO) { await sleep(250); return { ok: true, task: demoTask(q.code) }; }
    try {
      const d = await SB.rpc('form_task', { p_code: q.code, p_key: taskKey });
      showVer();
      return { ok: true, task: SB.full(d.plan, d.pickup, d.road) };
    } catch (e) { return refused(e); }
  }
  // keep = คำขอขนาดเล็กจะถูกส่งจนจบแม้ผู้ใช้ปิดหน้าไปก่อน
  async function apiPost(body, keep) {
    if (DEMO) { await sleep(300); return demoPost(body); }
    try {
      const p = Object.assign({ k: taskKey }, body);
      if (body.action === 'submit') {
        const d = await SB.rpc('form_submit', { p }, { keepalive: !!keep });
        return { ok: true, time: d.time, row: d.id, finish: d.finish, taskCode: d.taskCode, task: null };
      }
      if (body.action === 'attach') {
        p.id = body.row;
        const d = await SB.rpc('form_attach', { p }, { keepalive: !!keep });
        return { ok: true, row: d.id };
      }
      return { ok: false, error: 'ไม่รู้จักคำสั่ง: ' + body.action };
    } catch (e) { return refused(e); }
  }
  // ส่งรูปหนึ่งรูปเข้าที่เก็บรูปโดยตรง (ไฟล์ JPEG ที่ย่อแล้ว) คืนค่าที่อยู่ของรูป
  async function putPhoto(it) {
    const hh = new Date(Date.now() + 7 * 3600e3).toISOString().slice(11, 19).replace(/:/g, '');
    if (!it.path) it.path = `${it.taskCode}/p/${it.kind}${it.kind === 'unload' && it.stop ? '-s' + it.stop : ''}_${hh}_${it.no}_${Math.random().toString(36).slice(2, 7)}.jpg`;
    try {
      await SB.call('/storage/v1/object/photos/' + it.path.split('/').map(encodeURIComponent).join('/'),
        { method: 'POST', body: it.blob, headers: { 'Content-Type': 'image/jpeg', 'x-upsert': 'false' } });
    } catch (e) {
      if (e.status === 409 || /exist|duplicate/i.test(e.message || '')) return it.path;      // ส่งถึงแล้วในรอบก่อน (คำตอบหายระหว่างทาง)
      if (e.server) { const x = new Error(e.status === 403 || e.status === 400 ? 'ระบบไม่รับรูปนี้ (' + e.message + ')' : e.message); x.fatal = true; throw x; }
      throw e;
    }
    return it.path;
  }
  async function retry(fn, n) {
    let last;
    for (let i = 0; i < n; i++) {
      try { const d = await fn(); if (d && d.ok) return d; last = new Error((d && d.error) || 'ส่งข้อมูลไม่สำเร็จ'); if (d && d.error) break; }
      catch (e) { last = e; if (e && e.fatal) break; }
      if (i < n - 1) await sleep(600 * (i + 1));
    }
    throw last;
  }

  /* ---------- โหมดตัวอย่าง (ยังไม่ได้ใส่ API_URL) ---------- */
  let demo = null;
  function demoTask(code) {
    if (!demo || demo.taskCode !== code) demo = {
      taskCode: code, date: '2026-10-03', pickup: '07:30', plate: '3 ฒผ 2186', driver: '(โหมดตัวอย่าง)', vehicleType: '4ล้อเทลเกต(จัมโบ้)',
      stops: [1, 2, 3].map(i => ({ slot: i, name: 'จุดส่งตัวอย่าง ' + i, arrival: ['09:00', '10:00', '10:30'][i - 1], map: '', receiver: '' })),
      round: 'ไป-กลับ', roundTrip: true,
      pickupLog: null, logs: [], state: { checkin: null, depart: '', arrive: ['', '', ''], done: ['', '', ''], eta: ['', '', ''], lastRoad: '', roadCount: 0, returned: '' }
    };
    return demo;
  }
  function demoPost(b) {
    const t = new Date().toISOString();
    if (b.action === 'upload') return { ok: true, ids: b.files.map((_, i) => 'demo_file_' + i) };
    if (b.action === 'attach') return { ok: true, row: b.row };
    const d = demoTask(b.taskCode);
    apply(d.state, b, t, d);
    return { ok: true, time: t, row: 2, finish: b.type === 'return', task: JSON.parse(JSON.stringify(d)) };
  }

  // ผลของรายการต่อสถานะงาน (ใช้แสดงผลทันทีบนหน้าจอระหว่างรอเซิร์ฟเวอร์ตอบ)
  function apply(s, b, t, task) {
    const i = (b.stop || 0) - 1;
    if (b.type === 'checkin') { if (!s.checkin) s.checkin = { time: t, plate: b.plate }; if (task) task.plate = b.plate; }
    if (b.type === 'road') { s.lastRoad = t; s.roadCount = (s.roadCount || 0) + 1; }
    if (b.type === 'road' || b.type === 'eta') (b.eta || []).forEach((v, k) => { if (v) s.eta[k] = v; });
    if (b.type === 'arrive' && !s.arrive[i]) s.arrive[i] = t;
    if (b.type === 'unload' && !s.done[i]) { s.done[i] = t; if (!s.arrive[i]) s.arrive[i] = t; }
    if (b.type === 'return' && !s.returned) s.returned = t;
  }

  /* ---------- ข้อความแจ้ง ---------- */
  function say(text, kind) {
    const m = $('msg');
    m.hidden = !text; m.className = 'msg ' + (kind || 'err'); m.textContent = text || '';
    if (text) m.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }
  let toastTimer;
  function toast(text) {
    const t = $('toast'); if (!t) return;
    t.textContent = text; t.hidden = false;
    clearTimeout(toastTimer); toastTimer = setTimeout(() => { t.hidden = true; }, 3500);
  }
  function confirmBox(text, yes) {
    return new Promise(res => {
      const d = $('cfDlg');
      $('cfText').textContent = text; $('cfYes').textContent = yes || 'ยืนยัน';
      $('cfYes').onclick = () => { d.close(); res(true); };
      $('cfNo').onclick = () => { d.close(); res(false); };
      d.oncancel = () => res(false);
      d.showModal();
    });
  }

  /* ---------- สแกน QR (ใช้เมื่อเปิดหน้าโดยไม่ได้มาจาก QR ประจำงาน) ---------- */
  let scanner = null;
  function parseCode(text) {
    const s = String(text || '').trim();
    const m = s.match(/[?&]task=([^&#]+)/);
    return m ? decodeURIComponent(m[1]) : s;
  }
  async function startScan(onCode) {
    say('');
    // โหลดตัวสแกนเฉพาะเมื่อกดปุ่มสแกน (เปิดจาก QR ประจำงานไม่ต้องใช้ หน้าจึงเปิดเร็วขึ้น)
    if (!window.Html5Qrcode) {
      say('กำลังเปิดตัวสแกน…', 'info');
      await new Promise(res => { const sc = document.createElement('script'); sc.src = 'https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js'; sc.onload = sc.onerror = res; document.head.appendChild(sc); });
      say('');
    }
    if (!window.Html5Qrcode) return say('โหลดตัวสแกน QR ไม่สำเร็จ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่');
    $('reader').hidden = false; $('scanBtn').hidden = true;
    scanner = new Html5Qrcode('reader');
    try {
      await scanner.start({ facingMode: 'environment' }, { fps: 10, qrbox: { width: 240, height: 240 } },
        text => { stopScan().then(() => onCode(parseCode(text))); }, () => { });
    } catch (e) {
      await stopScan();
      say('เปิดกล้องไม่ได้ กรุณาอนุญาตการใช้กล้องแล้วลองใหม่');
    }
  }
  async function stopScan() {
    if (scanner) { try { await scanner.stop(); scanner.clear(); } catch (e) { } scanner = null; }
    $('reader').hidden = true; $('scanBtn').hidden = false;
  }

  /* ---------- ย่อรูป ---------- */
  async function shrink(file) {
    let src;
    // ให้เบราว์เซอร์ย่อขนาดตอนถอดรหัสรูป (เร็วและใช้หน่วยความจำน้อยกว่าบนมือถือ) ถ้าไม่รองรับจึงใช้วิธีเดิม
    try { src = await createImageBitmap(file, { imageOrientation: 'from-image' }); }
    catch (e) {
      src = await new Promise((res, rej) => {
        const im = new Image(); im.onload = () => res(im); im.onerror = () => rej(new Error('อ่านไฟล์รูปไม่ได้: ' + file.name));
        im.src = URL.createObjectURL(file);
      });
    }
    const k = Math.min(1, MAX_SIDE / Math.max(src.width, src.height));
    const c = document.createElement('canvas');
    c.width = Math.round(src.width * k); c.height = Math.round(src.height * k);
    c.getContext('2d').drawImage(src, 0, 0, c.width, c.height);
    const blob = await new Promise(r => c.toBlob(r, 'image/jpeg', QUALITY));
    if (src.close) src.close();
    if (!blob) throw new Error('แปลงรูปไม่สำเร็จ: ' + file.name);
    return blob;
  }
  const toB64 = blob => new Promise((res, rej) => {
    const fr = new FileReader(); fr.onload = () => res(String(fr.result).split(',')[1]); fr.onerror = rej; fr.readAsDataURL(blob);
  });

  /* ---------- คิวส่งรูปเบื้องหลัง ----------
     รูปเริ่มส่งทันทีที่เลือก ผู้ใช้กรอกข้อมูลต่อได้เลย พอกดบันทึกรูปส่วนใหญ่จะส่งเสร็จแล้ว */
  const queue = []; let running = 0;
  const watchers = new Set();
  function pump() {
    while (running < PARALLEL && queue.length) {
      const first = queue.shift(), batch = [first];
      for (let i = 0; i < queue.length && batch.length < BATCH;) {
        if (queue[i].group === first.group) batch.push(queue.splice(i, 1)[0]); else i++;
      }
      running++;
      send(batch).finally(() => { running--; pump(); });
    }
  }
  async function send(batch) {
    batch.forEach(it => { it.state = 'up'; }); notify();
    await Promise.all(batch.map(async it => {
      try {
        if (DEMO) { await sleep(300); it.id = 'demo_' + it.no; }
        else it.id = await retry(async () => ({ ok: true, id: await putPhoto(it) }), 3).then(d => d.id);
        it.state = 'done';
      } catch (e) { it.state = 'err'; it.error = e.message || String(e); }
    }));
    notify();
    batch.forEach(it => it.settle && it.settle());
  }
  function notify() { watchers.forEach(fn => fn()); }
  function enqueue(it) { it.state = 'wait'; it.done = new Promise(r => { it.settle = r; }); queue.push(it); pump(); }
  // รอจนรูปชุดนี้ส่งครบ (ลองใหม่ให้อัตโนมัติถ้ารูปใดส่งไม่ผ่าน) คืนค่ารายการที่ส่งสำเร็จ
  async function settle(items, tries) {
    for (let n = 0; n < (tries || 3); n++) {
      await Promise.all(items.map(it => it.done));
      const bad = items.filter(it => it.state === 'err');
      if (!bad.length) break;
      if (n < (tries || 3) - 1) { await sleep(800); bad.forEach(enqueue); }
    }
    return items.filter(it => it.state === 'done');
  }

  /* ---------- ตัวเลือกรูป ---------- */
  function makePicker(p) {
    const items = [], root = $(p.el);
    let seq = 0;
    root.innerHTML = `<label class="btn pick">+ เพิ่มรูป<input type="file" accept="image/*" multiple></label>
      <div class="grid"></div><div class="meter"></div>`;
    const input = root.querySelector('input'), grid = root.querySelector('.grid'), meter = root.querySelector('.meter');
    const total = () => items.reduce((s, x) => s + x.blob.size, 0);
    const MARK = { wait: '…', up: '↑', done: '✓', err: '!' };
    function draw() {
      grid.innerHTML = items.map((x, i) => `<div class="ph s-${x.state}"><img alt="รูปที่ ${i + 1}" src="${x.url}"><i>${MARK[x.state] || ''}</i><button type="button" data-i="${i}" aria-label="ลบรูปที่ ${i + 1}">×</button></div>`).join('');
      const sent = items.filter(x => x.state === 'done').length;
      meter.textContent = `${items.length}/${p.max} รูป · ${(total() / MB).toFixed(1)}/${p.maxMB} MB` + (items.length ? ` · ส่งแล้ว ${sent}/${items.length}` : '');
    }
    watchers.add(draw);
    grid.onclick = e => {
      const b = e.target.closest('button'); if (!b || root.dataset.busy) return;
      URL.revokeObjectURL(items.splice(Number(b.dataset.i), 1)[0].url); draw();
    };
    input.onchange = async () => {
      const files = Array.from(input.files); input.value = '';
      say('');
      const skipped = [], ctx = p.context();          // { taskCode, stop } ณ ตอนที่เลือกรูป
      for (const f of files) {
        if (items.length >= p.max) { skipped.push(`เกิน ${p.max} รูป`); break; }
        try {
          meter.textContent = 'กำลังเตรียมรูป…';
          const blob = await shrink(f);
          if (total() + blob.size > p.maxMB * MB) { skipped.push(`ขนาดรวมเกิน ${p.maxMB} MB`); break; }
          const it = { blob, url: URL.createObjectURL(blob), kind: p.kind, key: p.key, group: p.key, no: ++seq, taskCode: ctx.taskCode, stop: ctx.stop || 0 };
          items.push(it); draw();
          if (ctx.taskCode) enqueue(it); else { it.state = 'err'; it.done = Promise.resolve(); }
        } catch (e) { skipped.push(e.message); }
      }
      draw();
      if (skipped.length) say(`${p.label}: บางรูปไม่ถูกเพิ่ม (${skipped[0]})`);
    };
    draw();
    // take(): ย้ายรูปทั้งหมดออกจากตัวเลือก (หลังกดบันทึก) เพื่อให้ผู้ใช้เลือกรูปชุดถัดไปได้ทันที
    return { items, kind: p.kind, key: p.key, root, take() { const a = items.splice(0); draw(); return a; },
      clear() { items.splice(0).forEach(x => URL.revokeObjectURL(x.url)); draw(); } };
  }

  /* ---------- บันทึกรายการก่อน แล้วแนบรูปที่ยังส่งไม่เสร็จตามไป ----------
     submit: บันทึกทันทีพร้อมรูปที่ส่งเสร็จแล้ว -> สถานะขึ้น Dashboard เลย
     รูปที่ยังค้างจะถูกแนบเข้ารายการเดิม (attach) เมื่อส่งเสร็จ โดยผู้ใช้ไม่ต้องรอ */
  let pendingJobs = 0;
  function bar() {
    const p = $('prog'); if (!p) return;
    const all = [...jobItems], left = all.filter(it => it.state !== 'done' && it.state !== 'err').length;
    p.hidden = !pendingJobs;
    if (pendingJobs) {
      $('progBar').style.width = (all.length ? (all.length - left) / all.length * 100 : 100) + '%';
      $('progText').textContent = `กำลังส่งรูปที่เหลือ ${all.length - left}/${all.length} กรุณาอย่าปิดหน้านี้`;
    }
  }
  const jobItems = new Set();
  watchers.add(bar);
  // after: (ถ้ามี) รอรายการก่อนหน้าเสร็จก่อน เพื่อให้ลำดับในชีตถูกต้อง โดยหน้าจอไม่ต้องค้างรอ
  async function submitWithPhotos(body, pickers, after) {
    const taken = pickers.flatMap(pk => pk.take());
    if (after) await after.catch(() => { });
    const ids = its => { const o = {}; its.forEach(it => { (o[it.key] = o[it.key] || []).push(it.id); }); return o; };
    const ready = taken.filter(it => it.state === 'done'), rest = taken.filter(it => it.state !== 'done');
    let d;
    try { d = await retry(() => apiPost(Object.assign({ action: 'submit', pending: rest.length > 0 }, body, ids(ready)), true), 2); }
    catch (e) { pickers.forEach(pk => { taken.filter(it => it.key === pk.key).forEach(it => pk.items.push(it)); }); notify(); throw e; }   // คืนรูปกลับ ให้กดส่งใหม่ได้
    ready.forEach(it => URL.revokeObjectURL(it.url));
    d.photos = Promise.resolve({ sent: 0, total: 0 });       // สถานะการส่งรูปที่เหลือ
    if (rest.length) {
      pendingJobs++; rest.forEach(it => jobItems.add(it)); bar();
      d.photos = (async () => {
        let ok = await settle(rest, 4), attached = true;
        try { if (ok.length) await retry(() => apiPost(Object.assign({ action: 'attach', form: body.form, taskCode: body.taskCode, row: d.row }, ids(ok)), true), 3); }
        catch (e) { attached = false; say('แนบรูปเข้ารายการไม่สำเร็จ: ' + (e.message || e)); }
        if (ok.length < rest.length) say(`มีรูป ${rest.length - ok.length} รูปส่งไม่สำเร็จ กรุณาตรวจอินเทอร์เน็ตแล้วส่งรูปนั้นอีกครั้ง`);
        else if (attached) toast('ส่งรูปครบแล้ว');
        rest.forEach(it => { jobItems.delete(it); URL.revokeObjectURL(it.url); });
        pendingJobs--; bar();
        return { sent: attached ? ok.length : 0, total: rest.length };
      })();
    }
    return d;
  }
  window.addEventListener('beforeunload', e => { if (pendingJobs) { e.preventDefault(); e.returnValue = ''; } });

  // ทะเบียนรถรูปแบบเดียวกับในระบบ: "3 ฒผ 2186", "ฒผ 2186" หรือ "70-1234" (ไม่ถูกรูปแบบคืนค่าว่าง)
  function normPlate(v) {
    const s = String(v || '').replace(/\s+/g, ' ').trim();
    let m = s.match(/^(\d)?\s*([ก-ฮ]{2,3})\s*(\d{1,4})$/);
    if (m) return (m[1] ? m[1] + ' ' : '') + m[2] + ' ' + m[3];
    m = s.match(/^(\d{2})\s*-\s*(\d{4})$/);
    return m ? m[1] + '-' + m[2] : '';
  }

  function taskCard(t) {
    const s = t.state || {};
    return `<div class="task"><div class="code">${esc(t.taskCode)}</div>
      ${(t.stops || []).map((st, i) => `<div>${i + 1}. ${esc(st.name)} <span class="m">นัด ${esc(st.arrival || '-')}${s.done && s.done[i] ? ' · ลงงานแล้ว ' + hhmm(s.done[i]) : s.arrive && s.arrive[i] ? ' · ถึงหน้างาน ' + hhmm(s.arrive[i]) : ''}</span></div>`).join('')}
      ${t.roundTrip ? `<div>↩ กลับ SCM <span class="m">${s.returned ? 'ถึงแล้ว ' + hhmm(s.returned) : 'รอบไป-กลับ'}</span></div>` : ''}
      <div class="m">${esc([t.driver, t.vehicleType, t.plate, t.pickup ? 'ตารางเวลา ' + t.pickup : ''].filter(Boolean).join(' · '))}</div></div>`;
  }

  function clock() {
    const tick = () => { $('stamp').textContent = fmt(new Date()); };
    tick(); setInterval(tick, 1000);
  }

  // ผู้ให้บริการขนส่งที่ใช้ฟอร์มแบบ GPS (ตัดช่องว่างก่อนเทียบ)
  const isGpsCompany = c => String(c || '').replace(/\s+/g, '').includes('ปทุมทรานสปอร์ต');
  window.DF = { CFG, isGpsCompany, DEMO, $, esc, hhmm, fmt, apiGet, apiPost, retry, say, toast, confirmBox, startScan, parseCode,
    makePicker, submitWithPhotos, warm, apply, normPlate, taskCard, clock, param: k => new URLSearchParams(location.search).get(k) };
})();
