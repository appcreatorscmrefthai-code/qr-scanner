/* ฟอร์มผู้จัดส่งแบบ GPS (road-gps.html) สำหรับ บริษัท ปทุม ทรานสปอร์ต จำกัด
   สถานะ รถเข้า SCM > รถออก > ถึงหน้างาน มาจาก GPS อัตโนมัติ คนขับส่งเฉพาะ "สถานการณ์เมื่อออกไปแล้ว 1 ชม." และรูปลงงาน (ไม่บังคับ) */
(function () {
  const { $, esc, hhmm } = DF;
  let task = null, chain = Promise.resolve(), pending = 0, gen = 0;
  const ctx = () => ({ taskCode: task && task.taskCode, stop: task ? nextStop() + 1 : 0 });
  const pkRoad = DF.makePicker({ key: 'road', kind: 'road', el: 'pkRoad', max: 5, maxMB: 5, label: 'รูปสถานการณ์บนถนน', context: ctx });
  const pkUnload = DF.makePicker({ key: 'unload', kind: 'unload', el: 'pkUnload', max: 20, maxMB: 50, label: 'รูปลงงาน', context: ctx });
  const show = (id, on) => { $(id).hidden = !on; };
  const nextStop = () => task.state.done.findIndex(d => !d);
  const addH = (iso, h) => iso ? new Date(new Date(iso).getTime() + h * 3600e3).toISOString() : '';

  const pagePath = () => 'road.html?task=' + encodeURIComponent(task.taskCode) + '&force=1';
  async function load(code, quiet) {
    if (!code) return;
    if (!quiet) DF.say('กำลังโหลดข้อมูลงาน…', 'info');
    try {
      const t = (await DF.retry(() => DF.apiGet({ action: 'task', code }), 2)).task;
      if (!DF.isGpsCompany(t.company)) { location.replace('road.html?task=' + encodeURIComponent(t.taskCode)); return; }
      task = t; show('scanCard', false); show('app', true);
      DF.say(''); $('manualLink').href = pagePath(); render();
    } catch (e) {
      if (quiet) return;
      task = null; show('app', false); show('scanCard', true);
      DF.say(e.message || 'ไม่พบงานนี้');
    }
  }

  // รายการแหล่งที่มาของแต่ละเหตุการณ์ (GPS / คน)
  function srcOf(type, stop) {
    if (type === 'depart') return task.pickupLog ? task.pickupLog.source : '';
    const l = task.logs.find(x => x.type === type && (stop == null || x.stop === stop));
    return l ? l.source : '';
  }
  const badge = src => src ? `<span class="m" style="margin-left:6px">${src === 'GPS' ? '📡 GPS' : '👤 คน'}</span>` : '';
  const row = (label, time, src) => `<div class="eta"><span>${esc(label)}</span><b class="${time ? 'okline' : ''}" style="text-align:right">${time ? hhmm(time) + ' น.' + badge(src) : '<span class="m">รอ GPS</span>'}</b></div>`;

  function render() {
    const s = task.state, n = task.stops.length, k = nextStop(), allDone = k < 0;
    const back = allDone && task.roundTrip && !s.returned, fin = allDone && !back;
    const atSite = !allDone && !!s.arrive[k];
    $('taskBox').innerHTML = DF.taskCard(task);

    const lines = [row('1. รถเข้า SCM', s.checkin && s.checkin.time, srcOf('checkin')), row('2. รถออกจาก SCM', s.depart, srcOf('depart'))];
    const hr = s.depart ? addH(s.depart, 1) : '';
    lines.push(`<div class="eta"><span>3. สถานการณ์เมื่อออกไปแล้ว 1 ชม.${hr ? ' <span class="m">(ครบ ' + hhmm(hr) + ' น.)</span>' : ''}</span>
      <b class="${s.roadCount ? 'okline' : ''}" style="text-align:right">${s.roadCount ? 'ส่งแล้ว ' + hhmm(s.lastRoad) + ' น.' + badge('คน') : '<span class="m">รอคนขับส่ง</span>'}</b></div>`);
    task.stops.forEach((st, i) => { lines.push(row(`${i + 4}. รถถึงหน้างาน ${st.name} (นัด ${st.arrival || '-'})`, s.arrive[i], srcOf('arrive', i + 1))); });
    $('gList').innerHTML = lines.join('');
    $('gHint').textContent = fin ? '✓ จบงานแล้ว' : back ? 'ลงงานครบแล้ว รอ GPS บันทึกรถกลับถึง SCM' : s.depart ? '' : 'สถานะอัปเดตทุก 5 นาทีตามตำแหน่งรถ หน้านี้โหลดสถานะใหม่ให้เอง';

    // สถานการณ์ 1 ชม. : เปิดเมื่อรถออกแล้ว และยังไม่ถึงหน้างานจุดสุดท้าย
    show('s2', !!s.depart && !fin && !back);
    const lock2 = atSite ? `รถถึงหน้างานจุดที่ ${k + 1} แล้ว ส่งสถานการณ์ได้อีกครั้งหลังรถออกจากจุดนี้` : '';
    show('s2lock', !!lock2); $('s2lock').textContent = lock2; show('s2body', !lock2);
    $('s2time').textContent = hr ? (Date.now() < new Date(hr).getTime() ? `รถออกเมื่อ ${hhmm(s.depart)} น. ควรส่งเมื่อครบ 1 ชม. (เวลา ${hhmm(hr)} น.)` : `รถออกไปแล้วเกิน 1 ชม. (ออกเมื่อ ${hhmm(s.depart)} น.) ส่งสถานการณ์ได้เลย`) : '';

    // รูปลงงาน (ไม่บังคับ) เมื่อรถถึงหน้างานแล้ว
    show('s3', atSite);
    if (atSite) {
      const last = k === n - 1 && !task.roundTrip, st = task.stops[k];
      $('arrivedLine').textContent = `✓ ถึงหน้างานจุดที่ ${k + 1} เวลา ${hhmm(s.arrive[k])} น. · ${st.name}`;
      $('unloadBtn').textContent = last ? `ลงงานจุดที่ ${k + 1} เสร็จ และจบงาน` : `ลงงานจุดที่ ${k + 1} เสร็จ`;
    }
  }

  function act(body, pickers, okText) {
    if (!task) return false;
    DF.say('');
    const code = task.taskCode, my = ++gen, t0 = Date.now();
    DF.apply(task.state, body, new Date().toISOString(), task);
    render(); DF.toast(okText);
    pending++; showSync();
    const job = DF.submitWithPhotos(Object.assign({ form: 'driver', taskCode: code, lite: 1 }, body), pickers, chain);
    chain = job.then(d => {
      pending--; showSync(`บันทึกเข้าระบบแล้ว ${hhmm(d.time)} น. (${((Date.now() - t0) / 1000).toFixed(1)} วินาที)`);
      if (!pending) load(code, true);
    }, async e => {
      pending--; showSync('');
      DF.say('บันทึกไม่สำเร็จ: ' + (e.message || e) + ' กรุณาตรวจอินเทอร์เน็ตแล้วกดอีกครั้ง');
      load(code, true);
    });
    return true;
  }
  function showSync(doneText) {
    const el = $('sync'); if (!el) return;
    el.textContent = pending ? `กำลังบันทึกเข้าระบบ ${pending} รายการ… กรุณาอย่าปิดหน้านี้` : (doneText || '');
    el.hidden = !el.textContent;
  }
  window.addEventListener('beforeunload', e => { if (pending) { e.preventDefault(); e.returnValue = ''; } });

  $('roadBtn').onclick = () => {
    const note = $('noteRoad').value.trim();
    if (!pkRoad.items.length && !note) return DF.say('กรุณาแนบรูปหรือใส่หมายเหตุ อย่างน้อยหนึ่งอย่าง');
    if (act({ type: 'road', note }, [pkRoad], 'ส่งสถานการณ์เรียบร้อย')) $('noteRoad').value = '';
  };
  $('unloadBtn').onclick = async () => {
    const k = nextStop(), st = task.stops[k], last = k === task.stops.length - 1 && !task.roundTrip;
    if (!(await DF.confirmBox(`ยืนยันลงงานจุดที่ ${k + 1} (${st.name}) เสร็จ ?` + (last ? ' จุดนี้เป็นจุดสุดท้าย ระบบจะจบงานนี้' : ''), last ? 'ยืนยันจบงาน' : 'ยืนยัน'))) return;
    if (act({ type: 'unload', stop: k + 1, note: $('noteUnload').value.trim() }, [pkUnload], `ลงงานจุดที่ ${k + 1} เรียบร้อย`)) $('noteUnload').value = '';
  };

  $('scanBtn').onclick = () => DF.startScan(load);
  // โหลดสถานะใหม่ทุก 30 วินาที (ไม่ทำตอนกำลังส่งข้อมูล) เพื่อให้เห็นสถานะที่ GPS บันทึก
  setInterval(() => { if (task && !pending && !document.hidden) load(task.taskCode, true); }, 30000);
  DF.clock();
  if (DF.DEMO) $('demo').hidden = false;
  if (DF.param('task')) load(DF.param('task')); else show('scanCard', true);
})();
