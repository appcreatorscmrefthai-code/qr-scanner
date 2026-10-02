/**
 * Delivery Plan Dashboard - Apps Script Web App (API)
 * ผูกสคริปต์นี้กับ Google Sheet (Extensions > Apps Script) แล้วรัน setup() หนึ่งครั้ง
 * Deploy > New deployment > Web app > Execute as: Me, Who has access: Anyone
 */
const CFG = {
  SHEET_ID: '',                    // เว้นว่าง = ใช้ Sheet ที่ผูกกับสคริปต์นี้
  PHOTO_ROOT: 'Delivery_Photos',   // ชื่อโฟลเดอร์เก็บรูปใน Google Drive
  SYNC_KEY: 'CHANGE-ME',           // รหัสสำหรับปุ่ม VBA ส่งแผนจาก Excel (ใช้ในขั้นตอนถัดไป)
  TZ: 'Asia/Bangkok',
  MAX_PICKUP: 20, MAX_ROAD: 5, MAX_UNLOAD: 20
};

const PLAN_HEAD = ['Task Code', 'Date', 'Detail', 'Client Name', 'Transport', 'Pickup Time',
  'Arrival Time', 'ชื่อบริษัทขนส่ง', 'ชื่อผู้ขับ', 'เบอร์โทรผู้ขับ'];
const PICKUP_HEAD = ['Timestamp', 'Task Code', 'หมายเหตุ', 'จำนวนรูป', 'ลิงก์รูป', 'โฟลเดอร์'];
const ROAD_HEAD = ['Timestamp', 'Task Code', 'หมายเหตุ', 'จำนวนรูปบนถนน', 'ลิงก์รูปบนถนน',
  'จำนวนรูปลงงาน', 'ลิงก์รูปลงงาน', 'จบงาน', 'โฟลเดอร์'];

/* ---------- ติดตั้งครั้งแรก ---------- */
function setup() {
  const ss = ss_();
  ss.setSpreadsheetTimeZone(CFG.TZ);
  const plan = ensureSheet_(ss, 'Plan', PLAN_HEAD);
  plan.getRange('A:A').setNumberFormat('@');
  plan.getRange('B:B').setNumberFormat('yyyy-mm-dd');
  plan.getRange('F:G').setNumberFormat('HH:mm');
  plan.getRange('J:J').setNumberFormat('@');
  ensureSheet_(ss, 'Pickup_Log', PICKUP_HEAD).getRange('A:A').setNumberFormat('yyyy-mm-dd HH:mm:ss');
  ensureSheet_(ss, 'Road_Log', ROAD_HEAD).getRange('A:A').setNumberFormat('yyyy-mm-dd HH:mm:ss');
  rootFolder_();   // สร้างโฟลเดอร์รูป และขอสิทธิ์ Drive
}

function ensureSheet_(ss, name, head) {
  const sh = ss.getSheetByName(name) || ss.insertSheet(name);
  sh.getRange(1, 1, 1, head.length).setValues([head]).setFontWeight('bold');
  sh.setFrozenRows(1);
  return sh;
}

function ss_() {
  return CFG.SHEET_ID ? SpreadsheetApp.openById(CFG.SHEET_ID) : SpreadsheetApp.getActiveSpreadsheet();
}

/* ---------- Web App ---------- */
function doGet(e) {
  return respond_(function () {
    const p = (e && e.parameter) || {};
    if (p.action === 'task') {
      const t = findTask_(p.code);
      if (!t) throw new Error('ไม่พบ Task Code: ' + p.code);
      return { task: t };
    }
    const date = p.date || today_();
    return { date: date, now: iso_(new Date()), tasks: readPlan_(date) };
  });
}

function doPost(e) {
  return respond_(function () {
    const p = JSON.parse(e.postData.contents);
    if (p.action === 'upload') return upload_(p);
    if (p.action === 'submit') return submit_(p);
    if (p.action === 'syncPlan') return syncPlan_(p);
    throw new Error('ไม่รู้จักคำสั่ง: ' + p.action);
  });
}

function respond_(fn) {
  let out;
  try { out = Object.assign({ ok: true }, fn()); }
  catch (err) { out = { ok: false, error: String(err && err.message || err) }; }
  return ContentService.createTextOutput(JSON.stringify(out)).setMimeType(ContentService.MimeType.JSON);
}

