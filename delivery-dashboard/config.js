// ตั้งค่ากลาง ใช้ร่วมกันทุกหน้า (dashboard / pickup / road / qr)
window.APP_CONFIG = {
  // วาง URL ของ Apps Script Web App (ลงท้ายด้วย /exec) ถ้าเว้นว่าง = โหมดตัวอย่าง ไม่บันทึกข้อมูล
  API_URL: 'https://script.google.com/macros/s/AKfycbzboACRlDSeYjT7nohNOnPKVSW0QHVrjQ-x7hs9GSNq7BnKkUy-HPtmR6lfINS_KoZO/exec',

  ORIGIN: 'SCM',            // ชื่อต้นทางที่แสดงหลัง Pickup Time
  PER_PAGE: 5,              // จำนวนคันต่อหน้า
  REFRESH_SEC: 60,          // ดึงข้อมูลใหม่ทุกกี่วินาที
  ROTATE_SEC: 90,           // สลับหน้าอัตโนมัติทุกกี่วินาที (เมื่อมีมากกว่า 1 หน้า)
  NO_ROAD_UPDATE_MIN: 60    // รถออกแล้วเกินกี่นาทียังไม่มีอัปเดตบนถนน = ล่าช้า
};
