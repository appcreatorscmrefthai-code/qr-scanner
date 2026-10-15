/* ฟอร์มอัปโหลดรูปส่งงาน ใช้ร่วมกัน 2 หน้า : pickup.html (WH คลังสินค้า) และ qa.html (QA ประกันคุณภาพ)
   - งานในประเทศ : ส่งได้หลายครั้ง รวมไม่เกิน WH 20 รูป / QA 50 รูป (ครั้งละไม่เกิน 50 MB)
   - งานต่างประเทศ (ประเภทรถ CL 20FT / CL 40FT / CL 40HC / LCL / DHL) : หน้าเดิมเปลี่ยนเป็นโหมดต่างประเทศเอง
       WH และ QA รวมไม่เกิน 300 รูป (ครั้งละไม่เกิน 300 MB)
       WH มีเพิ่ม : 2. รูปรถเข้า (ส่งครั้งแรก = เวลารถเข้า) และ 3. รูปส่งงาน (ส่งครั้งแรก = เวลารถออก = จบงาน)
       ต้องส่งรูปรถเข้าก่อน จึงส่งรูปส่งงานได้ ; ส่งรูปเพิ่มทั้ง 2 หัวข้อได้ เวลารถเข้า-ออกยึดการส่งครั้งแรก
   - เปิดรับรูปส่งงานจนครบ 24 ชม. นับจากอัปโหลดครั้งล่าสุดของฝ่ายนั้น
   - เห็นรูปที่ส่งไปแล้ว (ดูอย่างเดียว ลบไม่ได้) และจำนวนที่ส่งเพิ่มได้ */
