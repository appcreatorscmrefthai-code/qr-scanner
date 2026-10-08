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

  let map = null, layer = null, board = null, sel = null, fitted = false, left = REFRESH, busy = false, group = 'day';
  const markers = {};

  /* ---------- แผนที่ ---------- */
  function initMap() {
    if (typeof L === 'undefined') { say('โหลดแผนที่ไม่สำเร็จ (ตรวจอินเทอร์เน็ต) ยังดูรายการรถและตารางได้'); return; }
    map = L.map('map', { zoomControl: true }).setView([13.75, 100.55], 9);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '&copy; OpenStreetMap' }).addTo(map);
    layer = L.layerGroup().addTo(map);
    map.on('click', () => closeDet());
    $('legend').innerHTML = Object.values(ST).map(([n, c]) => `<div><i style="background:${c}"></i>${n}</div>`).join('') +
      '<div><i style="background:#34d08c"></i>ทันเวลา <i style="background:#f6b93b"></i>เสี่ยงสาย <i style="background:#ff4d61"></i>สาย</div><div>■ SCM &nbsp; ● จุดส่ง &nbsp; 🚚 รถ</div>';
  }
  const vColor = v => v.state === 'moving' ? (WC[v.worst] || ST.moving[1]) : (ST[v.state] || ST.waiting)[1];
  const pinIcon = (txt, color, size, sq) => L.divIcon({ className: '', iconSize: [size, size], iconAnchor: [size / 2, size / 2],
    html: `<div class="pin${sq ? ' sq' : ''}" style="width:${size}px;height:${size}px;background:${color}">${esc(txt)}</div>` });

  function draw() {
    if (!map || !board) return;
    layer.clearLayers();
    const pts = [];
    if (board.origin) {
      const o = board.origin;
      L.marker([o.lat, o.lng], { icon: pinIcon('SCM', '#4aa8ff', 34, true), zIndexOffset: 500 }).addTo(layer).bindTooltip('SCM (ต้นทาง)');
      L.circle([o.lat, o.lng], { radius: o.radius || 300, color: '#4aa8ff', weight: 1, fillOpacity: .06 }).addTo(layer);
      pts.push([o.lat, o.lng]);
    }
    board.vehicles.forEach(v => {
      const col = vColor(v);
      (v.stops || []).forEach(s => {
        if (s.lat == null || s.lng == null) return;                 // จุดที่ยังไม่มีพิกัด ไม่แสดงหมุด
        const c = s.done ? '#34d08c' : s.arrive ? '#f6b93b' : (WC[s.status] || '#8e9bb3');
        const m = L.marker([s.lat, s.lng], { icon: pinIcon(s.i, c, 24), zIndexOffset: 200, opacity: s.done ? .6 : 1 }).addTo(layer);
        m.on('click', e => { L.DomEvent.stopPropagation(e); pick(v.task_code, false); });
        m.bindTooltip(`${esc(v.plate || v.task_code)} · จุดที่ ${s.i} ${esc(s.name)}`);
        pts.push([s.lat, s.lng]);
      });
      if (v.trail && v.trail.length > 1) L.polyline(v.trail, { color: col, weight: 3, opacity: .7 }).addTo(layer);
      if (v.pos && v.pos.lat != null) {
        const ic = L.divIcon({ className: '', iconSize: [20, 20], iconAnchor: [10, 10],
          html: `<div style="position:relative"><div class="veh" style="color:${col}">🚚</div><span class="vlab" style="position:absolute;left:20px;top:0;border-color:${col}">${esc(v.plate || v.task_code)}</span></div>` });
        const m = L.marker([v.pos.lat, v.pos.lng], { icon: ic, zIndexOffset: 1000 }).addTo(layer);
        m.on('click', e => { L.DomEvent.stopPropagation(e); pick(v.task_code, false); });
        markers[v.task_code] = m;
        pts.push([v.pos.lat, v.pos.lng]);
      }
    });
    if (!fitted && pts.length) { map.fitBounds(pts, { padding: [40, 40], maxZoom: 14 }); fitted = true; }
  }

  /* ---------- รายละเอียด ---------- */
  function closeDet() { sel = null; $('det').hidden = true; }
  function pick(code, pan) {
    sel = code; showDet();
    const v = board && board.vehicles.find(x => x.task_code === code);
    if (pan && map && v && v.pos && v.pos.lat != null) map.setView([v.pos.lat, v.pos.lng], Math.max(map.getZoom(), 13));
  }
  function stopLine(s) {
    let r;
    if (s.done) r = `ลงเสร็จ ${hhmm(s.done)} ${tag('ok', 'จบแล้ว')}`;
    else if (s.arrive) { const late = s.plan && new Date(s.arrive) > new Date(s.plan); r = `ถึง ${hhmm(s.arrive)} ${tag(late ? 'late' : 'ok', late ? 'ถึงช้ากว่านัด' : 'ถึงทัน')}`; }
    else {
      const a = s.eta_gps ? `📡 ${hhmm(s.eta_gps)} ${tag(s.status_gps)}` : '';
      const b = s.eta_human ? `👤 ${esc(s.eta_human)} ${tag(s.status_human)}` : '';
      r = a || b ? `${a} ${b}` : '<span class="muted">ยังไม่มี ETA</span>';
    }
    return `<div class="ln"><span>${s.i}. ${esc(s.name)}<br><span class="muted small">นัด ${hhmm(s.plan)}${s.lat == null ? ' · ยังไม่มีพิกัด' : ''}</span></span><span style="text-align:right">${r}</span></div>`;
  }
  function showDet() {
    const v = board && sel && board.vehicles.find(x => x.task_code === sel);
    if (!v) return closeDet();
    const p = v.pos, [sn, sc] = ST[v.state] || ST.waiting;
    $('det').innerHTML = `<button class="x" type="button" id="detX" aria-label="ปิด">×</button>
      <h3>${esc(v.plate || '(ไม่มีทะเบียน)')} <span class="tag" style="color:${sc}">${sn}</span>${tag(v.worst)}</h3>
      <div class="muted small">${esc(v.task_code)} · ${esc(v.company || '')}${v.round_trip ? ' · ไป-กลับ' : ''}${v.driver ? ' · ' + esc(v.driver) : ''}</div>
      <div class="ln"><span>นัดออก</span><span>${esc(v.schedule || '-')}</span></div>
      <div class="ln"><span>รถออกจาก SCM</span><span>${v.depart ? hhmm(v.depart) + ' น.' : '-'}</span></div>
      <div class="ln"><span>ตำแหน่งล่าสุด</span><span>${p ? `${p.speed != null ? Math.round(p.speed) + ' กม./ชม. · ' : ''}${hhmm(p.time)} น. (${p.age_min} นาทีก่อน)` : '<span class="muted">ไม่มีข้อมูล GPS</span>'}</span></div>
      ${v.reason ? `<div class="ln"><span>ETA</span><span class="muted">${esc(v.reason)}</span></div>` : ''}
      ${(v.stops || []).map(stopLine).join('')}`;
    $('det').hidden = false;
    $('detX').onclick = closeDet;
  }

  /* ---------- รายการรถ / KPI / ตาราง ---------- */
  function renderAll() {
    const b = board, k = b.kpi;
    $('kpi').innerHTML = [['งานทั้งหมด', k.total, '#4aa8ff'], ['ยังไม่ออก', k.waiting, '#8e9bb3'], ['กำลังเดินทาง', k.moving, '#38bdf8'], ['ถึงหน้างาน', k.site, '#f6b93b'], ['จบงาน', k.done, '#34d08c'],
      ['ทันเวลา', k.ontime, '#34d08c'], ['เสี่ยงสาย', k.risk, '#f6b93b'], ['คาดว่าสาย', k.late, '#ff4d61']]
      .map(([n, v, c]) => `<div style="--c:${c}"><b>${v}</b><span>${n}</span></div>`).join('');
    const bot = b.bot || {};
    const botTxt = bot.alert ? `<b style="color:#ff8a98">⚠ ${esc(bot.alert_reason || 'บอตผิดปกติ')}</b>` : bot.go ? '<b style="color:#34d08c">บอตทำงานปกติ</b>' : '<b>บอตพัก (ไม่มีงานต้องติดตาม)</b>';
    $('info').innerHTML = `<span>ซิงก์ GPS ล่าสุด <b>${b.last_sync ? dhm(b.last_sync) : '-'}</b>${b.sync_age_min != null ? ` (${Math.round(b.sync_age_min)} นาทีก่อน)` : ''}</span>
      <span>ดึงรอบถัดไป <b>${b.next_import ? hhmm(b.next_import) : '-'}</b></span><span>${botTxt}</span><span id="cd"></span>`;
    $('ban').innerHTML = bot.alert ? `<div class="ban bad">⚠ ${esc(bot.alert_reason || 'ข้อมูล GPS ไม่อัปเดต')}</div>` : '';
    const rank = { moving: 0, site: 1, checkin: 2, waiting: 3, done: 4 };
    const vs = b.vehicles.slice().sort((x, y) => (rank[x.state] - rank[y.state]) || String(x.schedule).localeCompare(String(y.schedule)));
    $('vlist').innerHTML = vs.length ? vs.map(v => {
      const [sn] = ST[v.state] || ST.waiting;
      return `<button class="vi" type="button" data-c="${esc(v.task_code)}" style="--c:${vColor(v)}"><b>${esc(v.plate || v.task_code)}</b> ${tag(v.worst)}<small>${sn} · ${esc(v.schedule || '')} · ${esc(v.company || '')}</small><small>${esc(v.task_code)}${v.date !== b.date ? ' · งานข้ามวัน ' + esc(v.date) : ''}${v.pos ? '' : ' · ไม่มี GPS'}</small></button>`;
    }).join('') : '<div class="empty">ไม่มีงานในวันนี้</div>';
    $('vlist').querySelectorAll('.vi').forEach(el => el.onclick = () => pick(el.dataset.c, true));
    $('gBody').innerHTML = (b.gps || []).length ? b.gps.map(g => `<tr><td>${esc(g.plate)}</td><td>${esc(g.task_code || '-')}</td><td>${esc(g.status || '-')}</td><td class="num">${g.speed != null ? Math.round(g.speed) : '-'}</td>
      <td>${Number(g.lat).toFixed(5)}, ${Number(g.lng).toFixed(5)}</td><td>${dhm(g.time)}</td><td class="num">${g.age_min}</td></tr>`).join('') : '<tr><td colspan="7" class="empty">ยังไม่มีข้อมูล GPS</td></tr>';
    draw(); if (sel) showDet();
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
    return grid + slots.map(p => {
      const r = by[p];
      if (!r) return `<div class="col${p === cur ? ' cur' : ''}"><div class="pa"><span class="none">–</span></div><div class="xl">${lab(p)}<small>&nbsp;</small></div></div>`;
      const pc = Number(r.ontime_pct), cls = pc >= 90 ? '' : pc >= 70 ? 'mid' : 'low', col = pc >= 90 ? '#34d08c' : pc >= 70 ? '#f6b93b' : '#ff6b7c';
      return `<div class="col${p === cur ? ' cur' : ''}" title="${esc(p)} : ทันเวลา ${pc}% (${r.ontime}/${r.n} จุด)${r.avg_late != null ? ' · สายเฉลี่ย ' + r.avg_late + ' นาที' : ''}">
        <div class="pa"><span class="v" style="color:${col}">${Math.round(pc)}%</span><i class="bar ${cls}" style="height:${Math.max(1, pc) * 1.5}px"></i></div>
        <div class="xl">${lab(p)}<small>${r.n} จุด</small></div></div>`;
    }).join('');
  }

  async function loadTrend() {
    const d = $('date').value || today();
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
      $('dtBody').innerHTML = rows.length ? rows.slice().reverse().map(r => `<tr><td>${esc(r.period)}</td><td class="num">${r.n}</td><td class="num">${r.ontime}</td><td class="num">${r.late}</td>
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
  function changeDate() { fitted = false; closeDet(); board = null; load(true); loadTrend(); }

  $('date').value = today();
  if (window.DateBox) DateBox.attach($('date'));
  $('date').onchange = changeDate;
  $('today').onclick = () => { $('date').value = today(); if (window.DateBox && DateBox.sync) DateBox.sync($('date')); changeDate(); };
  $('dtDay').onclick = () => { group = 'day'; loadTrend(); };
  $('dtMon').onclick = () => { group = 'month'; loadTrend(); };
  window.addEventListener('keydown', e => { if (e.key === 'Escape') closeDet(); });
  (async () => {
    initMap();
    if (!SB.ON) return say('โหมดตัวอย่าง: ยังไม่ได้ใส่ SUPABASE_URL ใน config.js');
    if (!Auth.get()) await Auth.login();
    Auth.badge($('userBox'));
    load(); loadTrend();
    setInterval(tick, 1000);
    document.addEventListener('visibilitychange', () => { if (!document.hidden && left < REFRESH - 5) load(); });
  })();
})();
