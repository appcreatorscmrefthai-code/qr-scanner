// =============================================================================
//  ส่งข้อมูล PD number (ชีต "Dashboard") และ Released products (ชีต "Master Product")
//  จาก Google Sheet ขึ้น Supabase
//  (ใช้ค้นหาตอนสแกนในเว็บแจ้งแก้ไข BOM)  แถวที่มีอยู่แล้วอัปเดตเป็นค่าล่าสุด แถวใหม่เพิ่มเข้าไป
//  ใช้โค้ดเดียวกันได้ทั้ง 2 ไฟล์ ถ้า 2 ชีตนี้อยู่คนละ Google Sheet: แต่ละไฟล์จะส่งเฉพาะชีตที่ตัวเองมี
//
//  ตั้งค่าครั้งแรก
//   1) Apps Script ของ Google Sheet นี้ > เพิ่มไฟล์ใหม่ชื่อ SupabaseSync > วางโค้ดนี้ทั้งหมด > Save
//   2) Project Settings (รูปเฟือง) > Script properties > เพิ่ม 2 ค่า
//        SB_EMAIL    = อีเมลผู้ใช้ Supabase ที่มีสิทธิ์ Admin ในระบบแจ้งแก้ไข BOM (ชื่อผู้ใช้สั้น เช่น pu ให้ใส่ pu@bomc.local)
//        SB_PASSWORD = รหัสผ่านของผู้ใช้นั้น
//   3) เลือกฟังก์ชัน setupSupabaseSync > Run (อนุญาตสิทธิ์) — จะส่งข้อมูลทันที 1 รอบ
//      และตั้งให้ส่งอัตโนมัติทุก 1 ชั่วโมง + เพิ่มเมนู "Supabase" บน Google Sheet
// =============================================================================

const SB_URL = "https://vmpcfiefryvfovqjhewy.supabase.co";
const SB_KEY = "sb_publishable_ZizU3_OdW6cOrouQXo7JsA_cYCySG9H";
const SB_BATCH = 2000;
const SB_SYNC_EVERY_HOURS = 1; // ส่งอัตโนมัติทุกกี่ชั่วโมง

// sheets = ชื่อชีตที่ใช้ได้ (ใช้ชีตแรกที่เจอในไฟล์)   required = คอลัมน์ที่ต้องมี
const SB_JOBS = [
  {
    label: "PD number", sheets: ["Dashboard", "PD number"], table: "bomc_pd_number", key: "qr",
    cols: { "QR": "qr", "PD number": "pd_number", "FG Model": "fg_model", "FG Type": "fg_type", "Item number": "item_number" },
    required: ["QR", "PD number", "FG Model"],
  },
  {
    label: "Released products", sheets: ["Master Product", "Released products"], table: "bomc_released_products", key: "qr_code",
    cols: { "QR code": "qr_code", "Item number": "item_number", "Product name": "product_name", "BOM unit": "bom_unit" },
    required: ["QR code", "Product name"],
  },
];