/* ---------- อ่านแผน + สถานะ ---------- */
function readPlan_(date) {
  const tasks = planRows_().filter(function (t) { return t.date === date; });
  if (!tasks.length) return tasks;
  const pick = {}, road = {};
  logRows_('Pickup_Log').forEach(function (r) {
    // เก็บรายการล่าสุดของแต่ละ Task
    pick[key_(r[1])] = { time: iso_(r[0]), note: String(r[2] || ''), photos: ids_(r[4]) };
  });
  logRows_('Road_Log').forEach(function (r) {
    const k = key_(r[1]);
    (road[k] = road[k] || []).push({
      time: iso_(r[0]), note: String(r[2] || ''), road: ids_(r[4]), unload: ids_(r[6]),
      finish: r[7] === true || String(r[7]).toUpperCase() === 'TRUE'
    });
  });
  tasks.forEach(function (t) {
    const k = key_(t.taskCode);
    t.pickupLog = pick[k] || null;
    t.roadLogs = road[k] || [];
  });
  return tasks;
}

function planRows_() {
  const sh = ss_().getSheetByName('Plan');
  if (!sh || sh.getLastRow() < 2) return [];
  const rng = sh.getRange(2, 1, sh.getLastRow() - 1, PLAN_HEAD.length);
  const val = rng.getValues(), disp = rng.getDisplayValues();
  const tz = ss_().getSpreadsheetTimeZone();
  const out = [];
  for (let i = 0; i < val.length; i++) {
    const code = String(val[i][0]).trim();
    if (!code) continue;
    out.push({
      taskCode: code,
      date: dateStr_(val[i][1], disp[i][1], tz),
      detail: clean_(disp[i][2]), client: clean_(disp[i][3]), transport: clean_(disp[i][4]),
      pickup: timeStr_(disp[i][5]), arrival: timeStr_(disp[i][6]),
      company: clean_(disp[i][7]), driver: clean_(disp[i][8]), phone: clean_(disp[i][9])
    });
  }
  return out;
}

function logRows_(name) {
  const sh = ss_().getSheetByName(name);
  if (!sh || sh.getLastRow() < 2) return [];
  return sh.getRange(2, 1, sh.getLastRow() - 1, sh.getLastColumn()).getValues()
    .filter(function (r) { return r[0] && r[1]; });
}

function findTask_(code) {
  const k = key_(code);
  if (!k) return null;
  const hit = planRows_().filter(function (t) { return key_(t.taskCode) === k; });
  return hit.length ? hit[0] : null;
}

/* ---------- รับรูป ---------- */
function upload_(p) {
  const task = findTask_(p.taskCode);
  if (!task) throw new Error('ไม่พบ Task Code: ' + p.taskCode);
  if (['pickup', 'road', 'unload'].indexOf(p.kind) < 0) throw new Error('ประเภทรูปไม่ถูกต้อง');
  if (!/^image\//.test(String(p.mime))) throw new Error('รับเฉพาะไฟล์รูปภาพ');
  const stamp = Utilities.formatDate(new Date(), CFG.TZ, 'HHmmss');
  const name = p.kind + '_' + stamp + '_' + (Number(p.index) || 0) + '.jpg';
  const blob = Utilities.newBlob(Utilities.base64Decode(p.data), p.mime, name);
  const file = taskFolder_(task).createFile(blob);
  try { file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW); } catch (err) { }
  return { id: file.getId() };
}

/* ---------- รับฟอร์ม ---------- */
function submit_(p) {
  const task = findTask_(p.taskCode);
  if (!task) throw new Error('ไม่พบ Task Code: ' + p.taskCode);
  const now = new Date();
  const note = String(p.note || '').slice(0, 2000);
  const folder = taskFolder_(task).getUrl();
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    if (p.form === 'pickup') {
      const a = list_(p.photos, CFG.MAX_PICKUP);
      if (!a.length) throw new Error('กรุณาแนบรูปส่งงานอย่างน้อย 1 รูป');
      ss_().getSheetByName('Pickup_Log').appendRow([now, task.taskCode, note, a.length, urls_(a), folder]);
    } else if (p.form === 'road') {
      const r = list_(p.road, CFG.MAX_ROAD), u = list_(p.unload, CFG.MAX_UNLOAD);
      const fin = p.finish === true;
      if (!fin && !r.length && !note) throw new Error('กรุณาแนบรูปหรือใส่หมายเหตุ');
      ss_().getSheetByName('Road_Log').appendRow(
        [now, task.taskCode, note, r.length, urls_(r), u.length, urls_(u), fin, folder]);
    } else {
      throw new Error('ไม่รู้จักฟอร์ม');
    }
  } finally { lock.releaseLock(); }
  return { time: iso_(now), taskCode: task.taskCode };
}

