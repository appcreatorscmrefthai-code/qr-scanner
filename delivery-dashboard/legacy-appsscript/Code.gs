/**
 * Delivery Plan Dashboard - Apps Script Web App (API)
 * ผูกสคริปต์นี้กับ Google Sheet (Extensions > Apps Script) แล้วรัน setup() หนึ่งครั้ง
 * Deploy > New deployment > Web app > Execute as: Me, Who has access: Anyone
 */
const VERSION = '2026.10.06b';   // รุ่นของ Code.gs (หน้าเว็บใช้ตรวจว่า Deploy รุ่นล่าสุดแล้วหรือยัง)
const CFG = {
  SHEET_ID: '',                    // เว้นว่าง = ใช้ Sheet ที่ผูกกับสคริปต์นี้
  PHOTO_ROOT: 'Delivery_Photos',   // ชื่อโฟลเดอร์เก็บรูปใน Google Drive
  SYNC_KEY: 'CHANGE-ME',           // รหัสสำหรับปุ่ม VBA ส่งแผนจาก Excel
  SESSION_DAYS: 30,                // เข้าสู่ระบบ 1 ครั้งใช้ได้กี่วัน (จอทีวีจะต้องเข้าสู่ระบบใหม่เมื่อครบกำหนด)
  TZ: 'Asia/Bangkok',
  MAX_PICKUP: 20, MAX_ROAD: 5, MAX_UNLOAD: 20,
  REQUIRE_TASK_KEY: true,     // true = ฟอร์มมือถือต้องเปิดจาก QR ที่มีรหัสลับประจำงาน (QR ที่พิมพ์ก่อนรุ่นนี้ต้องพิมพ์ใหม่)
  LOGIN_MAX_FAIL: 5, LOGIN_LOCK_MIN: 15   // ใส่รหัสผิดเกินกี่ครั้ง จะล็อกผู้ใช้นั้นกี่นาที
};

// ลำดับคอลัมน์ตรงกับชีต Plan ใน Excel (A-X) รถ 1 คันส่งได้สูงสุด 3 จุด ช่องที่เป็น "-" ถือว่าว่าง
const PLAN_HEAD = ['Task Code', 'Date', 'Detail', 'Client Name', 'Transport', 'Schedule',
  'Arrival Time 1', 'Arrival Time 2', 'Arrival Time 3', 'ชื่อบริษัทขนส่ง', 'ประเภทรถ', 'ทะเบียนรถ', 'ชื่อผู้ขับ',
  'เบอร์โทรผู้ขับ', 'รอบขนส่ง', 'จุดที่ 1', 'Map1', 'ชื่อ-เบอร์โทรผู้รับ จุดที่ 1', 'จุดที่ 2', 'Map2',
  'ชื่อ-เบอร์โทรผู้รับ จุดที่ 2', 'จุดที่ 3', 'Map3', 'ชื่อ-เบอร์โทรผู้รับ จุดที่ 3', 'Task Status'];   // Task Status = Canceled คืองานยกเลิก
const PICKUP_HEAD = ['Timestamp', 'Task Code', 'หมายเหตุ', 'จำนวนรูป', 'ลิงก์รูป', 'โฟลเดอร์'];
const ROAD_HEAD = ['Timestamp', 'Task Code', 'ประเภท', 'จุดส่ง', 'ทะเบียนรถ', 'ทะเบียนเดิม (ถ้าแก้ไข)', 'หมายเหตุ',
  'คาดว่าจะถึงจุดที่ 1', 'คาดว่าจะถึงจุดที่ 2', 'คาดว่าจะถึงจุดที่ 3', 'จำนวนรูปบนถนน', 'ลิงก์รูปบนถนน',
  'จำนวนรูปลงงาน', 'ลิงก์รูปลงงาน', 'จบงาน', 'โฟลเดอร์'];
const EDIT_HEAD = ['Timestamp', 'Task Code', 'ช่องทาง', 'รายการที่แก้ไข', 'ค่าเดิม', 'ค่าใหม่', 'ผู้แก้ไข'];
// ผู้ใช้ Dashboard : สิทธิ์ edit = ดูและแก้ไขได้, view = ดูได้อย่างเดียว
// พิมพ์รหัสผ่านลงช่อง Password ได้เลย ระบบจะเปลี่ยนเป็นค่าเข้ารหัส (sha256:...) ให้เองเมื่อมีการเข้าสู่ระบบครั้งถัดไป
const USER_HEAD = ['Username', 'Password', 'สิทธิ์ (edit/view)', 'ชื่อที่แสดง', 'ใช้งาน (TRUE/FALSE)'];

// ประเภทรายการใน Road_Log
const TYPE = { checkin: 'เช็คอิน', eta: 'เวลาคาดถึง', road: 'บนถนน', arrive: 'ถึงหน้างาน', unload: 'ลงงานเสร็จ', 'return': 'กลับถึง SCM' };