// ---------- รันครั้งเดียว: ตั้งเวลาอัตโนมัติ + เมนู แล้วส่งข้อมูลทันที ----------
function setupSupabaseSync() {
  ScriptApp.getProjectTriggers()
    .filter((t) => ["syncMasterToSupabase", "sbOnOpen"].indexOf(t.getHandlerFunction()) >= 0)
    .forEach((t) => ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger("syncMasterToSupabase").timeBased().everyHours(SB_SYNC_EVERY_HOURS).create();
  ScriptApp.newTrigger("sbOnOpen").forSpreadsheet(SpreadsheetApp.getActive()).onOpen().create();
  syncMasterToSupabase();
}

function sbOnOpen() {
  SpreadsheetApp.getUi().createMenu("Supabase")
    .addItem("ส่ง PD number / Released products ขึ้นระบบตอนนี้", "syncMasterToSupabase")
    .addToUi();
}

// ---------- ส่งข้อมูลทั้ง 2 ชีต ----------
function syncMasterToSupabase() {
  const ss = SpreadsheetApp.getActive();
  const token = sbLogin_();
  const done = [];

  SB_JOBS.forEach((job) => {
    const name = job.sheets.find((n) => ss.getSheetByName(n));
    if (!name) return; // ชีตนี้อยู่ใน Google Sheet อีกไฟล์
    const values = ss.getSheetByName(name).getDataRange().getDisplayValues();

    // หาแถวหัวตาราง (แถวที่มีคอลัมน์รหัส QR) ภายใน 10 แถวแรก
    const keyHead = Object.keys(job.cols).find((h) => job.cols[h] === job.key);
    const norm = (v) => String(v).trim().toLowerCase();
    let headRow = -1;
    for (let r = 0; r < Math.min(10, values.length); r++) {
      if (values[r].map(norm).indexOf(norm(keyHead)) >= 0) { headRow = r; break; }
    }
    const head = headRow >= 0 ? values[headRow].map(norm) : [];
    const missing = job.required.filter((h) => head.indexOf(norm(h)) < 0);
    if (missing.length) {
      throw new Error('ชีต "' + name + '" ไม่พบคอลัมน์: ' + missing.join(", ") +
        (headRow >= 0 ? "  (หัวตารางที่เจอ: " + values[headRow].filter(String).join(" | ") + ")" : ""));
    }
    const fields = Object.keys(job.cols).map((h) => ({ field: job.cols[h], col: head.indexOf(norm(h)) }));
    const keyCol = head.indexOf(norm(keyHead));

    // รหัส QR ซ้ำในชีต ใช้แถวล่างสุด
    const byKey = new Map();
    for (let r = headRow + 1; r < values.length; r++) {
      const key = String(values[r][keyCol]).trim();
      if (!key) continue;
      const row = {};
      fields.forEach((f) => {
        const v = f.col >= 0 ? String(values[r][f.col]).trim() : "";
        row[f.field] = v || null;
      });
      row[job.key] = key;
      byKey.set(key, row);
    }
    const rows = Array.from(byKey.values());

    for (let i = 0; i < rows.length; i += SB_BATCH) {
      const res = UrlFetchApp.fetch(SB_URL + "/rest/v1/" + job.table + "?on_conflict=" + job.key, {
        method: "post",
        contentType: "application/json",
        headers: {
          apikey: SB_KEY,
          Authorization: "Bearer " + token,
          Prefer: "resolution=merge-duplicates,return=minimal",
        },
        payload: JSON.stringify(rows.slice(i, i + SB_BATCH)),
        muteHttpExceptions: true,
      });
      if (res.getResponseCode() >= 300) {
        throw new Error("ส่ง " + job.label + " ไม่สำเร็จ (HTTP " + res.getResponseCode() + "): " +
          res.getContentText().slice(0, 300));
      }
    }
    done.push(job.label + " (ชีต " + name + "): " + rows.length + " แถว");
  });

  if (!done.length) throw new Error('ไม่พบชีต "Dashboard" หรือ "Master Product" ในไฟล์นี้');
  const msg = "ส่งขึ้น Supabase แล้ว — " + done.join(", ");
  console.log(msg);
  try { ss.toast(msg, "Supabase", 8); } catch (e) { /* รันจากตัวตั้งเวลา ไม่มีหน้าจอ */ }
}

function sbLogin_() {
  const p = PropertiesService.getScriptProperties();
  const email = p.getProperty("SB_EMAIL");
  const password = p.getProperty("SB_PASSWORD");
  if (!email || !password) throw new Error("ยังไม่ได้ตั้งค่า SB_EMAIL / SB_PASSWORD ใน Script properties");
  const res = UrlFetchApp.fetch(SB_URL + "/auth/v1/token?grant_type=password", {
    method: "post",
    contentType: "application/json",
    headers: { apikey: SB_KEY },
    payload: JSON.stringify({ email: email, password: password }),
    muteHttpExceptions: true,
  });
  if (res.getResponseCode() !== 200) {
    throw new Error("เข้าสู่ระบบ Supabase ไม่สำเร็จ (ตรวจ SB_EMAIL / SB_PASSWORD): " + res.getContentText().slice(0, 200));
  }
  return JSON.parse(res.getContentText()).access_token;
}
