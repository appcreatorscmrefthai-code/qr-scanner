/* ตรรกะร่วมของฟอร์ม pickup.html และ road.html */
(function () {
  const CFG = window.APP_CONFIG || {};
  const DEMO = !CFG.API_URL;
  const MAX_SIDE = 1600, QUALITY = 0.8, MB = 1024 * 1024;
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  let task = null, scanner = null, busy = false, opts = null, stopSel = 0;
  const pickers = {};

  /* ---------- API ---------- */
  async function apiGet(q) {
    if (DEMO) { await sleep(300); return { ok: true, task: { taskCode: q.code, driver: '(โหมดตัวอย่าง)', pickup: '07:30', done: [1],
      stops: [{ name: 'จุดส่งตัวอย่าง 1', arrival: '09:00' }, { name: 'จุดส่งตัวอย่าง 2', arrival: '10:00' }, { name: 'จุดส่งตัวอย่าง 3', arrival: '10:30' }] } }; }
    const r = await fetch(CFG.API_URL + '?' + new URLSearchParams(q));
    return r.json();
  }
  async function apiPost(body) {
    if (DEMO) { await sleep(250); return { ok: true, id: 'demo', time: new Date().toISOString() }; }
    // ไม่ใส่ Content-Type เอง เพื่อให้เป็น simple request (Apps Script ไม่รองรับ preflight)
    const r = await fetch(CFG.API_URL, { method: 'POST', body: JSON.stringify(body) });
    return r.json();
  }
  async function retry(fn, n) {
    let last;
    for (let i = 0; i < n; i++) {
      try { const d = await fn(); if (d && d.ok) return d; last = new Error((d && d.error) || 'ส่งข้อมูลไม่สำเร็จ'); }
      catch (e) { last = e; }
      await sleep(800 * (i + 1));
    }
    throw last;
  }

  /* ---------- ข้อความแจ้ง ---------- */
  function say(text, kind) {
    const m = $('msg');
    m.hidden = !text; m.className = 'msg ' + (kind || 'err'); m.textContent = text || '';
    if (text) m.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }

  /* ---------- สแกน QR ---------- */
  async function startScan() {
    say('');
    if (!window.Html5Qrcode) { say('โหลดตัวสแกน QR ไม่สำเร็จ กรุณาตรวจอินเทอร์เน็ตแล้วเปิดหน้านี้ใหม่'); return; }
    $('reader').hidden = false; $('scanBtn').hidden = true;
    scanner = new Html5Qrcode('reader');
    try {
      await scanner.start({ facingMode: 'environment' }, { fps: 10, qrbox: { width: 240, height: 240 } },
        text => { stopScan().then(() => setTask(text)); }, () => { });
    } catch (e) {
      await stopScan();
      say('เปิดกล้องไม่ได้ กรุณาอนุญาตการใช้กล้องแล้วลองใหม่');
    }
  }
  async function stopScan() {
    if (scanner) { try { await scanner.stop(); scanner.clear(); } catch (e) { } scanner = null; }
    $('reader').hidden = true; $('scanBtn').hidden = !!task;
  }
  async function setTask(raw) {
    const code = String(raw || '').trim();
    if (!code) return;
    say('กำลังตรวจสอบ Task Code…', 'info');
    try {
      const d = await retry(() => apiGet({ action: 'task', code }), 2);
      task = d.task;
      $('taskBox').hidden = false; $('scanBtn').hidden = true;
      $('taskBox').innerHTML = `<div class="task"><div class="code">${esc(task.taskCode)}</div>
        ${(task.stops || []).map((st, i) => `<div>${i + 1}. ${esc(st.name)} <span class="m">${esc(st.arrival)}</span></div>`).join('')}
        <div class="m">${esc([task.driver, task.pickup ? 'Pickup ' + task.pickup : ''].filter(Boolean).join(' · '))}</div></div>
        <button class="btn ghost" id="rescan" style="margin-top:10px">สแกนใหม่</button>`;
      $('rescan').onclick = () => { task = null; $('taskBox').hidden = true; drawStops(); refresh(); startScan(); };
      drawStops();
      say('');
    } catch (e) {
      task = null; $('scanBtn').hidden = false;
      say(e.message || 'ไม่พบ Task Code นี้');
    }
    refresh();
  }

  /* ---------- เลือกจุดส่ง (เฉพาะฟอร์มบนถนน) ---------- */
  function drawStops() {
    const box = $('stopBox'); if (!box) return;
    const stops = (task && task.stops) || [], done = (task && task.done) || [];
    if (!stops.length) { box.innerHTML = '<div class="meter">สแกน QR Task Code ก่อน จึงจะเลือกจุดส่งได้</div>'; stopSel = 0; label(); return; }
    stopSel = 0;
    for (let i = 1; i <= stops.length; i++) if (done.indexOf(i) < 0) { stopSel = i; break; }
    box.innerHTML = stops.map((st, i) => {
      const d = done.indexOf(i + 1) >= 0;
      return `<label class="stop ${d ? 'isdone' : ''}"><input type="radio" name="stop" value="${i + 1}" ${d ? 'disabled' : ''} ${stopSel === i + 1 ? 'checked' : ''}>
        <span><b>จุดที่ ${i + 1}${i + 1 === stops.length ? ' (จุดสุดท้าย)' : ''}</b> ${esc(st.name)}<br><span class="m">${d ? 'ลงงานแล้ว' : 'นัดถึง ' + esc(st.arrival) + ' น.'}</span></span></label>`;
    }).join('') + (stopSel ? '' : '<div class="meter">ลงงานครบทุกจุดแล้ว</div>');
    box.onchange = e => { stopSel = Number(e.target.value) || 0; label(); };
    label();
  }
  function label() {
    const b = document.querySelector('[data-send="finish"]'); if (!b) return;
    const n = task && task.stops ? task.stops.length : 0;
    b.textContent = !stopSel ? 'ลงงานเสร็จ' : stopSel === n ? `ลงงานจุดที่ ${stopSel} เสร็จ และจบงาน` : `ลงงานจุดที่ ${stopSel} เสร็จ`;
  }

  /* ---------- ย่อรูป ---------- */
  async function shrink(file) {
    let src;
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
    if (!blob) throw new Error('แปลงรูปไม่สำเร็จ: ' + file.name);
    return blob;
  }
  const toB64 = blob => new Promise((res, rej) => {
    const fr = new FileReader(); fr.onload = () => res(String(fr.result).split(',')[1]); fr.onerror = rej; fr.readAsDataURL(blob);
  });

  /* ---------- ตัวเลือกรูป ---------- */
  function makePicker(p) {
    const items = [];
    const root = $(p.el);
    root.innerHTML = `<label class="btn pick">+ เพิ่มรูป<input type="file" accept="image/*" multiple></label>
      <div class="grid"></div><div class="meter"></div>`;
    const input = root.querySelector('input'), grid = root.querySelector('.grid'), meter = root.querySelector('.meter');
    const total = () => items.reduce((s, x) => s + x.blob.size, 0);
    function draw() {
      grid.innerHTML = items.map((x, i) => `<div class="ph"><img alt="รูปที่ ${i + 1}" src="${x.url}"><button type="button" data-i="${i}" aria-label="ลบรูปที่ ${i + 1}">×</button></div>`).join('');
      meter.textContent = `${items.length}/${p.max} รูป · ${(total() / MB).toFixed(1)}/${p.maxMB} MB`;
      refresh();
    }
    grid.onclick = e => {
      const b = e.target.closest('button'); if (!b || busy) return;
      URL.revokeObjectURL(items.splice(Number(b.dataset.i), 1)[0].url); draw();
    };
    input.onchange = async () => {
      const files = Array.from(input.files); input.value = '';
      say('');
      const skipped = [];
      for (const f of files) {
        if (items.length >= p.max) { skipped.push(`เกิน ${p.max} รูป`); break; }
        try {
          meter.textContent = 'กำลังเตรียมรูป…';
          const blob = await shrink(f);
          if (total() + blob.size > p.maxMB * MB) { skipped.push(`ขนาดรวมเกิน ${p.maxMB} MB`); break; }
          items.push({ blob, url: URL.createObjectURL(blob) });
        } catch (e) { skipped.push(e.message); }
      }
      draw();
      if (skipped.length) say(`${p.label}: บางรูปไม่ถูกเพิ่ม (${skipped[0]})`);
    };
    draw();
    return { items, kind: p.kind, key: p.key, clear() { items.splice(0).forEach(x => URL.revokeObjectURL(x.url)); draw(); } };
  }

  /* ---------- ส่งข้อมูล ---------- */
  function refresh() {
    document.querySelectorAll('[data-send]').forEach(b => { b.disabled = busy || !task || (b.dataset.send === 'finish' && !stopSel); });
  }
  async function send(stop) {
    const finish = !!stop && task && stop === task.stops.length;
    if (busy) return;
    say('');
    if (!task) return say('กรุณาสแกน QR Task Code ก่อน');
    const note = $('note').value.trim();
    const count = k => pickers[k] ? pickers[k].items.length : 0;
    if (opts.form === 'pickup' && !count('photos')) return say('กรุณาแนบรูปส่งงานอย่างน้อย 1 รูป');
    if (opts.form === 'road' && !stop && count('unload')) return say('มีรูปลงงานแนบอยู่ กรุณากดปุ่ม "ลงงานเสร็จ" แทน หรือลบรูปลงงานออกก่อน');
    if (opts.form === 'road' && !stop && !count('road') && !note) return say('กรุณาแนบรูปสถานการณ์บนถนน หรือใส่หมายเหตุ');

    busy = true; refresh();
    const all = Object.values(pickers).flatMap(pk => pk.items.map((it, i) => ({ pk, it, i })));
    $('prog').hidden = false;
    const step = n => { $('progBar').style.width = (all.length ? n / all.length * 100 : 100) + '%'; $('progText').textContent = `กำลังส่งรูป ${n}/${all.length}`; };
    try {
      const ids = {};
      let n = 0; step(0);
      for (const a of all) {
        const data = await toB64(a.it.blob);
        const d = await retry(() => apiPost({ action: 'upload', taskCode: task.taskCode, kind: a.pk.kind, stop: stop || 0, index: a.i + 1, mime: 'image/jpeg', data }), 3);
        (ids[a.pk.key] = ids[a.pk.key] || []).push(d.id);
        step(++n);
      }
      $('progText').textContent = 'กำลังบันทึก…';
      const d = await retry(() => apiPost(Object.assign({ action: 'submit', form: opts.form, taskCode: task.taskCode, note, stop: stop || 0 }, ids)), 2);
      const t = new Date(d.time);
      $('formBox').hidden = true; $('doneBox').hidden = false;
      $('doneText').innerHTML = `<b>${esc(task.taskCode)}</b><br>${finish ? 'ลงงานครบทุกจุด จบงานเรียบร้อย' : stop ? 'ลงงานจุดที่ ' + stop + ' เรียบร้อย' : 'บันทึกข้อมูลเรียบร้อย'}<br>
        <span style="color:var(--muted)">${t.toLocaleString('th-TH', { timeZone: 'Asia/Bangkok', dateStyle: 'medium', timeStyle: 'medium' })}</span>`;
      window.scrollTo(0, 0);
    } catch (e) {
      say('ส่งข้อมูลไม่สำเร็จ: ' + (e.message || e) + ' กรุณากดส่งอีกครั้ง');
    } finally {
      busy = false; $('prog').hidden = true; refresh();
    }
  }
  function reset() {
    task = null; $('note').value = ''; drawStops();
    Object.values(pickers).forEach(p => p.clear());
    $('taskBox').hidden = true; $('scanBtn').hidden = false;
    $('formBox').hidden = false; $('doneBox').hidden = true; say(''); refresh();
  }

  /* ---------- เริ่มต้น ---------- */
  window.DeliveryForm = {
    init(o) {
      opts = o;
      o.pickers.forEach(p => { pickers[p.key] = makePicker(p); });
      $('scanBtn').onclick = startScan;
      $('again').onclick = reset;
      document.querySelectorAll('[data-send]').forEach(b => {
        b.onclick = () => {
          if (b.dataset.send !== 'finish') return send(0);
          if (!task) return say('กรุณาสแกน QR Task Code ก่อน');
          if (!stopSel) return say('กรุณาเลือกจุดส่ง');
          const st = task.stops[stopSel - 1], lastStop = stopSel === task.stops.length;
          $('finText').textContent = `ยืนยันลงงานจุดที่ ${stopSel} (${st.name}) เสร็จ ?` + (lastStop ? ' จุดนี้เป็นจุดสุดท้าย ระบบจะจบงานของ ' + task.taskCode : '');
          $('finYes').textContent = lastStop ? 'ยืนยันจบงาน' : 'ยืนยัน';
          $('finDlg').showModal();
        };
      });
      if ($('finYes')) {
        $('finYes').onclick = () => { $('finDlg').close(); send(stopSel); };
        $('finNo').onclick = () => $('finDlg').close();
      }
      const tick = () => { $('stamp').textContent = new Date().toLocaleString('th-TH', { timeZone: 'Asia/Bangkok', dateStyle: 'medium', timeStyle: 'medium' }); };
      tick(); setInterval(tick, 1000);
      if (DEMO) { $('demo').hidden = false; }
      const pre = new URLSearchParams(location.search).get('task');
      drawStops();
      if (pre) setTask(pre);
      refresh();
    }
  };
})();
