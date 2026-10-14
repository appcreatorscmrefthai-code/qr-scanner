/* ฟอร์มอัปโหลดรูปส่งงาน ใช้ร่วมกัน 2 หน้า : pickup.html (WH คลังสินค้า) และ qa.html (QA ประกันคุณภาพ)
   - ส่งได้หลายครั้ง รวมไม่เกิน 20 รูปต่อฝ่าย เปิดรับจนครบ 24 ชม. นับจากอัปโหลดครั้งล่าสุดของฝ่ายนั้น
   - เห็นรูปที่ส่งไปแล้ว (ดูอย่างเดียว ลบไม่ได้) และจำนวนที่ส่งเพิ่มได้ */
(function () {
  const { $, esc } = DF;
  const DEPT = window.UPLOAD_DEPT === 'QA' ? 'QA' : 'WH', FORM = DEPT === 'QA' ? 'qa' : 'pickup', MAX = 20;
  let task = null, busy = false;
  const picker = DF.makePicker({ key: 'photos', kind: FORM, el: 'pkPhotos', max: MAX, maxMB: 50, label: 'รูปส่งงาน', context: () => ({ taskCode: task && task.taskCode }) });
  const rows = () => ((task && task.pickupRows) || []).filter(r => r.source !== 'GPS' && (r.dept || 'WH') === DEPT);

  async function load(code) {
    if (!code) return;
    DF.say('กำลังโหลดข้อมูลงาน…', 'info');
    try {
      task = (await DF.retry(() => DF.apiGet({ action: 'task', code }), 2)).task;
      $('taskBox').hidden = false; $('taskBox').innerHTML = DF.taskCard(task);
      $('scanBtn').hidden = true; $('sendBtn').disabled = false;
      const mine = rows(), sent = mine.flatMap(r => r.photos || []);
      picker.setSent(sent.length);
      DF.sentBox('sentBox', [{ label: 'รูปที่ส่งแล้ว', paths: sent, max: MAX }]);
      const last = mine[mine.length - 1];
      $('winInfo').hidden = !last;
      if (last) {
        const close = new Date(new Date(last.time).getTime() + 24 * 3600e3), closed = Date.now() > close.getTime();
        $('winInfo').textContent = `อัปโหลดล่าสุด ${DF.fmt(last.time)} · ` + (closed ? 'ปิดรับรูปแล้ว (เกิน 24 ชม.)' : 'ส่งเพิ่มได้ถึง ' + DF.fmt(close.toISOString()));
        if (closed) { $('sendBtn').disabled = true; DF.say(`ปิดรับรูปจาก ${DEPT} แล้ว (เกิน 24 ชม. นับจากอัปโหลดครั้งล่าสุด)`); return; }
      }
      if (sent.length >= MAX) { $('sendBtn').disabled = true; DF.say(`ส่งรูปจาก ${DEPT} ครบ ${MAX} รูปแล้ว ส่งเพิ่มไม่ได้`, 'info'); return; }
      DF.say('');
    } catch (e) {
      task = null; $('scanBtn').hidden = false; $('sendBtn').disabled = true;
      DF.say(e.message || 'ไม่พบงานนี้');
    }
  }

  $('sendBtn').onclick = async () => {
    if (busy || !task) return;
    DF.say('');
    if (!picker.items.length) return DF.say('กรุณาแนบรูปส่งงานอย่างน้อย 1 รูป');
    busy = true; $('sendBtn').disabled = true;
    // ขึ้นหน้าสำเร็จทันที แล้วส่งข้อมูลต่อเบื้องหลัง (ถ้าส่งไม่ผ่านจะกลับมาหน้าฟอร์มพร้อมรูปเดิมให้กดส่งใหม่)
    const head = `<b>${esc(task.taskCode)}</b><br>`, t0 = Date.now();
    $('formBox').hidden = true; $('doneBox').hidden = false; $('moreBtn').hidden = true; window.scrollTo(0, 0);
    $('doneText').innerHTML = head + 'รับข้อมูลแล้ว กำลังส่งเข้าระบบ…<br><span style="color:var(--muted)">กรุณาเปิดหน้านี้ค้างไว้สักครู่</span>';
    try {
      const d = await DF.submitWithPhotos({ form: FORM, taskCode: task.taskCode, note: $('note').value.trim() }, [picker]);
      const when = `<br><span style="color:var(--muted)">${DF.fmt(d.time)}</span>`;
      $('doneText').innerHTML = head + 'บันทึกแล้ว กำลังส่งรูปที่เหลือ…' + when;
      const ph = await d.photos;
      $('doneText').innerHTML = head + (ph.sent < ph.total ? `บันทึกแล้ว แต่มีรูป ${ph.total - ph.sent} รูปส่งไม่สำเร็จ` : `บันทึกรูปส่งงานจาก ${DEPT} เรียบร้อย`) + when +
        `<br><span style="color:var(--muted);font-size:.8em">ใช้เวลา ${((Date.now() - t0) / 1000).toFixed(1)} วินาที</span>`;
      $('note').value = ''; $('moreBtn').hidden = false;
    } catch (e) {
      $('formBox').hidden = false; $('doneBox').hidden = true;
      DF.say('ส่งข้อมูลไม่สำเร็จ: ' + (e.message || e) + ' กรุณากดส่งอีกครั้ง');
    } finally {
      busy = false; $('sendBtn').disabled = !task; $('sendBtn').textContent = 'ส่งข้อมูล';
    }
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