// ช่องที่แก้ไขได้จาก Popup : ชื่อ -> [คอลัมน์ในชีต Plan, ชนิด, ชื่อที่บันทึกใน Edit_Log]
const FIELDS = {
  detail: [3, 'text', 'Detail'], client: [4, 'text', 'Client Name'], transport: [5, 'text', 'Transport'],
  pickup: [6, 'time', 'Schedule'], arr1: [7, 'time', 'Arrival Time 1'], arr2: [8, 'time', 'Arrival Time 2'],
  arr3: [9, 'time', 'Arrival Time 3'], company: [10, 'text', 'ชื่อบริษัทขนส่ง'], vehicleType: [11, 'text', 'ประเภทรถ'],
  plate: [12, 'plate', 'ทะเบียนรถ'], driver: [13, 'text', 'ชื่อผู้ขับ'], phone: [14, 'text', 'เบอร์โทรผู้ขับ'],
  round: [15, 'text', 'รอบขนส่ง'], stop1: [16, 'text', 'จุดที่ 1'], map1: [17, 'text', 'Map1'],
  rec1: [18, 'text', 'ชื่อ-เบอร์โทรผู้รับ จุดที่ 1'], stop2: [19, 'text', 'จุดที่ 2'], map2: [20, 'text', 'Map2'],
  rec2: [21, 'text', 'ชื่อ-เบอร์โทรผู้รับ จุดที่ 2'], stop3: [22, 'text', 'จุดที่ 3'], map3: [23, 'text', 'Map3'],
  rec3: [24, 'text', 'ชื่อ-เบอร์โทรผู้รับ จุดที่ 3']
};

/* ---------- ติดตั้ง / อัปเกรดโครงชีต (รันซ้ำได้ ข้อมูลเดิมไม่หาย) ---------- */
function setup() {
  const ss = ss_();
  ss.setSpreadsheetTimeZone(CFG.TZ);
  const plan = ensureSheet_(ss, 'Plan', PLAN_HEAD);
  plan.getRange('A:A').setNumberFormat('@');
  plan.getRange('B:B').setNumberFormat('yyyy-mm-dd');
  plan.getRange('F:I').setNumberFormat('HH:mm');
  plan.getRange('L:L').setNumberFormat('@');
  plan.getRange('N:N').setNumberFormat('@');
  ensureSheet_(ss, 'Pickup_Log', PICKUP_HEAD).getRange('A:A').setNumberFormat('yyyy-mm-dd HH:mm:ss');
  const road = ensureSheet_(ss, 'Road_Log', ROAD_HEAD);
  road.getRange('A:A').setNumberFormat('yyyy-mm-dd HH:mm:ss');
  road.getRange('E:F').setNumberFormat('@');
  road.getRange('H:J').setNumberFormat('@');
  ensureSheet_(ss, 'Edit_Log', EDIT_HEAD).getRange('A:A').setNumberFormat('yyyy-mm-dd HH:mm:ss');
  const users = ensureSheet_(ss, 'Users', USER_HEAD);
  users.getRange('A:B').setNumberFormat('@');
  if (users.getLastRow() < 2) {      // ผู้ใช้เริ่มต้น ควรเปลี่ยนรหัสผ่านทันทีโดยพิมพ์รหัสใหม่ทับในช่อง Password
    users.getRange(2, 1, 2, USER_HEAD.length).setValues([['admin', 'scm@1234', 'edit', 'ผู้ดูแลระบบ', true], ['viewer', 'view@1234', 'view', 'จอแสดงผล', true]]);
  }
  // สร้างโฟลเดอร์รูป ขอสิทธิ์ Drive และแชร์โฟลเดอร์หลักแบบดูได้ตามลิงก์
  try { rootFolder_().setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW); } catch (err) { }
}

// ถ้าชีตเดิมมีหัวตารางไม่ตรงกับโครงใหม่และมีข้อมูลอยู่ จะเก็บชีตเดิมไว้เป็นชื่อ <ชื่อ>_old_<วันเวลา> แล้วสร้างชีตใหม่
function ensureSheet_(ss, name, head) {
  let sh = ss.getSheetByName(name);
  if (sh && sh.getLastRow() >= 1) {
    const cur = sh.getRange(1, 1, 1, Math.max(head.length, sh.getLastColumn())).getDisplayValues()[0];
    // หัวตารางเดิมตรงกับส่วนต้นของหัวตารางใหม่ (รุ่นใหม่เพิ่มคอลัมน์ต่อท้าย) = ใช้ชีตเดิมต่อ แค่เติมหัวคอลัมน์ที่ขาด
    const same = head.every(function (h, i) { const c = clean_(cur[i]); return !c ? i > 0 : c === h; });
    if (!same && sh.getLastRow() >= 2) {
      sh.setName(name + '_old_' + Utilities.formatDate(new Date(), CFG.TZ, 'yyyyMMdd_HHmmss'));
      sh = null;
    } else if (!same) {
      sh.clear();
    }
  }
  if (!sh) sh = ss.insertSheet(name);
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
    if (p.action === 'task') { needKey_(p.code, p.k); return { task: taskFull_(p.code) }; }
    if (p.action !== 'task') auth_(p.token, false);          // ฟอร์มคนขับ (task) ไม่ต้องเข้าสู่ระบบ ส่วน Dashboard ต้องเข้าสู่ระบบ
    if (p.action === 'month') return { month: p.month, days: monthSummary_(String(p.month || today_().slice(0, 7))) };
    const date = p.date || today_();
    return { date: date, now: iso_(new Date()), tasks: readPlan_(date) };
  });
}

function doPost(e) {
  return respond_(function () {
    const p = JSON.parse(e.postData.contents);
    if (['upload', 'submit', 'attach', 'warm'].indexOf(p.action) >= 0) needKey_(p.taskCode, p.k);   // ฟอร์มมือถือ: ต้องมีรหัสลับจาก QR
    if (p.action === 'upload') return upload_(p);
    if (p.action === 'submit') return submit_(p);
    if (p.action === 'attach') return attach_(p);
    if (p.action === 'warm') { folderInfo_(p.taskCode); return {}; }   // เตรียมโฟลเดอร์รูปไว้ล่วงหน้า รูปแรกจะส่งเร็วขึ้น
    if (p.action === 'login') return login_(p);
    if (p.action === 'editPlan') return editPlan_(p);
    if (p.action === 'syncPlan') return syncPlan_(p);
    throw new Error('ไม่รู้จักคำสั่ง: ' + p.action);
  });
}

