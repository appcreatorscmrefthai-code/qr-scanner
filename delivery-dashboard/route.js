/* หน้า Route Plan (route.html) : แผนงานของวันที่เลือกบนแผนที่ สำหรับวางแผนจัดส่งล่วงหน้า
   ข้อมูลจาก RPC plan_map (ต้องเข้าสู่ระบบ) ไม่แก้ไขข้อมูลใดๆ
   - สีประจำงาน (ชุดเดียวกับหน้า Summary) จุดส่งเรียงเลข เส้นตรง SCM → จุด 1 → จุด 2 ... (ไป-กลับ = เส้นกลับ SCM)
   - ประมาณระยะ/เวลาขับ และเตือนเมื่อเวลานัดระหว่างจุดน้อยกว่าเวลาขับโดยประมาณ
   - เตือนจุดส่งที่ยังไม่มีพิกัด (เติมได้ที่หน้า ETA) */
(function () {
  const $ = id => document.getElementById(id);
  const esc = v => String(v == null ? '' : v).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const PAL = ['#e6194B', '#3cb44b', '#4363d8', '#f58231', '#911eb4', '#0aa5c0', '#f032e6', '#9A6324', '#469990', '#000075', '#808000', '#800000', '#2f4f4f', '#c2185b', '#5d8aa8'];
  const TH_DOW = ['อา.', 'จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.'];
  const today = () => new Date(Date.now() + 7 * 36e5).toISOString().slice(0, 10);
  const addDays = (s, n) => { const d = new Date(s + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
  const say = t => { $('msg').textContent = t || ''; };
  const short = (n, m) => { n = String(n || '').trim(); return n.length > m ? n.slice(0, m - 1) + '…' : n; };
  const dur = m => m >= 60 ? `${Math.floor(m / 60)} ชม. ${m % 60} นาที` : `${m} นาที`;

  let map = null, layer = null, data = null, busy = false, showNames = true, showLabels = true, focus = null;
  const hidden = new Set();

  /* ---------- คำนวณระยะ / เวลา ---------- */
  function km(a, b) {
    const R = 6371, r = x => x * Math.PI / 180;
    const dLa = r(b.lat - a.lat), dLo = r(b.lng - a.lng);
    const h = Math.sin(dLa / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(dLo / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(h));
  }
  // ผลต่อจุด : km / min ของช่วงที่มาถึงจุดนี้ (null = ไม่รู้เพราะขาดพิกัด) และเตือนเวลาไม่พอ
  function plan(t) {
    const c = data.cfg || {}, det = Number(c.detour) || 1.3, spd = Number(c.speed) || 45, unl = Number(c.unload) || 0;
    let prev = data.origin ? { lat: data.origin.lat, lng: data.origin.lng } : null;
    let prevT = t.sched_at ? new Date(t.sched_at) : null, prevIsOrigin = true;
    let total = 0, totalMin = 0, unknown = false, warn = 0, miss = 0;
    const legs = (t.stops || []).map(s => {
      const has = s.lat != null && s.lng != null, out = { km: null, min: null, avail: null, short: false };
      if (!has) { miss++; unknown = true; }
      if (has && prev) {
        out.km = km(prev, s) * det; out.min = Math.round(out.km / spd * 60);
        total += out.km; totalMin += out.min + (prevIsOrigin ? 0 : unl);
      } else if (has && !prev) unknown = true;
      const pt = s.plan ? new Date(s.plan) : null;
      if (pt && prevT && out.min != null) {
        out.avail = Math.round((pt - prevT) / 60000) - (prevIsOrigin ? 0 : unl);
        if (out.avail < out.min) { out.short = true; warn++; }
      }
      prev = has ? { lat: s.lat, lng: s.lng } : null;
      prevT = pt; prevIsOrigin = false;
      return out;
    });
    let back = null;
    if (t.round_trip && prev && data.origin) { back = km(prev, data.origin) * det; total += back; totalMin += Math.round(back / spd * 60) + unl; }
    return { legs, total, totalMin, unknown, warn, miss, back };
  }

  /* ---------- แผนที่ ---------- */
  function initMap() {
    if (typeof L === 'undefined') { say('โหลดแผนที่ไม่สำเร็จ (ตรวจอินเทอร์เน็ต) ยังดูรายการงานได้'); return; }
    map = L.map('map', { zoomControl: true }).setView([13.75, 100.6], 9);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '&copy; OpenStreetMap' }).addTo(map);
    layer = L.layerGroup().addTo(map);
    $('legend').innerHTML = '<div class="lx"><b>สีตามงาน</b> (ดูรายการด้านขวา)</div><div class="lx">■ SCM &nbsp; ● จุดส่ง (เลขลำดับ)</div>'
      + '<div class="lx">- - - เส้นตรงไปจุดส่ง &nbsp; ··· กลับ SCM (ไป-กลับ)</div>'
      + '<label><input type="checkbox" id="nameTog" checked> แสดงชื่อจุดส่ง</label>'
      + '<label><input type="checkbox" id="labTog" checked> แสดงป้ายงาน</label>';
    $('nameTog').onchange = e => { showNames = e.target.checked; draw(false); };
    $('labTog').onchange = e => { showLabels = e.target.checked; draw(false); };
  }
  const pinIcon = (txt, color, size, sq) => L.divIcon({ className: '', iconSize: [size, size], iconAnchor: [size / 2, size / 2],
    html: `<div class="pin${sq ? ' sq' : ''}" style="width:${size}px;height:${size}px;background:${color}">${esc(txt)}</div>` });

  function draw(fit) {
    if (!map || !data) return;
    layer.clearLayers();
    const pts = [], o = data.origin;
    if (o) {
      L.marker([o.lat, o.lng], { icon: pinIcon('SCM', '#4aa8ff', 34, true), zIndexOffset: 500 }).addTo(layer).bindTooltip('SCM (ต้นทาง)');
      pts.push([o.lat, o.lng]);
    }
    data.tasks.forEach(t => {
      if (hidden.has(t.task_code)) return;
      const col = t._color, dim = focus && focus !== t.task_code, op = dim ? .2 : 1;
      let prev = o ? [o.lat, o.lng] : null, first = null, last = null;
      (t.stops || []).forEach(s => {
        if (s.lat == null || s.lng == null) { prev = null; return; }
        const p = [s.lat, s.lng];
        if (prev) L.polyline([prev, p], { color: col, weight: 4, opacity: .85 * op, dashArray: '9 7' }).addTo(layer);
        const m = L.marker(p, { icon: pinIcon(s.i, col, 24), zIndexOffset: dim ? 0 : 200, opacity: op }).addTo(layer);
        m.on('click', e => { L.DomEvent.stopPropagation(e); setFocus(t.task_code); });
        if (showNames && !dim) m.bindTooltip(`<span style="border-left:4px solid ${col};padding-left:4px">${s.i}. ${esc(short(s.name, 24))}${s.arr ? ' · ' + esc(s.arr) : ''}</span>`, { permanent: true, direction: 'right', offset: [12, 0], className: 'slab' });
        else m.bindTooltip(`<b style="color:${col}">${esc(t.task_code)}</b><br>${s.i}. ${esc(s.name)}${s.arr ? '<br>นัด ' + esc(s.arr) : ''}`);
        if (!first) first = p;
        last = p; prev = p; pts.push(p);
      });
      if (t.round_trip && last && o) L.polyline([last, [o.lat, o.lng]], { color: col, weight: 3, opacity: .7 * op, dashArray: '2 8' }).addTo(layer);
      if (showLabels && first && !dim) {
        const lbl = `${esc(t.plate || t.vehicle_type || '-')} · ${esc(t.task_code)}${t.schedule ? ' · ' + esc(t.schedule) : ''}${t._p.warn ? ' ⚠' : ''}`;
        L.marker(first, { interactive: false, zIndexOffset: 300, icon: L.divIcon({ className: '', iconSize: [0, 0],
          html: `<span class="vlab" style="position:absolute;left:0;bottom:14px;transform:translateX(-50%);background:${col}">${lbl}</span>` }) }).addTo(layer);
      }
    });
    if (fit !== false) {
      const fp = focus ? focusPts() : pts;
      if (fp.length) map.fitBounds(fp, { paddingTopLeft: [40, 60], paddingBottomRight: [40, 40], maxZoom: 14 });
    }
  }
  function focusPts() {
    const t = data.tasks.find(x => x.task_code === focus), p = data.origin ? [[data.origin.lat, data.origin.lng]] : [];
    (t ? t.stops : []).forEach(s => { if (s.lat != null) p.push([s.lat, s.lng]); });
    return p;
  }
  function setFocus(code) {
    focus = focus === code ? null : code;
    if (focus) hidden.delete(focus);
    renderList(); draw(true);
  }

  /* ---------- รายการ / KPI / วัน ---------- */
  function renderDays() {
    const td = today(), sel = data.date;
    $('days').innerHTML = (data.days || []).map(d => {
      const dt = new Date(d.date + 'T00:00:00Z');
      return `<button type="button" data-d="${d.date}" class="${d.date === sel ? 'on' : ''} ${d.n ? 'has' : ''} ${d.date === td ? 'today' : ''}" title="${d.date}">
        <small>${TH_DOW[dt.getUTCDay()]}${d.date === td ? ' (วันนี้)' : ''}</small><b>${dt.getUTCDate()}/${dt.getUTCMonth() + 1}</b><span>${d.n ? d.n + ' งาน' : '–'}</span></button>`;
    }).join('');
    $('days').querySelectorAll('button').forEach(b => b.onclick = () => go(b.dataset.d));
    const on = $('days').querySelector('button.on'); if (on) on.scrollIntoView({ block: 'nearest', inline: 'center' });
  }
  function renderKpi() {
    const ts = data.tasks, nStop = ts.reduce((a, t) => a + (t.stops || []).length, 0);
    const kmAll = ts.reduce((a, t) => a + t._p.total, 0), miss = ts.reduce((a, t) => a + t._p.miss, 0), warn = ts.filter(t => t._p.warn).length;
    $('kpi').innerHTML = [['งานในวัน', ts.length, '#4aa8ff'], ['จุดส่ง', nStop, '#38bdf8'], ['ระยะรวมโดยประมาณ (กม.)', Math.round(kmAll), '#a78bfa'],
      ['งานที่เวลาอาจไม่พอ', warn, warn ? '#f6b93b' : '#34d08c'], ['จุดที่ยังไม่มีพิกัด', miss, miss ? '#ff4d61' : '#34d08c'], ['ยกเลิก (ไม่แสดง)', data.canceled || 0, '#8e9bb3']]
      .map(([n, v, c]) => `<div style="--c:${c}"><b>${v}</b><span>${n}</span></div>`).join('');
  }
  function renderList() {
    const ts = data.tasks;
    $('sideTitle').textContent = `งานวันที่ ${data.date} (${ts.length})`;
    if (!ts.length) { $('list').innerHTML = '<div class="empty">ไม่มีงานในวันนี้<br><span class="small">เลือกวันอื่นจากแถบด้านบน</span></div>'; return; }
    $('list').innerHTML = ts.map(t => {
      const p = t._p, off = hidden.has(t.task_code);
      const st = p.miss ? '<span class="tag na">ขาดพิกัด</span>' : p.warn ? '<span class="tag risk">เวลาอาจไม่พอ</span>' : '<span class="tag ok">เวลาพอ</span>';
      const stops = (t.stops || []).map((s, k) => {
        const l = p.legs[k];
        const lg = l.km != null ? `${l.km.toFixed(1)} กม. · ขับ ~${dur(l.min)}${l.avail != null ? ` · มีเวลา ${dur(Math.max(0, l.avail))}` : ''}` : '';
        const w = s.lat == null ? `<span class="warn">⚠ ยังไม่มีพิกัด : เติมที่ <a href="eta.html" onclick="event.stopPropagation()">หน้า ETA / GPS</a></span>`
          : l.short ? `<span class="warn">⚠ เวลาอาจไม่พอ : ต้องใช้ ~${dur(l.min)} แต่มี ${dur(Math.max(0, l.avail))}</span>` : '';
        return `<li><span class="n">${s.i}</span><span>${esc(s.name)}</span><span class="t">${s.arr ? 'นัด ' + esc(s.arr) : '<span class="muted">ไม่มีเวลานัด</span>'}</span>${lg ? `<span class="lg">${lg}</span>` : ''}${w}</li>`;
      }).join('');
      const tot = p.total ? `รวม ~${p.total.toFixed(1)} กม. · ขับ+ลงของ ~${dur(p.totalMin)}${t.round_trip ? ` (รวมกลับ SCM${p.back != null ? ' ' + p.back.toFixed(1) + ' กม.' : ''})` : ''}${p.unknown ? ' · ไม่รวมช่วงที่ขาดพิกัด' : ''}` : '';
      return `<div class="tk ${off ? 'off' : ''} ${focus === t.task_code ? 'foc' : ''}" tabindex="0" data-c="${esc(t.task_code)}" style="--c:${t._color}">
        <div class="hd"><input type="checkbox" ${off ? '' : 'checked'} aria-label="แสดงบนแผนที่" data-t="${esc(t.task_code)}"><i class="sw" style="background:${t._color}"></i><b>${esc(t.plate || t.vehicle_type || '(ยังไม่ระบุรถ)')}</b><span class="code">${esc(t.task_code)}</span>${st}</div>
        <div class="sub">นัดเข้า SCM ${esc(t.schedule || '-')} · ${esc(t.company || '-')}${t.plate && t.vehicle_type ? ' · ' + esc(t.vehicle_type) : ''}${t.round_trip ? ' · ไป-กลับ' : ''}${t.client ? ' · ' + esc(t.client) : ''}</div>
        <ol>${stops}</ol>${tot ? `<div class="tot">${tot}</div>` : ''}</div>`;
    }).join('');
    $('list').querySelectorAll('.tk').forEach(el => {
      el.onclick = e => { if (e.target.matches('input')) return; setFocus(el.dataset.c); };
      el.onkeydown = e => { if (e.key === 'Enter') setFocus(el.dataset.c); };
    });
    $('list').querySelectorAll('input[data-t]').forEach(cb => cb.onchange = () => {
      const c = cb.dataset.t; if (cb.checked) hidden.delete(c); else { hidden.add(c); if (focus === c) focus = null; }
      renderList(); draw(false);
    });
  }
  function renderAll(fit) {
    const c = data.cfg || {};
    $('cDet').textContent = c.detour; $('cSpd').textContent = c.speed; $('cUnl').textContent = c.unload;
    data.tasks.forEach((t, i) => { t._color = PAL[i % PAL.length]; t._p = plan(t); });
    renderDays(); renderKpi(); renderList(); draw(fit);
    if (!data.origin) say('ยังไม่ได้ตั้งพิกัดต้นทาง (SCM) ที่หน้า ETA : ไม่แสดงเส้นจาก SCM และไม่คำนวณระยะช่วงแรก');
  }

  /* ---------- โหลด ---------- */
  async function load(fit) {
    if (busy) return; busy = true;
    const d = $('date').value || today();
    try {
      const r = await Auth.rpc('plan_map', { p_date: d });
      if (($('date').value || today()) !== d) return;
      data = r; say(''); renderAll(fit);
    } catch (e) { say(/FORBIDDEN/.test(e.message || '') ? 'ไม่มีสิทธิ์ดูหน้านี้' : 'โหลดข้อมูลไม่สำเร็จ: ' + (e.message || e) + (/plan_map/.test(e.message || '') ? ' (ยังไม่ได้รัน SQL รุ่นล่าสุด)' : '')); }
    finally { busy = false; }
  }
  function go(d) {
    $('date').value = d; if (window.DateBox && DateBox.sync) DateBox.sync($('date'));
    focus = null; hidden.clear();
    $('dashLink').href = 'dashboard.html?date=' + encodeURIComponent(d);
    try { history.replaceState(null, '', 'route.html?date=' + encodeURIComponent(d)); } catch (e) { }
    load(true);
  }

  const q = new URLSearchParams(location.search).get('date');
  $('date').value = /^\d{4}-\d{2}-\d{2}$/.test(q || '') ? q : today();
  $('dashLink').href = 'dashboard.html?date=' + encodeURIComponent($('date').value);
  if (window.DateBox) DateBox.attach($('date'));
  $('date').onchange = () => go($('date').value || today());
  $('today').onclick = () => go(today());
  $('tmr').onclick = () => go(addDays(today(), 1));
  $('prev').onclick = () => go(addDays($('date').value || today(), -1));
  $('next').onclick = () => go(addDays($('date').value || today(), 1));
  $('reload').onclick = () => load(false);
  $('allOn').onclick = () => { hidden.clear(); renderList(); draw(true); };
  $('allOff').onclick = () => { if (!data) return; data.tasks.forEach(t => hidden.add(t.task_code)); focus = null; renderList(); draw(false); };
  window.addEventListener('keydown', e => { if (e.key === 'Escape' && focus) setFocus(focus); });
  (async () => {
    initMap();
    if (!SB.ON) return say('โหมดตัวอย่าง: ยังไม่ได้ใส่ SUPABASE_URL ใน config.js');
    if (!Auth.get()) await Auth.login();
    Auth.badge($('userBox'));
    load(true);
    setInterval(() => { if (!document.hidden) load(false); }, 5 * 60e3);
  })();
})();
