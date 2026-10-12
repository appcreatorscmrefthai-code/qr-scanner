/* หน้า Backup (backup.html) : สถานะ Backup, ดาวน์โหลดไฟล์ Excel รายคืนจาก Supabase Storage (bucket backups), สร้าง Excel สดในเบราว์เซอร์ด้วย SheetJS
   ใช้ config.js / api.js / auth.js ร่วมกับหน้าอื่น ไม่ใช้ localStorage เอง */
(function () {
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const MON = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  const XLSX_URL = 'https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js';
  const p2 = n => String(n).padStart(2, '0');
  const say = (t, k) => { $('msg').textContent = t || ''; $('msg').className = k || ''; };
  const prog = (t, k) => { $('prog').textContent = t || ''; $('prog').className = k || ''; };

  /* ---------- เวลาไทย ---------- */
  const bkk = ms => new Date(ms + 7 * 3600e3);                     // ใช้ getUTC* ของค่าที่ได้ = เวลาไทย
  function thaiDT(iso) {
    const t = Date.parse(iso); if (isNaN(t)) return '-';
    const d = bkk(t);
    return `${d.getUTCDate()} ${MON[d.getUTCMonth()]} ${d.getUTCFullYear()} ${p2(d.getUTCHours())}:${p2(d.getUTCMinutes())} น.`;
  }
  function thaiDate(ymd) {
    const m = String(ymd).match(/^(\d{4})(-?)(\d{2})\2(\d{2})$/);
    return m ? `${+m[4]} ${MON[+m[3] - 1]} ${m[1]}` : ymd;
  }
  function ago(h) {
    if (h == null) return '';
    if (h < 1) return 'ไม่ถึง 1 ชั่วโมงที่แล้ว';
    if (h < 48) return `${Math.round(h)} ชั่วโมงที่แล้ว`;
    return `${Math.floor(h / 24)} วัน ${Math.round(h % 24)} ชม. ที่แล้ว`;
  }
  const nowBkkDate = () => bkk(Date.now()).toISOString().slice(0, 10);
  const size = n => n == null ? '' : n >= 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(n / 1024)) + ' KB';

  /* ---------- Storage (ใช้โทเคนของผู้ใช้ที่ Auth ต่ออายุให้) ---------- */
  async function tok() {
    let a = Auth.get();
    if (!a || !a.access || a.exp - 60000 < Date.now()) { await Auth.rpc('backup_status'); a = Auth.get(); }   // เรียก RPC เพื่อให้ Auth ต่ออายุโทเคน
    return a.access;
  }
  async function store(path, body) {
    try { return await SB.call(path, { token: await tok(), body }); }
    catch (e) {
      if (e.status !== 401) throw e;
      await Auth.rpc('backup_status');
      return SB.call(path, { token: (Auth.get() || {}).access, body });
    }
  }
  const fileLabel = n => {
    if (n === 'Delivery_Backup_latest.xlsx') return 'ล่าสุด';
    const m = n.match(/^Delivery_Backup_(\d{8})\.xlsx$/);
    return m ? 'คืนวันที่ ' + thaiDate(m[1]) : n;
  };
  async function download(name, btn) {
    const old = btn && btn.textContent;
    if (btn) { btn.disabled = true; btn.textContent = 'กำลังเตรียมไฟล์…'; }
    try {
      const r = await store('/storage/v1/object/sign/backups/' + encodeURIComponent(name), { expiresIn: 300 });
      const u = r && (r.signedURL || r.signedUrl);
      if (!u) throw new Error('ไม่พบไฟล์นี้บนระบบ');
      const a = document.createElement('a');
      a.href = SB.URL + '/storage/v1' + u + (u.includes('?') ? '&' : '?') + 'download=' + encodeURIComponent(name);
      a.rel = 'noopener'; document.body.appendChild(a); a.click(); a.remove();
      say('เริ่มดาวน์โหลด ' + name, 'ok');
    } catch (e) {
      say(e.status === 400 || e.status === 404 ? 'ไม่พบไฟล์ ' + name + ' บนระบบ (อาจถูกลบตามรอบหมุนไฟล์ ลองรีเฟรชหน้านี้)' : 'ดาวน์โหลดไม่สำเร็จ: ' + (e.message || e), 'err');
    } finally { if (btn) { btn.disabled = false; btn.textContent = old; } }
  }

  /* ---------- 1) สถานะ ---------- */
  async function loadStatus() {
    const box = $('stat');
    try {
      const s = await Auth.rpc('backup_status'), info = s.info || {};
      const h = s.age_hours, never = !s.last_ok, stale = !never && h > 26;
      const failedLast = info.ok === false && s.last_run;
      let cls, head;
      if (never) { cls = 'bad'; head = 'ยังไม่เคยมี Backup สำเร็จ กรุณาแจ้งผู้ดูแลตรวจสอบบอต Backup ที่เครื่อง Admin'; }
      else if (stale) { cls = 'bad'; head = `คำเตือน: Backup สำเร็จครั้งล่าสุดเมื่อ ${thaiDT(s.last_ok)} (${ago(h)}) เกิน 26 ชั่วโมงแล้ว กรุณาแจ้งผู้ดูแลตรวจสอบเครื่อง Admin`; }
      else if (failedLast) { cls = 'warn'; head = `Backup สำเร็จล่าสุด ${thaiDT(s.last_ok)} (${ago(h)}) แต่รอบล่าสุดไม่สมบูรณ์`; }
      else { cls = 'ok'; head = `Backup ปกติ : สำเร็จล่าสุด ${thaiDT(s.last_ok)} (${ago(h)})`; }
      const n = v => v == null ? '-' : Number(v).toLocaleString('en-US');
      box.className = '';
      box.innerHTML = `<div class="ban ${cls}" role="${cls === 'bad' ? 'alert' : 'status'}">${esc(head)}</div>
        ${failedLast ? `<div class="ban warn">รอบล่าสุด ${esc(thaiDT(s.last_run))} : ${esc(info.message || 'ไม่สมบูรณ์')}</div>` : ''}
        <div class="facts">
          <div><b>${n(info.tasks)}</b><span>งานทั้งหมดใน Backup</span></div>
          <div><b>${n(info.photos_total)}</b><span>รูปทั้งหมดที่เก็บไว้</span></div>
          <div><b>${n(info.photos_new)}</b><span>รูปใหม่ในรอบล่าสุด</span></div>
          <div><b>${n(info.photos_missing)}</b><span>รูปที่ไม่มีใน Storage แล้ว</span></div>
        </div>
        <p class="muted small" style="margin:.7em 0 0">รอบล่าสุดที่บอตรัน : ${esc(s.last_run ? thaiDT(s.last_run) : '-')}${info.message && !failedLast ? ' · ' + esc(info.message) : ''}</p>`;
    } catch (e) {
      box.className = '';
      box.innerHTML = `<div class="ban bad" role="alert">อ่านสถานะ Backup ไม่ได้: ${esc(e.message || e)}${/function|schema|PGRST202/i.test(e.message || '') ? ' (ผู้ดูแลต้องรัน supabase_setup.sql รุ่น s10 ก่อน)' : ''}</div>`;
    }
  }

  /* ---------- 2) รายการไฟล์ ---------- */
  async function loadFiles() {
    const box = $('files'), btn = $('dlLatest');
    try {
      const rows = (await store('/storage/v1/object/list/backups', { prefix: '', limit: 100, offset: 0, sortBy: { column: 'name', order: 'desc' } })) || [];
      const seen = new Set(), all = rows.filter(r => /^Delivery_Backup_(latest|\d{8})\.xlsx$/.test(r.name || '') && !seen.has(r.name) && seen.add(r.name));
      const latest = all.find(r => r.name === 'Delivery_Backup_latest.xlsx');
      const dated = all.filter(r => r !== latest).sort((a, b) => a.name < b.name ? 1 : -1);
      if (latest) {
        btn.disabled = false; btn.onclick = () => download(latest.name, btn);
        $('latestInfo').textContent = `อัปเดตเมื่อ ${thaiDT(latest.updated_at || latest.created_at)}${latest.metadata && latest.metadata.size ? ' · ' + size(latest.metadata.size) : ''}`;
      } else { btn.disabled = true; $('latestInfo').textContent = 'ยังไม่มีไฟล์ล่าสุดบนระบบ'; }
      box.className = '';
      box.innerHTML = dated.length ? `<div class="files">${dated.map(r => `<div class="file"><div class="nm">${esc(fileLabel(r.name))}<small>${esc(r.name)}${r.metadata && r.metadata.size ? ' · ' + size(r.metadata.size) : ''}</small></div>
          <button type="button" data-n="${esc(r.name)}">ดาวน์โหลด</button></div>`).join('')}</div>
        <p class="muted small" style="margin:.5em 0 0">เก็บไฟล์รายคืนย้อนหลัง 30 คืนล่าสุด</p>`
        : '<span class="muted">ยังไม่มีไฟล์ Backup รายคืนบนระบบ</span>';
      box.querySelectorAll('button[data-n]').forEach(b => b.onclick = () => download(b.dataset.n, b));
    } catch (e) {
      box.className = 'muted';
      box.innerHTML = `<span style="color:var(--red)">อ่านรายการไฟล์ไม่ได้: ${esc(e.message || e)}</span>`;
    }
  }

  /* ---------- 3) สร้าง Excel สดในเบราว์เซอร์ ---------- */
  function loadXlsx() {
    if (window.XLSX) return Promise.resolve();
    if (loadXlsx.p) return loadXlsx.p;
    loadXlsx.p = new Promise((res, rej) => {
      const s = document.createElement('script');
      s.src = XLSX_URL; s.onload = res;
      s.onerror = () => { loadXlsx.p = null; rej(new Error('โหลดไลบรารีสร้างไฟล์ Excel ไม่สำเร็จ (ต้องเข้า cdnjs.cloudflare.com ได้) กรุณาลองใหม่ หรือดาวน์โหลดไฟล์ Backup รายคืนแทน')); };
      document.head.appendChild(s);
    });
    return loadXlsx.p;
  }
  // หัวตารางเหมือนไฟล์ Backup ของบอต (และชีตใน Excel macro)
  const PLAN_KEYS = 'task_code,date,detail,client,transport,schedule,arr1,arr2,arr3,company,vehicle_type,plate,driver,phone,round,stop1,map1,rec1,stop2,map2,rec2,stop3,map3,rec3,status'.split(',');
  const PLAN_HEADS = ('Task Code|Date|Detail|Client Name|Transport|Schedule|Arrival Time 1|Arrival Time 2|Arrival Time 3|ชื่อบริษัทขนส่ง|ประเภทรถ|ทะเบียนรถ|ชื่อผู้ขับ|เบอร์โทรผู้ขับ|รอบขนส่ง|' +
    'จุดที่ 1|Map1|ชื่อ-เบอร์โทรผู้รับ จุดที่ 1|จุดที่ 2|Map2|ชื่อ-เบอร์โทรผู้รับ จุดที่ 2|จุดที่ 3|Map3|ชื่อ-เบอร์โทรผู้รับ จุดที่ 3|Task Status|Synced|สถานะใน Backup').split('|');
  const PICKUP_HEADS = ['Timestamp', 'วันที่งาน', 'Task Code', 'ชื่อบริษัทขนส่ง', 'ทะเบียนรถ', 'ชื่อผู้ขับ', 'หมายเหตุ', 'จำนวนรูป (คลังสินค้า)', 'โฟลเดอร์รูปในเครื่อง', 'ที่มา (คน/GPS)', 'ID'];
  const ROAD_HEADS = ['Timestamp', 'วันที่งาน', 'Task Code', 'ประเภท', 'จุดที่', 'ชื่อจุดส่ง', 'ทะเบียนรถ', 'ทะเบียนเดิม (ถ้าแก้ไข)', 'หมายเหตุ', 'คาดว่าจะถึงจุดที่ 1', 'คาดว่าจะถึงจุดที่ 2', 'คาดว่าจะถึงจุดที่ 3',
    'จำนวนรูปบนถนน', 'จำนวนรูปลงงาน', 'โฟลเดอร์รูปในเครื่อง', 'จบงาน', 'ที่มา (คน/GPS)', 'ID'];
  const EDIT_HEADS = ['Timestamp', 'วันที่งาน', 'Task Code', 'ช่องทาง', 'รายการที่แก้ไข', 'ค่าเดิม', 'ค่าใหม่', 'ผู้แก้ไข', 'ID'];
  const DELAY_HEADS = ['วันที่งาน', 'Task Code', 'จุดที่', 'ชื่อจุดส่ง', 'ชื่อบริษัทขนส่ง', 'ทะเบียนรถ', 'เวลานัด', 'เวลาถึงจริง', 'ช้า(+)/เร็ว(-) นาที', 'ผล', 'ที่มา (คน/GPS)'];
  const TREND_TAIL = ['จำนวนจุดส่ง', 'ทันเวลา', 'ช้า', '% ทันเวลา', 'ช้า(+)/เร็ว(-) เฉลี่ย (นาที)', 'ช้าเฉลี่ย เฉพาะที่ช้า (นาที)', 'ช้าสุด (นาที)', 'เวลาถึงจาก GPS (จุด)'];
  const ROAD_TH = { checkin: 'เช็คอิน', depart: 'รถออก', eta: 'เวลาคาดถึง', road: 'บนถนน', arrive: 'ถึงหน้างาน', unload: 'ลงงานเสร็จ', return: 'กลับถึงต้นทาง' };
  const ILLEGAL = /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g;
  const safeName = s => (String(s ?? '').replace(/[<>:"/\\|?*\u0000-\u001f]/g, '_').replace(/^[ .]+|[ .]+$/g, '') || '_').slice(0, 150);
  const xs = v => v == null || v === '' ? null : typeof v === 'boolean' ? (v ? 'ใช่' : null) : typeof v === 'number' ? v : String(v).replace(ILLEGAL, '').slice(0, 32000);
  function stopNames(p) {
    const n = [1, 2, 3].map(k => String(p['stop' + k] || '').trim()).filter(Boolean);
    return n.length ? n : [String(p.detail || '').trim()];
  }
  function rowDirs(kind, r) {
    const t = safeName(r.task_code), c = [];
    if (kind === 'pickup' && (r.photos || []).length) c.push('ส่งจากคลังสินค้า');
    if (kind === 'road') {
      if ((r.road || []).length) c.push('สถานการณ์บนถนน');
      if ((r.unload || []).length) {
        const k = +r.stop || 0;
        c.push(r.type === 'return' ? 'ลงงานส่งกลับ' : (r.type === 'arrive' || r.type === 'unload') ? (k >= 1 && k <= 3 ? 'ลงงานจุดที่ ' + k : 'ลงงาน (ไม่ระบุจุด)') : 'รูปอื่นๆ');
      }
    }
    return c.map(x => 'Photos\\' + t + '\\' + x).join(' | ');
  }
  function aggregate(rows, group) {
    const g = {};
    rows.forEach(r => { const d = String(r.date || ''); (g[group === 'month' ? d.slice(0, 7) : d.slice(0, 10)] ||= []).push(r); });
    const r1 = v => Math.round(v * 10) / 10;
    return Object.keys(g).sort().map(per => {
      const rs = g[per], diffs = rs.filter(r => r.diff_min != null).map(r => +r.diff_min), late = rs.filter(r => r.diff_min != null && !r.ontime).map(r => +r.diff_min);
      const ok = rs.filter(r => r.ontime).length, n = rs.length;
      return [per, n, ok, n - ok, n ? r1(100 * ok / n) : null, diffs.length ? r1(diffs.reduce((a, b) => a + b, 0) / diffs.length) : null,
        late.length ? r1(late.reduce((a, b) => a + b, 0) / late.length) : null, late.length ? Math.max(...late) : null, rs.filter(r => r.source === 'GPS').length];
    });
  }
  function sheet(heads, rows) {
    const body = rows.map(r => r.map(xs)), ws = XLSX.utils.aoa_to_sheet([heads, ...body]);
    const w = heads.map(h => String(h).length * 1.3 + 2);
    body.slice(0, 400).forEach(r => r.forEach((v, i) => { if (v != null) w[i] = Math.max(w[i], Math.max(...String(v).split('\n').map(x => x.length)) * 1.15 + 2); }));
    ws['!cols'] = w.map(x => ({ wch: Math.max(8, Math.min(60, x)) }));
    ws['!autofilter'] = { ref: XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: Math.max(1, body.length), c: heads.length - 1 } }) };
    return ws;
  }
  function buildWorkbook(plan, pickup, road, edit, delay, infoRows) {
    const pmap = {}; plan.forEach(p => { pmap[p.task_code] = p; });
    const wb = XLSX.utils.book_new(), add = (name, ws) => XLSX.utils.book_append_sheet(wb, ws, name);
    add('Plan_Backup', sheet(PLAN_HEADS, plan.map(p => PLAN_KEYS.map(k => p[k]).concat([p.synced, 'ปกติ']))));
    add('Pickup_Log', sheet(PICKUP_HEADS, pickup.map(r => { const t = pmap[r.task_code] || {};
      return [r.ts, t.date, r.task_code, t.company, t.plate, t.driver, r.note, (r.photos || []).length, rowDirs('pickup', r), r.source, r.id]; })));
    add('Road_Log', sheet(ROAD_HEADS, road.map(r => { const t = pmap[r.task_code] || {}, st = +r.stop || 0, nm = t.task_code ? stopNames(t)[st - 1] : '';
      return [r.ts, t.date, r.task_code, ROAD_TH[r.type] || r.type, st || null, nm, r.plate, r.old_plate, r.note, r.eta1, r.eta2, r.eta3, (r.road || []).length, (r.unload || []).length,
        rowDirs('road', r), r.finish ? 'ใช่' : '', r.source, r.id]; })));
    add('Edit_Log', sheet(EDIT_HEADS, edit.map(r => [r.ts, (pmap[r.task_code] || {}).date, r.task_code, r.source, r.field, r.old_value, r.new_value, r.by_user, r.id])));
    add('Delay_Detail', sheet(DELAY_HEADS, delay.map(r => [r.date, r.task_code, r.stop, r.stop_name, r.company, r.plate, r.plan, r.arrive, r.diff_min, r.ontime ? 'ทันเวลา' : 'ช้า', r.source])));
    add('Delay_Daily', sheet(['วันที่'].concat(TREND_TAIL), aggregate(delay, 'day')));
    add('Delay_Monthly', sheet(['เดือน'].concat(TREND_TAIL), aggregate(delay, 'month')));
    add('Backup_Info', Object.assign(XLSX.utils.aoa_to_sheet([['รายการ', 'ค่า']].concat(infoRows.map(r => r.map(xs)))), { '!cols': [{ wch: 38 }, { wch: 60 }] }));
    return wb;
  }
  function saveBlob(blob, name) {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 5000);
  }
  function friendly(e) {
    const m = String((e && e.message) || e);
    if (/timeout|57014|canceling statement/i.test(m) || e.status === 504 || e.status === 546) return 'ข้อมูลมากเกินไปที่จะดึงในครั้งเดียว ลองเลือกช่วงวันที่ให้สั้นลง (เช่น เดือนนี้) หรือดาวน์โหลดไฟล์ Backup รายคืนแทน';
    if (/FORBIDDEN/.test(m) || e.status === 403) return 'บัญชีนี้ไม่มีสิทธิ์ดึงข้อมูล Backup';
    if (/BAD_RANGE/.test(m)) return 'ช่วงวันที่ไม่ถูกต้อง';
    if (/Failed to fetch|NetworkError|Load failed/i.test(m)) return 'เชื่อมต่อระบบไม่ได้ ตรวจอินเทอร์เน็ตแล้วลองใหม่';
    return m;
  }
  async function generate() {
    const btn = $('gen'), from = $('dFrom').value || null, to = $('dTo').value || null;
    if (from && to && to < from) return prog('ช่วงวันที่ไม่ถูกต้อง : “ถึงวันที่” ต้องไม่ก่อน “ตั้งแต่วันที่”', 'err');
    btn.disabled = true; prog('กำลังโหลดไลบรารีสร้างไฟล์ Excel…');
    try {
      await loadXlsx();
      prog('กำลังดึงข้อมูลจากระบบ… (ข้อมูลมากอาจใช้เวลาครู่หนึ่ง)');
      const exp = await Auth.rpc('backup_export', { p_from: from });
      const plan = (exp.plan || []).filter(p => !to || String(p.date) <= to).sort((a, b) => a.date < b.date ? -1 : a.date > b.date ? 1 : a.task_code < b.task_code ? -1 : 1);
      const codes = new Set(plan.map(p => p.task_code));
      const inSet = r => codes.has(r.task_code), byTs = (a, b) => a.ts < b.ts ? -1 : a.ts > b.ts ? 1 : a.id - b.id;
      const pickup = (exp.pickup || []).filter(inSet).sort(byTs), road = (exp.road || []).filter(inSet).sort(byTs), edit = (exp.edit || []).filter(inSet).sort(byTs);
      let delay = [];
      if (plan.length) {
        const d0 = new Date(plan[0].date + 'T00:00:00Z'), d1 = new Date(plan[plan.length - 1].date + 'T00:00:00Z');
        const chunks = []; for (let c = new Date(d0); c <= d1; c = new Date(c.getTime() + 400 * 86400e3)) chunks.push([c.toISOString().slice(0, 10), new Date(Math.min(d1.getTime(), c.getTime() + 399 * 86400e3)).toISOString().slice(0, 10)]);
        for (let i = 0; i < chunks.length; i++) {
          prog(`ได้ข้อมูล ${plan.length.toLocaleString('en-US')} งาน · กำลังดึงข้อมูลความล่าช้า (${i + 1}/${chunks.length})…`);
          delay = delay.concat(await Auth.rpc('delay_detail', { p_from: chunks[i][0], p_to: chunks[i][1] }) || []);
        }
        delay = delay.filter(inSet);
      }
      prog('กำลังสร้างไฟล์ Excel…');
      await new Promise(r => setTimeout(r, 30));                       // ให้ข้อความแสดงก่อนงานหนัก
      const now = bkk(Date.now()), a = Auth.get() || {};
      const stamp = `${now.getUTCFullYear()}${p2(now.getUTCMonth() + 1)}${p2(now.getUTCDate())}_${p2(now.getUTCHours())}${p2(now.getUTCMinutes())}`;
      const info = [['สร้างเมื่อ (เวลาไทย)', `${now.getUTCFullYear()}-${p2(now.getUTCMonth() + 1)}-${p2(now.getUTCDate())} ${p2(now.getUTCHours())}:${p2(now.getUTCMinutes())}:${p2(now.getUTCSeconds())}`],
        ['วิธีสร้าง', 'สร้างสดจากหน้าเว็บ Backup (ข้อมูลปัจจุบันของระบบ)'], ['สร้างโดย', a.name || a.user || ''],
        ['ช่วงวันที่งาน', (from || 'ทั้งหมด') + ' ถึง ' + (to || 'ล่าสุด')], ['จำนวนงาน (Plan_Backup)', plan.length], ['Pickup_Log (แถว)', pickup.length], ['Road_Log (แถว)', road.length],
        ['Edit_Log (แถว)', edit.length], ['Delay_Detail (แถว)', delay.length],
        ['หมายเหตุ', 'ไฟล์นี้ไม่รวมงานที่ถูกลบออกจากระบบแล้ว (ดูได้ในไฟล์ Backup รายคืน) · รูปต้นฉบับเก็บที่เครื่อง Admin ตาม Task Code'], ['หมายเหตุเวลา', 'เวลาทั้งหมดเป็นเวลาไทย (UTC+7) เก็บเป็นข้อความ']];
      const wb = buildWorkbook(plan, pickup, road, edit, delay, info);
      const out = XLSX.write(wb, { bookType: 'xlsx', type: 'array' });
      const name = `Delivery_Backup_${stamp}.xlsx`;
      saveBlob(new Blob([out], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }), name);
      prog(`สร้างไฟล์ ${name} แล้ว (${plan.length.toLocaleString('en-US')} งาน, Road ${road.length.toLocaleString('en-US')} แถว, ${size(out.byteLength)})`, 'ok');
    } catch (e) { prog(friendly(e), 'err'); }
    finally { btn.disabled = false; }
  }

  function setRange(a, b) { $('dFrom').value = a || ''; $('dTo').value = b || ''; DateBox.sync($('dFrom')); DateBox.sync($('dTo')); }
  function preset(k) {
    const t = nowBkkDate();
    if (k === 'month') setRange(t.slice(0, 8) + '01', '');
    else if (k === '30') setRange(bkk(Date.now() - 29 * 86400e3).toISOString().slice(0, 10), '');
    else setRange('', '');
  }

  DateBox.attach($('dFrom')); DateBox.attach($('dTo'));
  document.querySelectorAll('[data-p]').forEach(b => b.onclick = () => preset(b.dataset.p));
  $('gen').onclick = generate;
  preset('month');
  (async () => {
    if (!SB.ON) return say('โหมดตัวอย่าง: ยังไม่ได้ใส่ SUPABASE_URL ใน config.js', 'err');
    if (!Auth.get()) await Auth.login();
    Auth.badge($('userBox'));
    loadStatus(); loadFiles();
    setTimeout(() => loadXlsx().catch(() => { }), 2500);           // โหลดไลบรารีไว้ก่อน ให้ปุ่มสร้างไฟล์เร็วขึ้น
  })();
})();