function respond_(fn) {
  let out;
  const t0 = Date.now();
  try { out = Object.assign({ ok: true }, fn()); }
  catch (err) { out = { ok: false, error: String(err && err.message || err) }; }
  out.v = VERSION; out.ms = Date.now() - t0;        // รุ่นของ Code.gs และเวลาที่เซิร์ฟเวอร์ใช้ (มิลลิวินาที) ไว้ตรวจความเร็ว
  return ContentService.createTextOutput(JSON.stringify(out)).setMimeType(ContentService.MimeType.JSON);
}

/* ---------- อ่านแผน + สถานะ ---------- */
// Dashboard: จำผลลัพธ์ของแต่ละวันไว้ 45 วินาที และล้างทันทีเมื่อมีการบันทึกจากฟอร์ม/แก้ไข/ซิงก์
// (ถ้าแก้ชีตด้วยมือโดยตรง Dashboard จะเห็นข้อมูลใหม่ภายในไม่เกิน 45 วินาที)
function readPlan_(date) {
  const cache = CacheService.getScriptCache(), ck = 'plan_' + date + '_' + (cache.get('dv') || '0');
  const hit = cache.get(ck);
  if (hit) return JSON.parse(hit);
  const tasks = planRowsOn_(date);
  if (tasks.length) attachLogs_(tasks);
  tasks.forEach(function (t) { t.key = taskKey_(t.taskCode); });    // ใช้สร้างลิงก์ใน QR (ส่งให้เฉพาะผู้ที่เข้าสู่ระบบแล้ว)
  try { cache.put(ck, JSON.stringify(tasks), 45); } catch (err) { }      // ข้อมูลใหญ่เกินแคชก็ข้ามไป
  return tasks;
}
function touch_() { try { CacheService.getScriptCache().put('dv', String(Date.now()), 21600); } catch (err) { } }

// แถวแผนของวันเดียว: อ่านเฉพาะคอลัมน์วันที่ก่อน แล้วอ่านเต็มเฉพาะช่วงแถวของวันนั้น (ชีต Plan สะสมทุกวัน ไม่ต้องอ่านทั้งชีต)
function planRowsOn_(date) {
  const sh = ss_().getSheetByName('Plan');
  if (!sh || sh.getLastRow() < 2) return [];
  const n = sh.getLastRow() - 1, tz = ss_().getSpreadsheetTimeZone();
  const col = sh.getRange(2, 2, n, 1), v = col.getValues(), d = col.getDisplayValues();
  let lo = -1, hi = -1;
  for (let i = 0; i < n; i++) if (dateStr_(v[i][0], d[i][0], tz) === date) { if (lo < 0) lo = i; hi = i; }
  if (lo < 0) return [];
  const rng = sh.getRange(lo + 2, 1, hi - lo + 1, PLAN_HEAD.length), val = rng.getValues(), disp = rng.getDisplayValues();
  const out = [];
  for (let i = 0; i < val.length; i++) {
    if (!String(val[i][0]).trim()) continue;
    const t = rowTask_(val[i], disp[i], lo + i + 2, tz);
    if (t.date === date) out.push(t);
  }
  return out;
}

// แถว Log ของชุด Task ที่ต้องการ: อ่านเฉพาะคอลัมน์ Task Code ก่อน แล้วอ่านเต็มเฉพาะช่วงแถวที่เกี่ยวข้อง
function logRowsFor_(name, want) {
  const sh = ss_().getSheetByName(name);
  if (!sh || sh.getLastRow() < 2) return [];
  const codes = sh.getRange(2, 2, sh.getLastRow() - 1, 1).getValues();
  let lo = -1, hi = -1;
  for (let i = 0; i < codes.length; i++) if (want[key_(codes[i][0])]) { if (lo < 0) lo = i; hi = i; }
  if (lo < 0) return [];
  return sh.getRange(lo + 2, 1, hi - lo + 1, sh.getLastColumn()).getValues()
    .filter(function (r) { return r[0] && want[key_(r[1])]; });
}

function taskFull_(code, allowCanceled) {
  const t = findTask_(code);
  if (!t) throw new Error('ไม่พบ Task Code: ' + code);
  if (t.canceled && !allowCanceled) throw new Error('งานนี้ถูกยกเลิกแล้ว (' + t.taskCode + ')');     // ฟอร์มมือถือเปิดงานที่ยกเลิกไม่ได้
  // ฟอร์มมือถือ: อ่านเฉพาะแถว Log ของงานนี้ ไม่อ่านทั้งชีต เพื่อให้ตอบกลับเร็วแม้ข้อมูลสะสมมาก
  const k = key_(t.taskCode);
  const pick = taskRows_('Pickup_Log', t.taskCode);
  t.pickupLog = pick.length ? pickLog_(pick[pick.length - 1]) : null;
  t.logs = taskRows_('Road_Log', t.taskCode).map(roadLog_);
  t.state = state_(t);
  return t;
}