/* ---------- รับแผนจาก Excel (ปุ่ม VBA) : เพิ่ม/แทนที่ตาม Task Code ---------- */
function syncPlan_(p) {
  if (!CFG.SYNC_KEY || CFG.SYNC_KEY === 'CHANGE-ME' || p.key !== CFG.SYNC_KEY) throw new Error('รหัสไม่ถูกต้อง');
  const rows = (p.rows || []).filter(function (r) { return r && String(r[0] || '').trim(); })
    .map(function (r) { const a = r.slice(0, PLAN_HEAD.length); while (a.length < PLAN_HEAD.length) a.push(''); return a; });
  if (!rows.length) throw new Error('ไม่มีข้อมูล');
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const sh = ss_().getSheetByName('Plan');
    const incoming = {};
    rows.forEach(function (r) { incoming[key_(r[0])] = true; });
    const last = sh.getLastRow();
    if (last >= 2) {
      const codes = sh.getRange(2, 1, last - 1, 1).getValues();
      for (let i = codes.length - 1; i >= 0; i--) if (incoming[key_(codes[i][0])]) sh.deleteRow(i + 2);
    }
    sh.getRange(sh.getLastRow() + 1, 1, rows.length, PLAN_HEAD.length).setValues(rows);
  } finally { lock.releaseLock(); }
  return { count: rows.length };
}

/* ---------- โฟลเดอร์รูป: Delivery_Photos / วันที่ / Task Code ---------- */
function rootFolder_() {
  const props = PropertiesService.getScriptProperties();
  const id = props.getProperty('PHOTO_ROOT_ID');
  if (id) { try { return DriveApp.getFolderById(id); } catch (err) { } }
  const f = DriveApp.createFolder(CFG.PHOTO_ROOT);
  props.setProperty('PHOTO_ROOT_ID', f.getId());
  return f;
}

function taskFolder_(task) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    return child_(child_(rootFolder_(), task.date || 'no-date'), task.taskCode);
  } finally { lock.releaseLock(); }
}

function child_(parent, name) {
  const it = parent.getFoldersByName(name);
  return it.hasNext() ? it.next() : parent.createFolder(name);
}

/* ---------- ตัวช่วย ---------- */
function key_(v) { return String(v == null ? '' : v).trim().toUpperCase(); }
function clean_(v) { return String(v == null ? '' : v).replace(/\s+/g, ' ').trim(); }
function today_() { return Utilities.formatDate(new Date(), CFG.TZ, 'yyyy-MM-dd'); }
function iso_(d) { return d instanceof Date ? Utilities.formatDate(d, CFG.TZ, "yyyy-MM-dd'T'HH:mm:ssXXX") : ''; }
function list_(a, max) {
  return (Array.isArray(a) ? a : []).map(String).filter(function (s) { return /^[\w-]{10,}$/.test(s); }).slice(0, max);
}
function urls_(ids) {
  return ids.map(function (id) { return 'https://drive.google.com/file/d/' + id + '/view'; }).join('\n');
}
function ids_(cell) {
  const out = [], re = /\/d\/([\w-]+)/g; let m;
  while ((m = re.exec(String(cell || '')))) out.push(m[1]);
  return out;
}
function dateStr_(v, disp, tz) {
  if (v instanceof Date) return Utilities.formatDate(v, tz, 'yyyy-MM-dd');
  const s = String(disp || '').trim();
  let m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (m) return m[1] + '-' + pad_(m[2]) + '-' + pad_(m[3]);
  m = s.match(/^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})/);     // วัน/เดือน/ปี
  if (m) { let y = Number(m[3]); if (y > 2400) y -= 543; return y + '-' + pad_(m[2]) + '-' + pad_(m[1]); }
  return s;
}
function timeStr_(disp) {
  const m = String(disp || '').match(/(\d{1,2})[:.](\d{2})/);
  if (!m) return '';
  let h = Number(m[1]);
  if (/pm/i.test(disp) && h < 12) h += 12;
  if (/am/i.test(disp) && h === 12) h = 0;
  return pad_(h) + ':' + m[2];
}
function pad_(n) { return ('0' + n).slice(-2); }
