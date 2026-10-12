/* หน้าแผนที่ GPS (gps.html) : แผนที่ Leaflet + OpenStreetMap, KPI ของวัน, รายการรถ, Delay Trend รายวัน/รายเดือน
   ข้อมูลทั้งหมดมาจาก RPC gps_board / delay_trend (ต้องเข้าสู่ระบบ) รีเฟรชทุก 60 วินาที */
(function () {
  const $ = id => document.getElementById(id);
  const esc = v => String(v == null ? '' : v).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const REFRESH = 60;
  const ST = { waiting: ['ยังไม่เข้า SCM', '#8e9bb3'], checkin: ['เข้า SCM แล้ว รอออก', '#4aa8ff'], moving: ['กำลังเดินทาง', '#38bdf8'], site: ['ถึงหน้างาน', '#f6b93b'], done: ['จบงาน', '#34d08c'] };
  const WC = { late: '#ff4d61', risk: '#f6b93b', ok: '#34d08c' };
  const ETA_TH = { ok: 'ทันเวลา', risk: 'เสี่ยงสาย', late: 'คาดว่าจะสาย' };
  const TZ = 'Asia/Bangkok';
  const hhmm = iso => { if (!iso) return '-'; const d = new Date(iso); return isNaN(d) ? String(iso) : d.toLocaleTimeString('th-TH', { timeZone: TZ, hour: '2-digit', minute: '2-digit', hour12: false }); };
  const dhm = iso => { if (!iso) return '-'; const d = new Date(iso); return isNaN(d) ? '-' : d.toLocaleString('th-TH', { timeZone: TZ, day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false }); };
  const today = () => new Date(Date.now() + 7 * 36e5).toISOString().slice(0, 10);
  const addDays = (s, n) => { const d = new Date(s + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
  const tag = (st, txt) => st ? `<span class="tag ${st}">${esc(txt || ETA_TH[st])}</span>` : '';
  const say = t => { $('msg').textContent = t || ''; };

  let map = null, layer = null, board = null, fitted = false, left = REFRESH, busy = false, group = 'day', showNames = true;
  // สีประจำรถ/งาน (แยกชุดรถ + จุดส่ง + เส้นทาง) วันหนึ่งไม่เกิน 15 คัน
  const PAL = ['#e6194B', '#3cb44b', '#4363d8', '#f58231', '#911eb4', '#0aa5c0', '#f032e6', '#9A6324', '#469990', '#000075', '#808000', '#800000', '#2f4f4f', '#c2185b', '#5d8aa8'];
  let colorOf = {};
  function assignColors() {
    colorOf = {};
    const codes = board.vehicles.map(v => v.task_code).sort();
    codes.forEach((c, i) => { colorOf[c] = PAL[i % PAL.length]; });
  }
  const jobColor = v => colorOf[v.task_code] || '#64748b';

  // ค้นหา : ทะเบียนรถ / Task Code / Client Name / ชื่อจุดส่ง  (หลายคำคั่นด้วย , = ตรงคำใดคำหนึ่ง ; ไม่สนช่องว่างและตัวพิมพ์เล็ก-ใหญ่)
  const norm = s => String(s == null ? '' : s).toLowerCase().replace(/\s+/g, '');
  let qTerms = [];
  const matchQ = t => !qTerms.length || [t.task_code, t.plate, t.client].concat((t.stops || []).map(s => s.name)).map(norm).some(h => qTerms.some(q => h.includes(q)));
  function bindSearch(redraw) {
    let tm = null;
    const run = () => { qTerms = $('q').value.split(/[,，]/).map(norm).filter(Boolean); $('qx').hidden = !$('q').value; redraw(); };
    $('q').addEventListener('input', () => { clearTimeout(tm); tm = setTimeout(run, 200); });
    $('q').addEventListener('keydown', e => { if (e.key === 'Escape') { $('q').value = ''; run(); } });
    $('qx').onclick = () => { $('q').value = ''; run(); $('q').focus(); };
  }
  const shortName = (n, m) => { n = String(n || '').trim(); return n.length > m ? n.slice(0, m - 1) + '…' : n; };

  /* ---------- แผนที่ ---------- */
  // focus = Task Code ที่กดเลือก (แสดงบนแผนที่เฉพาะงานนั้น) ; null = แสดงทุกงาน
  let focus = null, GRACE = 0;
  function initMap() {
    if (typeof L === 'undefined') { say('โหลดแผนที่ไม่สำเร็จ (ตรวจอินเทอร์เน็ต) ยังดูรายการรถและตารางได้'); return; }
    map = L.map('map', { zoomControl: true }).setView([13.75, 100.55], 9);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '&copy; OpenStreetMap' }).addTo(map);
    layer = L.layerGroup().addTo(map);
    $('legend').innerHTML = '<div class="lx"><b>สีตามรถแต่ละคัน</b> (กดการ์ดด้านขวา = ดูเฉพาะคันนั้น)</div><div class="lx">■ SCM &nbsp; ● จุดส่ง (เลขลำดับ) &nbsp; 🚚 รถ</div>'
      + '<div class="lx">━ เส้นที่วิ่งมาจริง &nbsp; - - - แผน (เส้นตรง)</div>'
      + '<div class="lx">✓ = ลงงานแล้ว &nbsp; <i style="background:#fff;border:3px solid #ff4d61"></i>ขอบแดง = คาดว่าจะสาย</div>'
      + '<label style="display:block;cursor:pointer"><input type="checkbox" id="nameTog" checked> แสดงชื่อจุดส่ง</label>';
    $('nameTog').onchange = e => { showNames = e.target.checked; draw(false); };
  }
  const vColor = v => v.state === 'moving' ? (WC[v.worst] || ST.moving[1]) : (ST[v.state] || ST.waiting)[1];
  const pinIcon = (txt, color, size, sq, extra) => L.divIcon({ className: '', iconSize: [size, size], iconAnchor: [size / 2, size / 2],
    html: `<div class="pin${sq ? ' sq' : ''} ${extra || ''}" style="width:${size}px;height:${size}px;background:${color}">${esc(txt)}</div>` });

  function draw(fit) {
    if (!map || !board) return;
    layer.clearLayers();
    const pts = [], o = board.origin;
    if (o) {
      L.marker([o.lat, o.lng], { icon: pinIcon('SCM', '#4aa8ff', 34, true), zIndexOffset: 500 }).addTo(layer).bindTooltip('SCM (ต้นทาง)');
      L.circle([o.lat, o.lng], { radius: o.radius || 300, color: '#4aa8ff', weight: 1, fillOpacity: .06 }).addTo(layer);
      if (!focus) pts.push([o.lat, o.lng]);
    }
    board.vehicles.forEach(v => {
      if ((focus && focus !== v.task_code) || !matchQ(v)) return;                     // ดูเฉพาะคันที่เลือก
      const col = jobColor(v), dim = v.state === 'done';
      // แผน : เส้นตรงประ SCM → จุด 1 → จุด 2 ... (ไป-กลับ = เส้นจุดกลับ SCM)
      let prev = o ? [o.lat, o.lng] : null, last = null;
      (v.stops || []).forEach(s => {
        if (s.lat == null || s.lng == null) { prev = null; return; }
        const p = [s.lat, s.lng];
        if (prev) L.polyline([prev, p], { color: col, weight: 2.5, opacity: dim ? .25 : .55, dashArray: '8 7' }).addTo(layer);
        prev = last = p;
      });
      if (v.round_trip && last && o) L.polyline([last, [o.lat, o.lng]], { color: col, weight: 2, opacity: .45, dashArray: '2 8' }).addTo(layer);
      // เส้นทางที่วิ่งมาจริง (GPS)
      if (v.trail && v.trail.length > 1) { L.polyline(v.trail, { color: col, weight: 4, opacity: dim ? .35 : .85 }).addTo(layer); if (focus) v.trail.forEach(t => pts.push(t)); }
      (v.stops || []).forEach(s => {
        if (s.lat == null || s.lng == null) return;
        const late = !s.arrive && s.status === 'late';
        const m = L.marker([s.lat, s.lng], { icon: pinIcon(s.done ? '✓' : s.i, col, 24, false, late ? 'late' : ''), zIndexOffset: 200, opacity: s.done || dim ? .6 : 1 }).addTo(layer);
        m.on('click', e => { L.DomEvent.stopPropagation(e); pick(v.task_code, true); });
        if (showNames) m.bindTooltip(`<span style="border-left:4px solid ${col};padding-left:4px">${s.i}. ${esc(shortName(s.name, 22))}${s.plan ? ' · ' + hhmm(s.plan) : ''}</span>`, { permanent: true, direction: 'right', offset: [12, 0], className: 'slab' });
        else m.bindTooltip(`<b style="color:${col}">${esc(v.plate || '')} · ${esc(v.task_code)}</b><br>จุดที่ ${s.i} ${esc(s.name)}`);
        pts.push([s.lat, s.lng]);
      });
      if (v.pos && v.pos.lat != null) {
        const lbl = `${esc(v.plate || '-')} · ${esc(v.task_code)}${v.worst === 'late' ? ' ⚠' : ''}`;
        const ic = L.divIcon({ className: '', iconSize: [22, 22], iconAnchor: [11, 11],
          html: `<div style="position:relative"><div class="veh" style="background:${col}">🚚</div><span class="vlab" style="position:absolute;left:12px;bottom:16px;transform:translateX(-50%);background:${col}">${lbl}</span></div>` });
        const m = L.marker([v.pos.lat, v.pos.lng], { icon: ic, zIndexOffset: 1000, opacity: dim ? .7 : 1 }).addTo(layer);
        m.on('click', e => { L.DomEvent.stopPropagation(e); pick(v.task_code, true); });
        pts.push([v.pos.lat, v.pos.lng]);
      }
      if (focus && o) pts.push([o.lat, o.lng]);
    });
    if ((fit || (!fitted && fit !== false)) && pts.length) { map.fitBounds(pts, { paddingTopLeft: [40, 60], paddingBottomRight: [40, 40], maxZoom: 14 }); fitted = true; }
  }

  /* ---------- เลือกงาน ---------- */
  // กดการ์ด/หมุด : แสดงเฉพาะงานนั้นบนแผนที่ ; กดซ้ำ = กลับไปแสดงทุกงาน
  function pick(code, fromMap) {
    focus = fromMap ? code : (focus === code ? null : code);
    renderList(); draw(true);
    const el = focus && $('vlist').querySelector(`.tk[data-c="${CSS.escape(focus)}"]`);
    if (el) el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }
  const durTh = m => m >= 60 ? `${Math.floor(m / 60)} ชม.${m % 60 ? ' ' + (m % 60) + ' นาที' : ''}` : `${m} นาที`;
  // ผลการถึงจุด (เทียบเวลาถึงจริงกับเวลานัด แบบเดียวกับ Delay Trend)
  function arrTag(s) {
    if (!s.arrive || !s.plan) return '';
    const dm = Math.round((new Date(s.arrive) - new Date(s.plan)) / 60000);
    return dm <= GRACE ? '<span class="tag ok">✓ ถึงทันเวลา</span>' : `<span class="tag late2">สายไป ${durTh(dm)}</span>`;
  }
  function stopItem(s) {
    let r;
    if (s.done || s.arrive) {
      r = `<span class="ok">ถึง ${hhmm(s.arrive || s.done)}</span>${s.done ? ` · ลงเสร็จ ${hhmm(s.done)}` : ' · <b>กำลังลงงาน</b>'} ${arrTag(s)}`;
    } else {
      const a = s.eta_gps ? `<span class="ev">📡 GPS คาดถึง <b>${hhmm(s.eta_gps)}</b> ${tag(s.status_gps)}</span>` : '';
      const b = s.eta_human ? `<span class="ev">👤 คนขับแจ้ง <b>${esc(s.eta_human)}</b> ${tag(s.status_human)}</span>` : '';
      r = a || b ? a + b : '<span class="muted">ยังไม่มีเวลาคาดว่าจะถึง</span>';
    }
    return `<li><span class="n${s.done ? ' dn' : ''}">${s.done ? '✓' : s.i}</span><span>${esc(s.name)}</span><span class="t">${s.plan ? 'นัด ' + hhmm(s.plan) : '<span class="muted">ไม่มีเวลานัด</span>'}</span>
      <span class="lg">${r}</span>${s.lat == null ? '<span class="warn">⚠ ยังไม่มีพิกัด (เติมที่หน้า ETA / GPS)</span>' : ''}</li>`;
  }
  function card(v) {
    const [sn, sc] = ST[v.state] || ST.waiting, p = v.pos, col = jobColor(v);
    const steps = [v.checkin ? `เข้า SCM ${hhmm(v.checkin)}` : '', v.depart ? `ออก ${hhmm(v.depart)}` : '', v.returned ? `กลับถึง SCM ${hhmm(v.returned)}` : ''].filter(Boolean).join(' · ');
    const gps = p ? `📍 GPS ${hhmm(p.time)} (${p.age_min} นาทีก่อน)${p.speed != null ? ' · ' + Math.round(p.speed) + ' กม./ชม.' : ''}${p.source ? ' · ' + esc(p.source) : ''}` : '<span class="muted">📍 ไม่มีข้อมูล GPS</span>';
    return `<div class="tk${focus === v.task_code ? ' foc' : ''}" tabindex="0" data-c="${esc(v.task_code)}" style="--c:${col}">
      <div class="hd"><i class="sw" style="background:${col}"></i><b class="tcode">${esc(v.task_code)}</b><span class="cli">${v.client ? esc(v.client) : '<span class="na2">Client ยังไม่ระบุ</span>'}</span>${tag(v.worst)}</div>
      <div class="hd2"><span>ทะเบียน <b>${v.plate ? esc(v.plate) : '<span class="na2">ยังไม่ระบุ</span>'}</b></span><span>ประเภทรถ <b>${v.vehicle_type ? esc(v.vehicle_type) : '<span class="na2">ยังไม่ระบุ</span>'}</b></span></div>
      <div class="sub"><span style="color:${sc};font-weight:700">● ${sn}</span> · นัดเข้า SCM ${esc(v.schedule || '-')} · ${esc(v.company || '-')}${v.round_trip ? ' · ไป-กลับ' : ''}${v.date !== board.date ? ' · งานข้ามวัน ' + esc(v.date) : ''}</div>
      ${focus === v.task_code ? `<div class="sub">${v.driver ? 'คนขับ ' + esc(v.driver) : ''}${v.phone ? ' ' + esc(v.phone) : ''}${v.detail ? '<br>' + esc(v.detail) : ''}</div>` : ''}
      ${steps ? `<div class="sub">${steps}</div>` : ''}<div class="sub">${gps}</div>
      <ol>${(v.stops || []).map(stopItem).join('')}</ol>
      ${v.reason && !(v.stops || []).some(s => s.eta_gps) && v.state !== 'done' ? `<div class="sub">ETA: ${esc(v.reason)}</div>` : ''}</div>`;
  }
  function renderList() {
    const b = board;
    const rank = { moving: 0, site: 1, checkin: 2, waiting: 3, done: 4 };
    const vs = b.vehicles.filter(matchQ).sort((x, y) => (rank[x.state] - rank[y.state]) || String(x.schedule).localeCompare(String(y.schedule)));
    $('sideTitle').textContent = focus ? `ดูเฉพาะ ${focus}` : qTerms.length ? `พบ ${vs.length} จาก ${b.vehicles.length} คัน` : `รถทั้งหมด (${vs.length})`;
    $('allOn').hidden = !focus;
    $('vlist').innerHTML = vs.length ? vs.map(card).join('') : `<div class="empty">${b.vehicles.length ? 'ไม่พบงานที่ตรงกับคำค้นหา' : 'ไม่มีงานในวันนี้'}</div>`;
    $('vlist').querySelectorAll('.tk').forEach(el => {
      el.onclick = () => pick(el.dataset.c, false);
      el.onkeydown = e => { if (e.key === 'Enter') pick(el.dataset.c, false); };
    });
  }

  /* ---------- KPI / ตาราง ---------- */
  function renderAll() {
    const b = board, k = b.kpi;
    assignColors();
    if (focus && !b.vehicles.some(v => v.task_code === focus)) focus = null;
    $('kpi').innerHTML = [['งานทั้งหมด', k.total, '#4aa8ff'], ['ยังไม่ออก', k.waiting, '#8e9bb3'], ['กำลังเดินทาง', k.moving, '#38bdf8'], ['ถึงหน้างาน', k.site, '#f6b93b'], ['จบงาน', k.done, '#34d08c'],
      ['ทันเวลา', k.ontime, '#34d08c'], ['เสี่ยงสาย', k.risk, '#f6b93b'], ['คาดว่าสาย', k.late, '#ff4d61']]
      .map(([n, v, c]) => `<div style="--c:${c}"><b>${v}</b><span>${n}</span></div>`).join('');
    const bot = b.bot || {};
    const botTxt = bot.alert ? `<b style="color:#ff8a98">⚠ ${esc(bot.alert_reason || 'บอตผิดปกติ')}</b>` : bot.go ? '<b style="color:#34d08c">บอตทำงานปกติ</b>' : '<b>บอตพัก (ไม่มีงานต้องติดตาม)</b>';
    $('info').innerHTML = `<span>ซิงก์ GPS ล่าสุด <b>${b.last_sync ? dhm(b.last_sync) : '-'}</b>${b.sync_age_min != null ? ` (${Math.round(b.sync_age_min)} นาทีก่อน)` : ''}</span>
      <span>ดึงรอบถัดไป <b>${b.next_import ? hhmm(b.next_import) : '-'}</b></span><span>${botTxt}</span><span id="cd"></span>`;
    $('ban').innerHTML = bot.alert ? `<div class="ban bad">⚠ ${esc(bot.alert_reason || 'ข้อมูล GPS ไม่อัปเดต')}</div>` : '';
    renderList();
    $('gBody').innerHTML = (b.gps || []).length ? b.gps.map(g => `<tr><td>${g.task_code && colorOf[g.task_code] ? `<i class="sw" style="background:${colorOf[g.task_code]}"></i>` : ''}${esc(g.plate)}</td><td>${esc(g.source || '-')}</td><td>${esc(g.task_code || '-')}</td><td>${esc(g.status || '-')}</td><td class="num">${g.speed != null ? Math.round(g.speed) : '-'}</td>
      <td>${Number(g.lat).toFixed(5)}, ${Number(g.lng).toFixed(5)}</td><td>${dhm(g.time)}</td><td class="num">${g.age_min}</td></tr>`).join('') : '<tr><td colspan="8" class="empty">ยังไม่มีข้อมูล GPS</td></tr>';
    draw();
  }
  async function loadGrace() {
    try { const c = await Auth.config(); const g = parseFloat(c.delay_grace_min); if (!isNaN(g)) GRACE = g; } catch (e) { /* ใช้ 0 */ }
  }

  /* ---------- Delay Trend ---------- */
  // กราฟแท่ง % ทันเวลา : ทุกวัน/เดือนในช่วง (ไม่มีข้อมูล = ขีด) แกนตั้ง 0-100% เส้นประเป้าหมาย 90%
  const TH_MON = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  function trendChart(rows, from, to) {
    const by = {}; rows.forEach(r => { by[r.period] = r; });
    const slots = [];
    if (group === 'month') { let y = +from.slice(0, 4), m = +from.slice(5, 7); for (let i = 0; i < 12; i++) { slots.push(`${y}-${String(m).padStart(2, '0')}`); if (++m > 12) { m = 1; y++; } } }
    else for (let x = from; x <= to; x = addDays(x, 1)) slots.push(x);
    const cur = group === 'month' ? to.slice(0, 7) : to;
    const lab = p => group === 'month' ? `${TH_MON[+p.slice(5, 7) - 1]}<small>${String(+p.slice(0, 4) + 543).slice(2)}</small>` : `${+p.slice(8, 10)}/${+p.slice(5, 7)}`;
    const y = v => 20 + 150 - v * 1.5;
    const grid = `<div class="grid">${[100, 50, 0].map(v => `<div style="top:${150 - v * 1.5}px"></div>`).join('')}<div class="tg" style="top:${150 - 90 * 1.5}px"></div></div>`
      + `<div class="ax">${[100, 50, 0].map(v => `<span style="top:${y(v)}px">${v}%</span>`).join('')}<span class="tg" style="top:${y(90)}px">90%</span></div>`;
    // รายวัน : กดแล้วเปิด Dashboard ของวันนั้น / รายเดือน : กดแล้วดูรายวันของเดือนนั้น
    const close = group === 'month' ? '</div>' : '</a>';
    const open = (p, tip) => {
      const c = `col${p === cur ? ' cur' : ''}`;
      if (group === 'month') return `<div class="${c} go" data-mon="${p}" role="button" tabindex="0" title="${esc((tip ? tip + '\n' : '') + 'กดเพื่อดูรายวันของเดือนนี้')}">`;
      return `<a class="${c}" href="${dashUrl(p)}" title="${esc((tip ? tip + '\n' : p + ' : ไม่มีข้อมูลเวลาถึง\n') + 'กดเพื่อเปิด Dashboard วันนี้')}">`;
    };
    return grid + slots.map(p => {
      const r = by[p];
      if (!r) return open(p, '') + `<div class="pa"><span class="none">–</span></div><div class="xl">${lab(p)}<small>&nbsp;</small></div>` + close;
      const pc = Number(r.ontime_pct), cls = pc >= 90 ? '' : pc >= 70 ? 'mid' : 'low', col = pc >= 90 ? '#34d08c' : pc >= 70 ? '#f6b93b' : '#ff6b7c';
      return open(p, `${p} : ทันเวลา ${pc}% (${r.ontime}/${r.n} จุด)${r.avg_late != null ? ' · สายเฉลี่ย ' + r.avg_late + ' นาที' : ''}`)
        + `<div class="pa"><span class="v" style="color:${col}">${Math.round(pc)}%</span><i class="bar ${cls}" style="height:${Math.max(1, pc) * 1.5}px"></i></div>
        <div class="xl">${lab(p)}<small>${r.n} จุด</small></div>` + close;
    }).join('');
  }

  const dashUrl = d => 'dashboard.html?date=' + encodeURIComponent(d);
  let trendEnd = '';                       // วันสุดท้ายของกราฟรายวัน (ตั้งเมื่อกดเดือนในกราฟรายเดือน) ; ว่าง = ตามวันที่ที่เลือก
  function drillMonth(m) {                 // m = 'YYYY-MM' : แสดงรายวันของเดือนนั้น (30 วันจนถึงสิ้นเดือน หรือวันนี้)
    const [y, mo] = m.split('-').map(Number);
    const end = new Date(Date.UTC(y, mo, 0)).toISOString().slice(0, 10);
    const sel = $('date').value || today();
    trendEnd = end < sel ? end : sel; group = 'day'; loadTrend();
  }
  async function loadTrend() {
    const d = (group === 'day' && trendEnd) || $('date').value || today();
    let from = addDays(d, -29);
    if (group === 'month') {               // 12 เดือนล่าสุด รวมเดือนปัจจุบัน
      let y = +d.slice(0, 4), m = +d.slice(5, 7) - 11;
      if (m < 1) { m += 12; y--; }
      from = `${y}-${String(m).padStart(2, '0')}-01`;
    }
    $('dtDay').classList.toggle('on', group === 'day'); $('dtMon').classList.toggle('on', group === 'month');
    try {
      const rows = await Auth.rpc('delay_trend', { p_from: from, p_to: d, p_group: group }) || [];
      const tot = rows.reduce((a, r) => (a.n += r.n, a.ok += r.ontime, a), { n: 0, ok: 0 });
      $('dtNote').textContent = tot.n ? `รวม ${tot.n} จุด ทันเวลา ${Math.round(1000 * tot.ok / tot.n) / 10}%` : '';
      $('dtChart').innerHTML = trendChart(rows, from, d);
      const w = $('dtChart').parentNode; w.scrollLeft = w.scrollWidth;      // จอเล็ก : เลื่อนไปช่วงล่าสุด
      $('dtHint').textContent = group === 'month' ? 'กดเดือนในกราฟหรือตาราง = ดูรายวันของเดือนนั้น' : 'กดวันที่ในกราฟหรือตาราง = เปิด Dashboard ของวันนั้น';
      $('dtBody').innerHTML = rows.length ? rows.slice().reverse().map(r => `<tr class="go" tabindex="0" ${group === 'month' ? `data-mon="${esc(r.period)}"` : `data-day="${esc(r.period)}"`}>
        <td>${group === 'month' ? `<a class="dl" href="#" data-mon="${esc(r.period)}">${esc(r.period)}</a>` : `<a class="dl" href="${dashUrl(r.period)}">${esc(r.period)}</a>`}</td><td class="num">${r.n}</td><td class="num">${r.ontime}</td><td class="num">${r.late}</td>
        <td class="num"><b style="color:${r.ontime_pct >= 90 ? '#34d08c' : r.ontime_pct >= 70 ? '#f6b93b' : '#ff6b7c'}">${r.ontime_pct}%</b></td><td class="num">${r.avg_late == null ? '-' : r.avg_late}</td><td class="num">${r.max_late == null ? '-' : r.max_late}</td><td class="num">${r.gps}</td></tr>`).join('')
        : '<tr><td colspan="8" class="empty">ยังไม่มีข้อมูลเวลาถึง</td></tr>';
    } catch (e) { $('dtBody').innerHTML = `<tr><td colspan="8" class="empty">โหลด Delay Trend ไม่สำเร็จ: ${esc(e.message || e)}</td></tr>`; }
  }

  /* ---------- โหลดข้อมูล ---------- */
  async function load(manual) {
    if (busy) return; busy = true;
    try {
      const d = $('date').value || today();
      const nb = await Auth.rpc('gps_board', { p_date: d });
      if (($('date').value || today()) !== d) return;
      board = nb; say(''); renderAll();
    } catch (e) { say(/FORBIDDEN/.test(e.message || '') ? 'ไม่มีสิทธิ์ดูหน้านี้' : 'โหลดข้อมูลไม่สำเร็จ: ' + (e.message || e) + (/gps_board/.test(e.message || '') ? ' (ยังไม่ได้รัน SQL รุ่นล่าสุด)' : '')); }
    finally { busy = false; left = REFRESH; }
  }
  function tick() {
    if (document.hidden) return;
    left--; const cd = $('cd'); if (cd) cd.textContent = `รีเฟรชอีก ${left} วินาที`;
    if (left <= 0) { load(); if ((($('date').value || today()) === today())) loadTrend(); }
  }
  function changeDate() { trendEnd = ''; fitted = false; focus = null; board = null; load(true); loadTrend(); }

  $('date').value = today();
  if (window.DateBox) DateBox.attach($('date'));
  $('date').onchange = changeDate;
  $('today').onclick = () => { $('date').value = today(); if (window.DateBox && DateBox.sync) DateBox.sync($('date')); changeDate(); };
  $('dtDay').onclick = () => { group = 'day'; trendEnd = ''; loadTrend(); };
  // คลิกแถวตาราง / แท่งเดือน
  const trendGo = e => {
    const m = e.target.closest('[data-mon]'), d = e.target.closest('tr[data-day]');
    if (m) { e.preventDefault(); drillMonth(m.dataset.mon); }
    else if (d && !e.target.closest('a')) location.href = dashUrl(d.dataset.day);
  };
  ['dtChart', 'dtBody'].forEach(id => {
    $(id).addEventListener('click', trendGo);
    $(id).addEventListener('keydown', e => { if (e.key === 'Enter' && !e.target.closest('a')) trendGo(e); });
  });
  $('dtMon').onclick = () => { group = 'month'; loadTrend(); };
  window.addEventListener('keydown', e => { if (e.key === 'Escape' && focus) pick(focus, false); });
  $('allOn').onclick = () => { focus = null; renderList(); draw(true); };
  bindSearch(() => { if (!board) return; if (focus && !board.vehicles.some(v => v.task_code === focus && matchQ(v))) focus = null; renderList(); draw(true); });
  (async () => {
    initMap();
    if (!SB.ON) return say('โหมดตัวอย่าง: ยังไม่ได้ใส่ SUPABASE_URL ใน config.js');
    if (!Auth.get()) await Auth.login();
    Auth.badge($('userBox'));
    await loadGrace();
    load(); loadTrend();
    setInterval(tick, 1000);
    document.addEventListener('visibilitychange', () => { if (!document.hidden && left < REFRESH - 5) load(); });
  })();
})();