(function () {
  const { $, esc, hhmm } = DF;
  const DEPT = window.UPLOAD_DEPT === 'QA' ? 'QA' : 'WH', FORM = DEPT === 'QA' ? 'qa' : 'pickup';
  const LIMIT = { WH: [20, 50], QA: [50, 50], INTL: [300, 300] };      // [จำนวนรูปรวม, MB ต่อครั้ง]
  let task = null, busy = false, MAX = LIMIT[DEPT][0];
  const cfg = { key: 'photos', kind: FORM, el: 'pkPhotos', max: LIMIT[DEPT][0], maxMB: LIMIT[DEPT][1], label: 'รูปส่งงาน', context: () => ({ taskCode: task && task.taskCode }) };
  const picker = DF.makePicker(cfg);
  const pkIn = DEPT === 'WH' ? DF.makePicker({ key: 'unload', kind: 'whin', el: 'pkIn', max: 20, maxMB: 50, label: 'รูปรถเข้า', context: () => ({ taskCode: task && task.taskCode }) }) : null;
  const rows = () => ((task && task.pickupRows) || []).filter(r => r.source !== 'GPS' && (r.dept || 'WH') === DEPT);
  const logOf = type => ((task && task.logs) || []).find(l => l.type === type);
  const show = (id, on) => { const el = $(id); if (el) el.hidden = !on; };
  const durTh = m => m >= 60 ? `${Math.floor(m / 60)} ชม.${m % 60 ? ' ' + (m % 60) + ' นาที' : ''}` : `${m} นาที`;
  let needIn = false;                                  // งานต่างประเทศ WH ที่ยังไม่ได้ส่งรูปรถเข้า : ยังส่งรูปส่งงานไม่ได้
  // งานต่างประเทศ WH : ย้ายหมายเหตุ + ปุ่มส่งเข้าไปในหัวข้อ 3 (แบบเดียวกับหัวข้อ 2) ; งานอื่นอยู่ที่เดิม
  const homeWrap = document.createComment('sendWrap'), noteLbl = document.createElement('label');
  $('sendWrap').before(homeWrap);
  noteLbl.htmlFor = 'note'; noteLbl.className = 'tailLbl'; noteLbl.textContent = 'หมายเหตุ (ถ้ามี)';
  noteLbl.style.cssText = 'display:block;margin:14px 0 6px;font-weight:600';
  function placeSend(inCard) {
    const note = $('note'), wrap = $('sendWrap');
    if (inCard) {
      $('phTail').append(noteLbl, note, wrap); wrap.style.marginTop = '12px';
    } else {
      noteLbl.remove(); $('noteBox').append(note); homeWrap.after(wrap); wrap.style.marginTop = '';
    }
    show('noteCard', !inCard);
  }

  // โหมดต่างประเทศ : ปรับหัวข้อ / จำนวนรูป / ส่วนรถเข้า-รถออก (WH)
  function applyMode() {
    const info = SB.intlInfo(task.vehicleType), intl = !!info, wh = intl && DEPT === 'WH';
    [cfg.max, cfg.maxMB] = intl ? LIMIT.INTL : LIMIT[DEPT];
    MAX = cfg.max; picker.redraw();
    show('intlTag', intl);
    $('phNote').textContent = `รวมไม่เกิน ${cfg.max} รูป · ครั้งละไม่เกิน ${cfg.maxMB} MB`;
    $('phTitle').textContent = (wh ? '3' : '2') + '. รูปส่งงาน';
    $('noteTitle').textContent = (wh ? '4' : '3') + '. หมายเหตุ';
    $('sendBtn').textContent = wh ? 'ส่งรูปส่งงาน' : 'ส่งข้อมูล';
    if (intl) $('sub').textContent = `งานต่างประเทศ (${info.label}) ${DEPT === 'WH' ? 'ส่งรูปรถเข้า (= เวลารถเข้า) > ส่งรูปส่งงาน (= เวลารถออก)' : 'อัปโหลดรูปตรวจสินค้า'} · ส่งรูปเพิ่มได้จนครบ 24 ชม. นับจากอัปโหลดครั้งล่าสุด`;
    show('inCard', wh); show('outInfo', wh); placeSend(wh);
    needIn = false;
    if (!wh) return;
    const ck = logOf('checkin'), dp = logOf('depart'), inN = ck ? (ck.unload || []).length : 0;
    const inClosed = ck && Date.now() > new Date(ck.time).getTime() + 24 * 3600e3;
    needIn = !ck;
    show('inDone', !!ck);
    if (ck) $('inDone').textContent = `✓ รถเข้า ${hhmm(ck.time)} น. (เวลาที่ส่งรูปรถเข้าครั้งแรก)` + (inClosed ? ' · ปิดรับรูปรถเข้าแล้ว (เกิน 24 ชม.)' : '');
    DF.sentBox('inSent', [{ label: 'รูปรถเข้าที่ส่งแล้ว', paths: ck ? ck.unload || [] : [], max: 20 }]);
    pkIn.setSent(inN);
    show('inBody', !inClosed && inN < 20);
    $('inBtn').textContent = ck ? 'ส่งรูปรถเข้าเพิ่ม' : 'ส่งรูปรถเข้า';
    if (dp) $('outInfo').innerHTML = `<span class="okline">✓ รถออก ${hhmm(dp.time)} น. (เวลาที่ส่งรูปส่งงานครั้งแรก) · จบงาน</span>`;
    else if (!ck) $('outInfo').textContent = 'ส่งรูปรถเข้า (หัวข้อ 2) ก่อน จึงส่งรูปส่งงานได้ · การส่งรูปส่งงานครั้งแรกจะบันทึกเป็นเวลารถออก (จบงาน)';
    else {
      const m = Math.round((Date.now() - new Date(ck.time)) / 60000);
      $('outInfo').textContent = `รถอยู่ที่ SCM แล้ว ${durTh(Math.max(0, m))} (เกณฑ์ ${info.label} ไม่เกิน ${durTh(info.min)}) · การส่งรูปส่งงานครั้งแรกจะบันทึกเป็นเวลารถออก (จบงาน)`;
    }
  }

  async function load(code) {
    if (!code) return;
    DF.say('กำลังโหลดข้อมูลงาน…', 'info');
    try {
      task = (await DF.retry(() => DF.apiGet({ action: 'task', code }), 2)).task;
      $('taskBox').hidden = false; $('taskBox').innerHTML = DF.taskCard(task);
      $('scanBtn').hidden = true; $('sendBtn').disabled = false;
      applyMode();
      const mine = rows(), sent = mine.flatMap(r => r.photos || []);
      picker.setSent(sent.length);
      DF.sentBox('sentBox', [{ label: 'รูปส่งงานที่ส่งแล้ว', paths: sent, max: MAX }]);
      const last = mine[mine.length - 1];
      $('winInfo').hidden = !last;
      if (last) {
        const close = new Date(new Date(last.time).getTime() + 24 * 3600e3), closed = Date.now() > close.getTime();
        $('winInfo').textContent = `อัปโหลดรูปส่งงานล่าสุด ${DF.fmt(last.time)} · ` + (closed ? 'ปิดรับรูปแล้ว (เกิน 24 ชม.)' : 'ส่งเพิ่มได้ถึง ' + DF.fmt(close.toISOString()));
        if (closed) { $('sendBtn').disabled = true; DF.say(`ปิดรับรูปจาก ${DEPT} แล้ว (เกิน 24 ชม. นับจากอัปโหลดครั้งล่าสุด)`); return; }
      }
      if (sent.length >= MAX) { $('sendBtn').disabled = true; DF.say(`ส่งรูปจาก ${DEPT} ครบ ${MAX} รูปแล้ว ส่งเพิ่มไม่ได้`, 'info'); return; }
      if (needIn) $('sendBtn').disabled = true;
      DF.say('');
    } catch (e) {
      task = null; $('scanBtn').hidden = false; $('sendBtn').disabled = true;
      DF.say(e.message || 'ไม่พบงานนี้');
    }
  }

  // ส่งรายการ + รูป แล้วแสดงหน้าสำเร็จ (ส่งไม่ผ่านจะกลับมาหน้าฟอร์มพร้อมรูปเดิม)
  async function send(body, pickers, okText) {
    if (busy || !task) return false;
    DF.say('');
    busy = true;
    const head = `<b>${esc(task.taskCode)}</b><br>`, t0 = Date.now();
    $('formBox').hidden = true; $('doneBox').hidden = false; $('moreBtn').hidden = true; window.scrollTo(0, 0);
    $('doneText').innerHTML = head + 'รับข้อมูลแล้ว กำลังส่งเข้าระบบ…<br><span style="color:var(--muted)">กรุณาเปิดหน้านี้ค้างไว้สักครู่</span>';
    try {
      const d = await DF.submitWithPhotos(Object.assign({ taskCode: task.taskCode }, body), pickers);
      const when = `<br><span style="color:var(--muted)">${DF.fmt(d.time)}</span>`;
      $('doneText').innerHTML = head + 'บันทึกแล้ว กำลังส่งรูปที่เหลือ…' + when;
      const ph = await d.photos;
      $('doneText').innerHTML = head + (ph.sent < ph.total ? `บันทึกแล้ว แต่มีรูป ${ph.total - ph.sent} รูปส่งไม่สำเร็จ` : okText) + when +
        `<br><span style="color:var(--muted);font-size:.8em">ใช้เวลา ${((Date.now() - t0) / 1000).toFixed(1)} วินาที</span>`;
      $('moreBtn').hidden = false;
      return true;
    } catch (e) {
      $('formBox').hidden = false; $('doneBox').hidden = true;
      DF.say('ส่งข้อมูลไม่สำเร็จ: ' + (e.message || e) + ' กรุณากดส่งอีกครั้ง');
      return false;
    } finally { busy = false; }
  }

  $('sendBtn').onclick = async () => {
    if (needIn) return DF.say('กรุณาส่งรูปรถเข้า (หัวข้อ 2) ก่อน');
    if (!picker.items.length) return DF.say('กรุณาแนบรูปส่งงานอย่างน้อย 1 รูป');
    const first = DEPT === 'WH' && task && SB.intlInfo(task.vehicleType) && !logOf('depart');
    $('sendBtn').disabled = true;
    if (await send({ form: FORM, note: $('note').value.trim() }, [picker], first ? 'บันทึกรูปส่งงานและเวลารถออกเรียบร้อย (จบงาน)' : `บันทึกรูปส่งงานจาก ${DEPT} เรียบร้อย`)) $('note').value = '';
    $('sendBtn').disabled = !task;
  };
  // รูปรถเข้า (งานต่างประเทศ WH) : ส่งครั้งแรก = เวลารถเข้า ส่งเพิ่มได้รวมไม่เกิน 20 รูป
  if (pkIn) $('inBtn').onclick = async () => {
    if (!pkIn.items.length) return DF.say('กรุณาแนบรูปรถเข้าอย่างน้อย 1 รูป');
    const first = !logOf('checkin');
    $('inBtn').disabled = true;
    await send({ form: 'wh_in', note: '' }, [pkIn], first ? 'บันทึกรูปรถเข้าและเวลารถเข้าเรียบร้อย' : 'บันทึกรูปรถเข้าเพิ่มเรียบร้อย');
    $('inBtn').disabled = false;
  };
  // ดูรูปที่ส่งแล้ว / ส่งเพิ่ม : โหลดข้อมูลงานใหม่แล้วกลับไปหน้าฟอร์ม
  $('moreBtn').onclick = async () => {
    $('doneBox').hidden = true; $('formBox').hidden = false; window.scrollTo(0, 0);
    if (task) await load(task.taskCode);
  };

  $('scanBtn').onclick = () => DF.startScan(load);
  DF.clock();
  if (DF.DEMO) $('demo').hidden = false;
  if (DF.param('task')) load(DF.param('task')); else $('scanBtn').hidden = false;
})();
