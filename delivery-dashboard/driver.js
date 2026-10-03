/* ฟอร์มผู้จัดส่ง (road.html): เช็คอิน -> สถานการณ์บนถนน -> ถึงหน้างาน / ลงงานแต่ละจุด */
(function () {
  const { $, esc, hhmm } = DF;
  let task = null, busy = false;
  const ctx = () => ({ taskCode: task && task.taskCode, stop: task ? nextStop() + 1 : 0 });
  const pkRoad = DF.makePicker({ key: 'road', kind: 'road', el: 'pkRoad', max: 5, maxMB: 5, label: 'รูปสถานการณ์บนถนน', context: ctx });
  const pkUnload = DF.makePicker({ key: 'unload', kind: 'unload', el: 'pkUnload', max: 20, maxMB: 50, label: 'รูปลงงาน', context: ctx });

  const show = (id, on) => { $(id).hidden = !on; };
  // จุดถัดไปที่ยังไม่ลงงาน (เริ่มที่ 0) ถ้าครบแล้วคืน -1
  const nextStop = () => task.state.done.findIndex(d => !d);

  async function load(code) {
    if (!code) return;
    DF.say('กำลังโหลดข้อมูลงาน…', 'info');
    try {
      task = (await DF.retry(() => DF.apiGet({ action: 'task', code }), 2)).task;
      show('scanCard', false); show('app', true);
      DF.say(''); render(true);
    } catch (e) {
      task = null; show('app', false); show('scanCard', true);
      DF.say(e.message || 'ไม่พบงานนี้');
    }
  }

  function render(resetPlate) {
    const s = task.state, n = task.stops.length, k = nextStop(), allDone = k < 0;
    const back = allDone && task.roundTrip && !s.returned;      // งานไป-กลับ: ลงงานครบแล้ว กำลังกลับ SCM
    const fin = allDone && !back;
    const atSite = !allDone && !!s.arrive[k];
    $('taskBox').innerHTML = DF.taskCard(task);

    // 1. เช็คอิน
    show('s1done', !!s.checkin); show('s1form', !s.checkin);
    if (s.checkin) $('s1done').textContent = `✓ เช็คอินแล้ว ${hhmm(s.checkin.time)} น. · ทะเบียน ${s.checkin.plate || task.plate || '-'}`;
    else if (resetPlate) {
      $('plate').value = task.plate || '';
      $('plate').readOnly = !!task.plate;          // ไม่มีทะเบียนในระบบ ให้กรอกได้เลย
      show('plateEdit', !!task.plate);
      if (!task.plate) $('plateHint').textContent = 'ยังไม่มีทะเบียนรถในระบบ กรุณาพิมพ์ตามรูปแบบ เช่น 3 ฒผ 2186';
    }

    // 2. สถานการณ์บนถนน
    const lock2 = !s.checkin ? 'เช็คอินก่อน จึงจะส่งสถานการณ์บนถนนได้' : fin ? 'จบงานแล้ว'
      : atSite ? `รถถึงหน้างานจุดที่ ${k + 1} แล้ว ส่งสถานการณ์บนถนนได้อีกครั้งหลังลงงานจุดนี้เสร็จ` : '';
    show('s2lock', !!lock2); $('s2lock').textContent = lock2; show('s2body', !lock2);
    if (!lock2) {
      $('etaBox').innerHTML = task.stops.map((st, i) => s.arrive[i] ? '' :
        `<label class="eta"><span>จุดที่ ${i + 1} ${esc(st.name)} <span class="m">นัด ${esc(st.arrival || '-')}</span></span>
         <input class="inp" type="time" data-eta="${i}" value="${esc(s.eta[i] || '')}"></label>`).join('');
    }

    // 3. ส่งงาน / จบงาน
    const lock3 = !s.checkin ? 'เช็คอินก่อน จึงจะบันทึกการส่งงานได้' : fin ? (task.roundTrip ? `✓ รถกลับถึง SCM จบงานแล้ว ${hhmm(s.returned)} น.` : `✓ ลงงานครบทุกจุด จบงานแล้ว ${hhmm(s.done[n - 1])} น.`) : '';
    show('s3lock', !!lock3); $('s3lock').textContent = lock3; $('s3lock').className = fin ? 'okline' : 'lock';
    show('s3arrive', !lock3 && !atSite); show('s3unload', !lock3 && atSite);
    if (!lock3 && back) {
      $('arriveText').textContent = 'ลงงานครบทุกจุดแล้ว งานนี้เป็นรอบไป-กลับ กดเมื่อรถกลับถึง SCM เพื่อจบงาน';
      $('arriveBtn').textContent = 'รถกลับถึง SCM';
    } else if (!lock3) {
      const st = task.stops[k], last = k === n - 1 && !task.roundTrip;
      $('arriveText').textContent = `จุดถัดไป: จุดที่ ${k + 1} ${st.name} (นัด ${st.arrival || '-'}) กดเมื่อรถถึงหน้างานแล้ว จึงจะขึ้นส่วนลงงาน`;
      $('arriveBtn').textContent = `รถถึงหน้างาน จุดที่ ${k + 1}`;
      $('arrivedLine').textContent = atSite ? `✓ ถึงหน้างานจุดที่ ${k + 1} เวลา ${hhmm(s.arrive[k])} น. · ${st.name}` : '';
      $('unloadBtn').textContent = last ? `ลงงานจุดที่ ${k + 1} เสร็จ และจบงาน` : `ลงงานจุดที่ ${k + 1} เสร็จ`;
    }
    lockUi();
  }

  function lockUi() {
    document.querySelectorAll('.act').forEach(b => { b.disabled = busy; });
  }

  // ส่งรายการหนึ่งรายการ: หน้าจอเปลี่ยนสถานะทันที แล้วจึงยืนยันกับเซิร์ฟเวอร์ (ถ้าไม่สำเร็จจะย้อนกลับและแจ้งเตือน)
  async function act(body, pickers, okText) {
    if (busy || !task) return false;
    busy = true; DF.say('');
    const before = JSON.parse(JSON.stringify(task));
    DF.apply(task.state, body, new Date().toISOString(), task);
    render(false);
    DF.toast(okText + ' · กำลังบันทึก…');
    try {
      const d = await DF.submitWithPhotos(Object.assign({ form: 'driver', taskCode: task.taskCode }, body), pickers);
      task = d.task;
      DF.toast(`${okText} (${hhmm(d.time)} น.)`);
      return true;
    } catch (e) {
      task = before;
      DF.say('บันทึกไม่สำเร็จ: ' + (e.message || e) + ' กรุณากดอีกครั้ง');
      return false;
    } finally {
      busy = false; if (task) render(false);
    }
  }

  $('plateEdit').onclick = () => { $('plate').readOnly = false; $('plate').focus(); $('plate').select(); };
  $('checkinBtn').onclick = async () => {
    const plate = DF.normPlate($('plate').value);
    if (!plate) return DF.say('รูปแบบทะเบียนรถไม่ถูกต้อง ตัวอย่าง: 3 ฒผ 2186');
    if (task.plate && plate !== task.plate &&
        !(await DF.confirmBox(`ทะเบียนในระบบคือ ${task.plate} ต้องการแก้เป็น ${plate} ใช่ไหม ระบบจะบันทึกการแก้ไขนี้`, 'ยืนยันแก้ไขและเช็คอิน'))) return;
    act({ type: 'checkin', plate }, [], 'เช็คอินเรียบร้อย');
  };
  $('roadBtn').onclick = async () => {
    const eta = task.stops.map(() => '');
    document.querySelectorAll('[data-eta]').forEach(i => { eta[Number(i.dataset.eta)] = i.value; });
    const changed = eta.some((v, i) => v && v !== task.state.eta[i]);
    const note = $('noteRoad').value.trim();
    if (!pkRoad.items.length && !note && !changed) return DF.say('กรุณาแนบรูป ใส่หมายเหตุ หรือเวลาที่คาดว่าจะถึง อย่างน้อยหนึ่งอย่าง');
    if (await act({ type: 'road', note, eta }, [pkRoad], 'ส่งสถานการณ์บนถนนเรียบร้อย')) $('noteRoad').value = '';
  };
  $('arriveBtn').onclick = async () => {
    const k = nextStop(), st = task.stops[k];
    if (k < 0) {
      if (!(await DF.confirmBox('ยืนยันว่ารถกลับถึง SCM แล้ว ? ระบบจะจบงานนี้', 'ยืนยันจบงาน'))) return;
      return act({ type: 'return' }, [], 'รถกลับถึง SCM จบงานเรียบร้อย');
    }
    if (!(await DF.confirmBox(`ยืนยันว่ารถถึงหน้างาน จุดที่ ${k + 1} (${st.name}) แล้ว ?`, 'ยืนยันถึงหน้างาน'))) return;
    act({ type: 'arrive', stop: k + 1 }, [], `บันทึกถึงหน้างานจุดที่ ${k + 1} เรียบร้อย`);
  };
  $('unloadBtn').onclick = async () => {
    const k = nextStop(), st = task.stops[k], last = k === task.stops.length - 1 && !task.roundTrip;
    if (!(await DF.confirmBox(`ยืนยันลงงานจุดที่ ${k + 1} (${st.name}) เสร็จ ?` + (last ? ' จุดนี้เป็นจุดสุดท้าย ระบบจะจบงานนี้' : ''), last ? 'ยืนยันจบงาน' : 'ยืนยัน'))) return;
    if (await act({ type: 'unload', stop: k + 1, note: $('noteUnload').value.trim() }, [pkUnload], last ? 'ลงงานครบทุกจุด จบงานเรียบร้อย' : `ลงงานจุดที่ ${k + 1} เรียบร้อย`)) $('noteUnload').value = '';
  };

  $('scanBtn').onclick = () => DF.startScan(load);
  DF.clock();
  if (DF.DEMO) $('demo').hidden = false;
  if (DF.param('task')) load(DF.param('task')); else show('scanCard', true);
})();