// แถว Log ของ Task เดียว ค้นด้วยตัวค้นหาของชีต แล้วอ่านเฉพาะช่วงแถวที่เกี่ยวข้อง
function taskRows_(name, code) {
  const sh = ss_().getSheetByName(name);
  if (!sh || sh.getLastRow() < 2) return [];
  const hits = sh.getRange(2, 2, sh.getLastRow() - 1, 1).createTextFinder(String(code).trim()).matchEntireCell(true).findAll();
  if (!hits.length) return [];
  const rows = hits.map(function (h) { return h.getRow(); });
  const lo = Math.min.apply(null, rows), hi = Math.max.apply(null, rows), k = key_(code);
  return sh.getRange(lo, 1, hi - lo + 1, sh.getLastColumn()).getValues()
    .filter(function (r) { return r[0] && key_(r[1]) === k; });
}

function pickLog_(r) { return { time: iso_(r[0]), note: String(r[2] || ''), photos: ids_(r[4]) }; }
function roadLog_(r) {
  return {
    time: iso_(r[0]), type: typeKey_(r[2]), stop: Number(r[3]) || 0, plate: String(r[4] || ''), oldPlate: String(r[5] || ''),
    note: String(r[6] || ''), eta: [hm_(r[7]), hm_(r[8]), hm_(r[9])], road: ids_(r[11]), unload: ids_(r[13]),
    finish: r[14] === true || String(r[14]).toUpperCase() === 'TRUE'
  };
}

// ใส่ pickupLog, logs และ state ให้แต่ละ Task
function attachLogs_(tasks) {
  const want = {}, pick = {}, road = {};
  tasks.forEach(function (t) { want[key_(t.taskCode)] = true; });
  logRowsFor_('Pickup_Log', want).forEach(function (r) {
    const k = key_(r[1]);
    if (want[k]) pick[k] = pickLog_(r);   // รายการล่าสุด
  });
  logRowsFor_('Road_Log', want).forEach(function (r) {
    const k = key_(r[1]);
    if (!want[k]) return;
    (road[k] = road[k] || []).push(roadLog_(r));
  });
  tasks.forEach(function (t) {
    const k = key_(t.taskCode);
    t.pickupLog = pick[k] || null;
    t.logs = road[k] || [];
    t.state = state_(t);
  });
}

// สรุปสถานะจาก Log : เช็คอิน, ออกรถ, ถึงหน้างาน/ลงงานเสร็จของแต่ละจุด, เวลาที่คาดว่าจะถึง
function state_(t) {
  const n = t.stops.length;
  const s = { checkin: null, depart: t.pickupLog ? t.pickupLog.time : '', arrive: [], done: [], eta: [], lastRoad: '', roadCount: 0, returned: '' };
  for (let i = 0; i < n; i++) { s.arrive.push(''); s.done.push(''); s.eta.push(''); }
  t.logs.forEach(function (l) {
    const i = l.stop - 1;
    if (l.type === 'checkin' && !s.checkin) s.checkin = { time: l.time, plate: l.plate };
    if (l.type === 'road') { s.lastRoad = l.time; s.roadCount++; }
    // เวลาที่คาดว่าจะถึง: บันทึก/แก้ไขแยกจากสถานการณ์บนถนน (ไม่นับเป็นอัปเดตบนถนน) ใช้ค่าล่าสุดของแต่ละจุด
    if (l.type === 'road' || l.type === 'eta') for (let k = 0; k < n; k++) if (l.eta[k]) s.eta[k] = l.eta[k];
    if (l.type === 'return' && !s.returned) s.returned = l.time;
    if (l.type === 'arrive' && i >= 0 && i < n && !s.arrive[i]) s.arrive[i] = l.time;
    if (l.type === 'unload' && i >= 0 && i < n && !s.done[i]) { s.done[i] = l.time; if (!s.arrive[i]) s.arrive[i] = l.time; }
  });
  return s;
}

// สรุปรายวันของเดือน (yyyy-MM) สำหรับหน้าปฏิทิน
// จำผลลัพธ์ไว้ 60 วินาที และล้างทันทีเมื่อมีการบันทึก (หน้านี้ต้องอ่านชีต Plan และ Road_Log ทั้งหมด จึงช้าที่สุดถ้าไม่จำไว้)
function monthSummary_(month) {
  const cache = CacheService.getScriptCache(), ck = 'month_' + month + '_' + (cache.get('dv') || '0');
  const hit = cache.get(ck);
  if (hit) return JSON.parse(hit);
  const days = monthBuild_(month);
  try { cache.put(ck, JSON.stringify(days), 60); } catch (err) { }
  return days;
}
function monthBuild_(month) {
  const byCode = {}, days = {};
  planRows_().forEach(function (t) {
    if (t.date.slice(0, 7) !== month) return;
    const day = days[t.date] = days[t.date] || { total: 0, done: 0, canceled: 0 };
    if (t.canceled) { day.canceled++; return; }             // งานยกเลิก: นับแยก ไม่รวมในจำนวนงานของวัน
    byCode[key_(t.taskCode)] = t.date;
    day.total++;
  });
  const seen = {};
  logRows_('Road_Log').forEach(function (r) {
    const k = key_(r[1]);
    if (!byCode[k] || seen[k]) return;
    if (r[14] === true || String(r[14]).toUpperCase() === 'TRUE') { seen[k] = true; days[byCode[k]].done++; }
  });
  return days;
}

