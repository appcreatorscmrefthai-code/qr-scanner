/* ส่วนที่ใช้ร่วมกันของ pickup.html และ road.html */
(function () {
  const CFG = window.APP_CONFIG || {};
  const DEMO = !CFG.API_URL;
  // ย่อรูปก่อนส่ง และส่งหลายรูปต่อครั้ง หลายคำขอพร้อมกัน เพื่อให้บันทึกเร็วบนเน็ตมือถือ
  const MAX_SIDE = 1280, QUALITY = 0.72, MB = 1024 * 1024, BATCH = 3, PARALLEL = 3;
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const hhmm = iso => iso ? new Date(new Date(iso).getTime() + 7 * 3600e3).toISOString().slice(11, 16) : '';
  const fmt = iso => new Date(iso).toLocaleString('th-TH', { timeZone: 'Asia/Bangkok', dateStyle: 'medium', timeStyle: 'medium' });

  /* ---------- API ---------- */
  async function apiGet(q) {
    if (DEMO) { await sleep(250); return { ok: true, task: demoTask(q.code) }; }
    return (await fetch(CFG.API_URL + '?' + new URLSearchParams(q))).json();
  }
  async function apiPost(body) {
    if (DEMO) { await sleep(300); return demoPost(body); }
    // ไม่ใส่ Content-Type เอง เพื่อให้เป็น simple request (Apps Script ไม่รองรับ preflight)
    return (await fetch(CFG.API_URL, { method: 'POST', body: JSON.stringify(body) })).json();
  }
  async function retry(fn, n) {
    let last;
    for (let i = 0; i < n; i++) {
      try { const d = await fn(); if (d && d.ok) return d; last = new Error((d && d.error) || 'ส่งข้อมูลไม่สำเร็จ'); if (d && d.error) break; }
      catch (e) { last = e; }
      if (i < n - 1) await sleep(700 * (i + 1));
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
    const d = demoTask(b.taskCode), s = d.state, i = (b.stop || 0) - 1;
    if (b.type === 'checkin') { s.checkin = { time: t, plate: b.plate }; d.plate = b.plate; }
    if (b.type === 'road') { s.lastRoad = t; (b.eta || []).forEach((v, k) => { if (v) s.eta[k] = v; }); }
    if (b.type === 'arrive') s.arrive[i] = t;
    if (b.type === 'unload') s.done[i] = t;
    if (b.type === 'return') s.returned = t;
    return { ok: true, time: t, finish: b.type === 'return', task: d };
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
  // QR ประจำงานเป็นลิงก์ที่มี ?task=รหัส ถ้าสแกนในหน้าได้ลิงก์มาให้ดึงรหัสออก
  function parseCode(text) {
    const s = String(text || '').trim();
    const m = s.match(/[?&]task=([^&#]+)/);
    return m ? decodeURIComponent(m[1]) : s;
  }
  async function startScan(onCode) {
    say('');
    if (!window.Html5Qrcode) return say('โหลดตัวสแกน QR ไม่สำเร็จ กรุณาตรวจอินเทอร์เน็ตแล้วเปิดหน้านี้ใหม่');
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

  /* ---------- ตัวเลือกรูป ---------- */
  function makePicker(p) {
    const items = [], root = $(p.el);
    root.innerHTML = `<label class="btn pick">+ เพิ่มรูป<input type="file" accept="image/*" multiple></label>
      <div class="grid"></div><div class="meter"></div>`;
    const input = root.querySelector('input'), grid = root.querySelector('.grid'), meter = root.querySelector('.meter');
    const total = () => items.reduce((s, x) => s + x.blob.size, 0);
    function draw() {
      grid.innerHTML = items.map((x, i) => `<div class="ph"><img alt="รูปที่ ${i + 1}" src="${x.url}"><button type="button" data-i="${i}" aria-label="ลบรูปที่ ${i + 1}">×</button></div>`).join('');
      meter.textContent = `${items.length}/${p.max} รูป · ${(total() / MB).toFixed(1)}/${p.maxMB} MB`;
    }
    grid.onclick = e => {
      const b = e.target.closest('button'); if (!b || root.dataset.busy) return;
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
    return { items, kind: p.kind, key: p.key, root, clear() { items.splice(0).forEach(x => URL.revokeObjectURL(x.url)); draw(); } };
  }

  /* ---------- ส่งรูป: ครั้งละ BATCH รูป พร้อมกัน PARALLEL คำขอ ---------- */
  async function uploadAll(taskCode, pickers, stop, onProgress) {
    const jobs = [], ids = {};
    let total = 0, done = 0, next = 0;
    pickers.forEach(pk => {
      ids[pk.key] = []; total += pk.items.length;
      for (let i = 0; i < pk.items.length; i += BATCH) jobs.push({ pk, start: i, items: pk.items.slice(i, i + BATCH) });
    });
    onProgress(0, total);
    async function run(job) {
      const files = await Promise.all(job.items.map(async (it, j) => ({ data: await toB64(it.blob), index: job.start + j + 1 })));
      const d = await retry(() => apiPost({ action: 'upload', taskCode, kind: job.pk.kind, stop: stop || 0, files }), 3);
      job.ids = d.ids; done += job.items.length; onProgress(done, total);
    }
    await Promise.all(Array.from({ length: Math.min(PARALLEL, jobs.length) }, async () => { while (next < jobs.length) await run(jobs[next++]); }));
    jobs.forEach(j => ids[j.pk.key].push(...j.ids));
    return ids;
  }

  function progress(done, total) {
    const p = $('prog'); if (!p) return;
    p.hidden = false;
    $('progBar').style.width = (total ? done / total * 100 : 100) + '%';
    $('progText').textContent = total ? `กำลังส่งรูป ${done}/${total}` : 'กำลังบันทึก…';
  }

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

  window.DF = { CFG, DEMO, $, esc, hhmm, fmt, apiGet, apiPost, retry, say, toast, confirmBox, startScan, parseCode,
    makePicker, uploadAll, progress, normPlate, taskCard, clock, param: k => new URLSearchParams(location.search).get(k) };
})();
