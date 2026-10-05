// ตั้งค่ากลาง ใช้ร่วมกันทุกหน้า (dashboard / pickup / road / qr)
window.APP_CONFIG = {
  // วาง URL ของ Apps Script Web App (ลงท้ายด้วย /exec) ถ้าเว้นว่าง = โหมดตัวอย่าง ไม่บันทึกข้อมูล
  API_URL: 'https://script.google.com/macros/s/AKfycbzboACRlDSeYjT7nohNOnPKVSW0QHVrjQ-x7hs9GSNq7BnKkUy-HPtmR6lfINS_KoZO/exec',

  ORIGIN: 'SCM',            // ชื่อต้นทางที่แสดงหลัง Pickup Time
  PER_PAGE: 5,              // จำนวนคันต่อหน้า
  REFRESH_SEC: 60,          // ดึงข้อมูลใหม่ทุกกี่วินาที
  ROTATE_SEC: 90,           // สลับหน้าอัตโนมัติทุกกี่วินาที (เมื่อมีมากกว่า 1 หน้า)
  CHECKIN_LATE_MIN: 10,     // เลยตารางเวลาเกินกี่นาทีแล้วรถยังไม่เช็คอิน = Follow (กรอบเหลือง)
  NO_ROAD_UPDATE_MIN: 60,   // รถออกแล้วเกินกี่นาทียังไม่มีอัปเดตบนถนน = Follow (กรอบเหลือง)
  FOLLOW_REPEAT: false,     // true = เตือน Follow ซ้ำทุกครั้งที่เงียบเกินเวลา, false = เตือนเฉพาะช่วงก่อนอัปเดตแรก

  // คำอธิบายวิธีใช้บนใบ QR (หน้า qr.html) พิมพ์ทีละบรรทัดในเครื่องหมาย ' ' คั่นด้วยจุลภาค ถ้าเว้นว่างจะเป็นพื้นที่ว่างให้เขียนเอง
  QR_HELP_DRIVER: ['1. สแกน QR ด้วย Line', '2. กดลิงค์เข้าไปที่หน้ากรอกข้อมูล', '3. กรอกข้อมูล'],
  QR_HELP_LOADER: [],
  // รายการเอกสารในตารางของรายงานคนขับ (แต่ละจุดส่งมีตาราง 1 ชุด)
  QR_DOCS: ['PACKING SLIP / DELIVERY ORDER', 'TAX INVOICE ________________', 'BILLING NOTE', 'RECEIPT', 'PO. CUSTOMER', 'ใบส่งสินค้าชั่วคราว']
};