function planRows_() {
  const sh = ss_().getSheetByName('Plan');
  if (!sh || sh.getLastRow() < 2) return [];
  const rng = sh.getRange(2, 1, sh.getLastRow() - 1, PLAN_HEAD.length);
  const val = rng.getValues(), disp = rng.getDisplayValues();
  const tz = ss_().getSpreadsheetTimeZone();
  const out = [];
  for (let i = 0; i < val.length; i++) {
    if (String(val[i][0]).trim()) out.push(rowTask_(val[i], disp[i], i + 2, tz));
  }
  return out;
}

function rowTask_(val, d, row, tz) {
  const code = String(val[0]).trim(), stops = [];
  for (let k = 0; k < 3; k++) {
    const name = blank_(d[15 + 3 * k]);
    if (name) stops.push({ slot: k + 1, name: name, arrival: timeStr_(d[6 + k]), map: blank_(d[16 + 3 * k]), receiver: blank_(d[17 + 3 * k]) });
  }
  // ถ้าไม่ได้กรอกจุดที่ 1-3 ให้ใช้ Detail เป็นจุดส่งเดียว
  if (!stops.length) stops.push({ slot: 1, name: blank_(d[2]) || code, arrival: timeStr_(d[6]), map: '', receiver: '' });
  return {
    row: row, taskCode: code, date: dateStr_(val[1], d[1], tz),
    detail: blank_(d[2]), client: blank_(d[3]), transport: blank_(d[4]), pickup: timeStr_(d[5]),
    company: blank_(d[9]), vehicleType: blank_(d[10]), plate: blank_(d[11]), driver: blank_(d[12]),
    phone: blank_(d[13]), round: blank_(d[14]), roundTrip: /กลับ/.test(d[14]), stops: stops,
    status: blank_(d[24]), canceled: /cancel|ยกเลิก/i.test(String(d[24] || ''))
  };
}

function logRows_(name) {
  const sh = ss_().getSheetByName(name);
  if (!sh || sh.getLastRow() < 2) return [];
  return sh.getRange(2, 1, sh.getLastRow() - 1, sh.getLastColumn()).getValues()
    .filter(function (r) { return r[0] && r[1]; });
}

// หา Task เดียว: ใช้แคช 5 นาที และค้นเฉพาะแถวนั้นด้วยตัวค้นหาของชีต (ไม่อ่านทั้งชีต Plan)
function findTask_(code) {
  const k = key_(code);
  if (!k) return null;
  const cache = CacheService.getScriptCache(), hit = cache.get('task_' + k);
  if (hit) return JSON.parse(hit);
  const sh = ss_().getSheetByName('Plan');
  if (!sh || sh.getLastRow() < 2) return null;
  let t = null;
  const cell = sh.getRange(2, 1, sh.getLastRow() - 1, 1).createTextFinder(String(code).trim()).matchEntireCell(true).findNext();
  if (cell) {
    const rng = sh.getRange(cell.getRow(), 1, 1, PLAN_HEAD.length);
    t = rowTask_(rng.getValues()[0], rng.getDisplayValues()[0], cell.getRow(), ss_().getSpreadsheetTimeZone());
  } else {                                          // เผื่อรหัสในชีตมีช่องว่างหรือตัวพิมพ์ต่างกัน
    t = planRows_().filter(function (x) { return key_(x.taskCode) === k; })[0] || null;
  }
  if (t) cache.put('task_' + k, JSON.stringify(t), 300);
  return t;
}
function forgetTask_(code) { CacheService.getScriptCache().remove('task_' + key_(code)); }

/* ---------- รับรูป (หลายรูปต่อครั้ง) ---------- */
function upload_(p) {
  if (['pickup', 'road', 'unload'].indexOf(p.kind) < 0) throw new Error('ประเภทรูปไม่ถูกต้อง');
  const files = Array.isArray(p.files) ? p.files.slice(0, 6) : [{ data: p.data, index: p.index }];
  const folder = DriveApp.getFolderById(folderInfo_(p.taskCode).id);
  const stamp = Utilities.formatDate(new Date(), CFG.TZ, 'HHmmss');
  const stopTag = p.kind === 'unload' && Number(p.stop) ? '-จุด' + Number(p.stop) : '';
  const ids = files.map(function (f) {
    const name = p.kind + stopTag + '_' + stamp + '_' + (Number(f.index) || 0) + '.jpg';
    // รับเฉพาะไฟล์รูป JPEG ขนาดไม่เกิน ~3 MB ต่อรูป (หน้าเว็บย่อรูปเหลือไม่กี่ร้อย KB อยู่แล้ว)
    if (typeof f.data !== 'string' || f.data.length > 4200000) throw new Error('ไฟล์รูปใหญ่เกินไป');
    const bytes = Utilities.base64Decode(f.data);
    if (bytes.length < 4 || (bytes[0] & 255) !== 0xFF || (bytes[1] & 255) !== 0xD8) throw new Error('รับเฉพาะไฟล์รูปภาพ');
    return folder.createFile(Utilities.newBlob(bytes, 'image/jpeg', name)).getId();
  });
  return { ids: ids, id: ids[0] };
}

/* ---------- รับฟอร์ม ---------- */
function submit_(p) {
  const task = findTask_(p.taskCode);
  if (!task) throw new Error('ไม่พบ Task Code: ' + p.taskCode);
  if (task.canceled) throw new Error('งานนี้ถูกยกเลิกแล้ว (' + task.taskCode + ')');
  const now = new Date(), n = task.stops.length;
  const note = String(p.note || '').slice(0, 2000);
  let fin = false, rowNo = 0;
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const ss = ss_();
    if (p.form === 'pickup') {
      // บันทึกเวลารถออกก่อน รูปจะถูกแนบตามมาด้วยคำสั่ง attach เพื่อให้สถานะขึ้น Dashboard ทันที
      const a = list_(p.photos, CFG.MAX_PICKUP), sh = ss.getSheetByName('Pickup_Log');
      sh.appendRow([now, task.taskCode, note, a.length, urls_(a), '']);
      rowNo = sh.getLastRow();
    } else if (p.form === 'driver') {
      const stop = Number(p.stop) || 0;
      let row;
      if (p.type === 'checkin') {
        const plate = normPlate_(p.plate);
        if (!plate) throw new Error('รูปแบบทะเบียนรถไม่ถูกต้อง ตัวอย่าง: 3 ฒผ 2186');
        const changed = plate !== task.plate;
        if (changed) {
          ss.getSheetByName('Plan').getRange(task.row, FIELDS.plate[0]).setValue(plate);
          forgetTask_(task.taskCode);
          ss.getSheetByName('Edit_Log').appendRow([now, task.taskCode, 'ฟอร์มผู้จัดส่ง (เช็คอิน)', 'ทะเบียนรถ', task.plate, plate, 'ผู้จัดส่ง']);
        }
        row = [now, task.taskCode, TYPE.checkin, '', plate, changed ? (task.plate || '(ว่าง)') : '', note, '', '', '', 0, '', 0, '', false, ''];
      } else if (p.type === 'eta') {
        const eta = [0, 1, 2].map(function (i) { return i < n ? hm_((p.eta || [])[i]) : ''; });
        if (!eta.join('')) throw new Error('กรุณาใส่เวลาที่คาดว่าจะถึงอย่างน้อย 1 จุด');
        const et = eta.map(function (x) { return x ? x + ' น.' : ''; });
        row = [now, task.taskCode, TYPE.eta, '', '', '', note, et[0], et[1], et[2], 0, '', 0, '', false, ''];
      } else if (p.type === 'road') {
        const r = list_(p.road, CFG.MAX_ROAD);
        const eta = [0, 1, 2].map(function (i) { return i < n ? hm_((p.eta || [])[i]) : ''; });
        if (!r.length && !note && !eta.join('')) throw new Error('กรุณาแนบรูป ใส่หมายเหตุ หรือเวลาที่คาดว่าจะถึง');
        const et = eta.map(function (x) { return x ? x + ' น.' : ''; });   // เก็บเป็นข้อความ ไม่ให้ Sheet แปลงเป็นค่าเวลา
        row = [now, task.taskCode, TYPE.road, '', '', '', note, et[0], et[1], et[2], r.length, urls_(r), 0, '', false, ''];
      } else if (p.type === 'arrive' || p.type === 'unload') {
        if (stop < 1 || stop > n) throw new Error('จุดส่งไม่ถูกต้อง');
        const u = p.type === 'unload' ? list_(p.unload, CFG.MAX_UNLOAD) : [];
        fin = p.type === 'unload' && stop === n && !task.roundTrip;   // ลงงานจุดสุดท้าย = จบงาน (งานไป-กลับจบเมื่อรถกลับถึง SCM)
        row = [now, task.taskCode, TYPE[p.type], stop, '', '', note, '', '', '', 0, '', u.length, urls_(u), fin, ''];
      } else if (p.type === 'return') {
        if (!task.roundTrip) throw new Error('งานนี้ไม่ใช่รอบไป-กลับ');
        fin = true;
        row = [now, task.taskCode, TYPE['return'], '', '', '', note, '', '', '', 0, '', 0, '', true, ''];
      } else {
        throw new Error('ไม่รู้จักประเภทรายการ');
      }
      const sh = ss.getSheetByName('Road_Log');
      sh.appendRow(row);
      rowNo = sh.getLastRow();
    } else {
      throw new Error('ไม่รู้จักฟอร์ม');
    }
  } finally { lock.releaseLock(); }
  touch_();
  return { time: iso_(now), taskCode: task.taskCode, finish: fin, row: rowNo, task: p.form === 'driver' && !p.lite ? taskFull_(task.taskCode) : null };
}

/* ---------- แนบรูปเข้ารายการที่บันทึกไปแล้ว (เรียกซ้ำได้ รูปจะถูกเพิ่มต่อท้าย) ---------- */
function attach_(p) {
  const isPick = p.form === 'pickup';
  const sh = ss_().getSheetByName(isPick ? 'Pickup_Log' : 'Road_Log'), row = Number(p.row) || 0;
  if (row < 2 || row > sh.getLastRow()) throw new Error('ไม่พบรายการที่จะแนบรูป');
  const folder = folderInfo_(p.taskCode).url;
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    if (key_(sh.getRange(row, 2).getValue()) !== key_(p.taskCode)) throw new Error('รายการไม่ตรงกับ Task Code');
    // [คอลัมน์จำนวนรูป, รายการรูปที่ส่งมา, จำนวนสูงสุด]
    const sets = isPick ? [[4, p.photos, CFG.MAX_PICKUP]] : [[11, p.road, CFG.MAX_ROAD], [13, p.unload, CFG.MAX_UNLOAD]];
    sets.forEach(function (x) {
      const add = list_(x[1], x[2]);
      if (!add.length) return;
      const cell = sh.getRange(row, x[0], 1, 2), old = ids_(cell.getValues()[0][1]);
      const all = old.concat(add.filter(function (id) { return old.indexOf(id) < 0; })).slice(0, x[2]);
      cell.setValues([[all.length, urls_(all)]]);
    });
    sh.getRange(row, isPick ? 6 : 16).setValue(folder);
  } finally { lock.releaseLock(); }
  touch_();
  return { row: row };
}

/* ---------- แก้ไขข้อมูลแผนจาก Popup บน Dashboard ---------- */
function editPlan_(p) {
  const who = auth_(p.token, true);                         // ต้องเข้าสู่ระบบด้วยผู้ใช้ที่มีสิทธิ์ edit
  const now = new Date(), changes = p.changes || {};
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  let count = 0;
  try {
    const task = findTask_(p.taskCode);
    if (!task) throw new Error('ไม่พบ Task Code: ' + p.taskCode);
    const plan = ss_().getSheetByName('Plan'), log = ss_().getSheetByName('Edit_Log');
    const cur = plan.getRange(task.row, 1, 1, PLAN_HEAD.length).getDisplayValues()[0];
    Object.keys(changes).forEach(function (k) {
      const f = FIELDS[k];
      if (!f) return;
      let v = clean_(changes[k]).slice(0, 500);
      const old = f[1] === 'time' ? timeStr_(cur[f[0] - 1]) : blank_(cur[f[0] - 1]);
      if (f[1] === 'time') { if (v && !hm_(v)) throw new Error(f[2] + ': รูปแบบเวลาไม่ถูกต้อง (ชม.:นาที)'); v = hm_(v); }
      if (f[1] === 'plate' && v) { v = normPlate_(v); if (!v) throw new Error('รูปแบบทะเบียนรถไม่ถูกต้อง ตัวอย่าง: 3 ฒผ 2186'); }
      if (v === old) return;
      plan.getRange(task.row, f[0]).setValue(v);
      forgetTask_(task.taskCode);
      log.appendRow([now, task.taskCode, 'Dashboard (Popup)', f[2], old, v, who.user]);
      count++;
    });
  } finally { lock.releaseLock(); }
  touch_();
  return { count: count, task: taskFull_(p.taskCode, true) };
}

/* ---------- ผู้ใช้และการเข้าสู่ระบบ (ชีต Users) ---------- */
function secret_() {
  const props = PropertiesService.getScriptProperties();
  let s = props.getProperty('AUTH_SECRET');
  if (!s) { s = Utilities.getUuid() + Utilities.getUuid(); props.setProperty('AUTH_SECRET', s); }
  return s;
}
function hash_(user, pw) {
  const bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, secret_() + '|' + key_(user) + '|' + pw, Utilities.Charset.UTF_8);
  return 'sha256:' + bytes.map(function (b) { return ('0' + (b & 255).toString(16)).slice(-2); }).join('');
}
// อ่านผู้ใช้ทั้งหมด ถ้า protect = true จะเปลี่ยนรหัสผ่านที่ยังเป็นข้อความธรรมดาให้เป็นค่าเข้ารหัสในชีต
function users_(protect) {
  const sh = ss_().getSheetByName('Users');
  if (!sh || sh.getLastRow() < 2) return [];
  const rows = sh.getRange(2, 1, sh.getLastRow() - 1, USER_HEAD.length).getValues();
  return rows.map(function (r, i) {
    const user = clean_(r[0]);
    let pw = String(r[1] == null ? '' : r[1]);
    if (user && pw && pw.indexOf('sha256:') !== 0) {
      pw = hash_(user, pw);
      if (protect) sh.getRange(i + 2, 2).setValue(pw);
    }
    return { user: user, pw: pw, role: clean_(r[2]).toLowerCase() === 'edit' ? 'edit' : 'view', name: clean_(r[3]) || user,
      active: !(r[4] === false || String(r[4]).toUpperCase() === 'FALSE') };
  }).filter(function (u) { return u.user; });
}
function sign_(payload) {
  return Utilities.base64EncodeWebSafe(Utilities.computeHmacSha256Signature(payload, secret_()));
}
// รหัสลับประจำงาน: คำนวณจาก Task Code กับค่าลับของระบบ (ไม่ต้องเก็บในชีต) เดาจาก Task Code ไม่ได้
function taskKey_(code) { return sign_('task|' + key_(code)).replace(/[^A-Za-z0-9]/g, '').slice(0, 10); }
function needKey_(code, k) {
  if (CFG.REQUIRE_TASK_KEY && (!key_(code) || String(k || '') !== taskKey_(code))) throw new Error('ลิงก์ไม่ถูกต้องหรือเป็น QR รุ่นเก่า กรุณาสแกน QR ประจำงานใบใหม่');
}
function login_(p) {
  const name = key_(p.user), pw = String(p.password || '');
  // กันการเดารหัสผ่าน: ผิดเกินกำหนดจะล็อกผู้ใช้นั้นชั่วคราว
  const cache = CacheService.getScriptCache(), fk = 'lf_' + name.slice(0, 60), fails = Number(cache.get(fk)) || 0;
  if (fails >= (CFG.LOGIN_MAX_FAIL || 5)) throw new Error('ใส่รหัสผิดหลายครั้ง กรุณารอ ' + (CFG.LOGIN_LOCK_MIN || 15) + ' นาทีแล้วลองใหม่');
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  let u;
  try { u = users_(true).filter(function (x) { return key_(x.user) === name; })[0]; } finally { lock.releaseLock(); }
  if (!name || !pw || !u || !u.active || u.pw !== hash_(u.user, pw)) { cache.put(fk, String(fails + 1), (CFG.LOGIN_LOCK_MIN || 15) * 60); Utilities.sleep(800); throw new Error('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'); }
  const exp = Date.now() + (CFG.SESSION_DAYS || 30) * 86400e3;
  const payload = Utilities.base64EncodeWebSafe(u.user + '|' + u.role + '|' + exp, Utilities.Charset.UTF_8);
  cache.remove(fk);
  return { token: payload + '.' + sign_(payload), user: u.user, name: u.name, role: u.role, weak: pw === 'scm@1234' || pw === 'view@1234' };
}
// ตรวจการเข้าสู่ระบบ : ไม่ผ่าน = AUTH, ไม่มีสิทธิ์แก้ไข = FORBIDDEN
function auth_(token, needEdit) {
  const part = String(token || '').split('.');
  if (part.length !== 2 || sign_(part[0]) !== part[1]) throw new Error('AUTH');
  const f = Utilities.newBlob(Utilities.base64DecodeWebSafe(part[0])).getDataAsString().split('|');
  if (!(Number(f[2]) > Date.now())) throw new Error('AUTH');
  if (!needEdit) return { user: f[0], role: f[1] };
  // สิทธิ์แก้ไขตรวจกับชีต Users ทุกครั้ง เพื่อให้การถอนสิทธิ์มีผลทันที
  const u = users_(false).filter(function (x) { return key_(x.user) === key_(f[0]); })[0];
  if (!u || !u.active) throw new Error('AUTH');
  if (u.role !== 'edit') throw new Error('FORBIDDEN');
  return { user: u.user, role: u.role };
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
    rows.forEach(function (r) { incoming[key_(r[0])] = true; forgetTask_(r[0]); });
    const last = sh.getLastRow();
    if (last >= 2) {
      const codes = sh.getRange(2, 1, last - 1, 1).getValues();
      for (let i = codes.length - 1; i >= 0; i--) if (incoming[key_(codes[i][0])]) sh.deleteRow(i + 2);
    }
    sh.getRange(sh.getLastRow() + 1, 1, rows.length, PLAN_HEAD.length).setValues(rows);
  } finally { lock.releaseLock(); }
  touch_();
  return { count: rows.length };
}

/* ---------- โฟลเดอร์รูป: Delivery_Photos / วันที่ / Task Code ----------
   จำ id โฟลเดอร์ไว้ในแคช 6 ชม. เพื่อให้การอัปโหลดรูปแต่ละครั้งไม่ต้องอ่านชีตและค้นโฟลเดอร์ซ้ำ */
function rootFolder_() {
  const props = PropertiesService.getScriptProperties();
  const id = props.getProperty('PHOTO_ROOT_ID');
  if (id) { try { return DriveApp.getFolderById(id); } catch (err) { } }
  const f = DriveApp.createFolder(CFG.PHOTO_ROOT);
  // แชร์ที่โฟลเดอร์หลักครั้งเดียว รูปทุกงานเปิดดูได้ตามลิงก์ ไม่ต้องตั้งสิทธิ์ทีละงานหรือทีละรูป
  try { f.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW); } catch (err) { }
  props.setProperty('PHOTO_ROOT_ID', f.getId());
  return f;
}

function folderInfo_(code, task) {
  const cache = CacheService.getScriptCache(), ck = 'fld_' + key_(code);
  const hit = cache.get(ck);
  if (hit) return JSON.parse(hit);
  task = task || findTask_(code);
  if (!task) throw new Error('ไม่พบ Task Code: ' + code);
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  let info;
  try {
    const f = child_(child_(rootFolder_(), task.date || 'no-date'), task.taskCode);
    info = { id: f.getId(), url: f.getUrl() };
  } finally { lock.releaseLock(); }
  cache.put(ck, JSON.stringify(info), 21600);
  return info;
}

function child_(parent, name) {
  const it = parent.getFoldersByName(name);
  return it.hasNext() ? it.next() : parent.createFolder(name);
}

/* ---------- ตัวช่วย ---------- */
function key_(v) { return String(v == null ? '' : v).trim().toUpperCase(); }
function clean_(v) { return String(v == null ? '' : v).replace(/\s+/g, ' ').trim(); }
function blank_(v) { const s = clean_(v); return s === '-' ? '' : s; }
function today_() { return Utilities.formatDate(new Date(), CFG.TZ, 'yyyy-MM-dd'); }
function iso_(d) { return d instanceof Date ? Utilities.formatDate(d, CFG.TZ, "yyyy-MM-dd'T'HH:mm:ssXXX") : ''; }
function typeKey_(v) {
  const s = clean_(v);
  for (const k in TYPE) if (TYPE[k] === s) return k;
  return '';
}
// เวลาแบบ HH:mm (รับ 9:05, 09.05) ถ้าไม่ใช่เวลาคืนค่าว่าง
function hm_(v) {
  if (v instanceof Date) return Utilities.formatDate(v, CFG.TZ, 'HH:mm');
  const m = clean_(v).match(/^(\d{1,2})[:.](\d{2})(\s*น\.?)?$/);
  if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) return '';
  return pad_(m[1]) + ':' + m[2];
}
// ทะเบียนรถรูปแบบเดียวกับในระบบ: "3 ฒผ 2186", "ฒผ 2186" หรือ "70-1234"
function normPlate_(v) {
  const s = clean_(v);
  let m = s.match(/^(\d)?\s*([ก-ฮ]{2,3})\s*(\d{1,4})$/);
  if (m) return (m[1] ? m[1] + ' ' : '') + m[2] + ' ' + m[3];
  m = s.match(/^(\d{2})\s*-\s*(\d{4})$/);
  return m ? m[1] + '-' + m[2] : '';
}
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
