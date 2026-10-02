# Delivery Plan Dashboard

## ไฟล์
| ไฟล์ | หน้าที่ |
|---|---|
| `dashboard.html` | หน้า Dashboard (ทีวี / จอคอม / มือถือ) |
| `pickup.html` | ฟอร์มอัปรูปส่งงาน |
| `road.html` | ฟอร์มอัปเดตสถานการณ์รถบนถนน + จบงาน |
| `qr.html` | QR เข้าฟอร์มทั้ง 2 ใบ สำหรับพิมพ์ |
| `config.js` | ตั้งค่ากลาง (ใส่ `API_URL` ที่นี่ที่เดียว) |
| `form.js`, `form.css` | ส่วนที่ฟอร์มทั้งสองใช้ร่วมกัน |
| `apps-script/Code.gs` | API ฝั่ง Google (ไม่ต้องอัปขึ้น GitHub) |

## ติดตั้ง
1. สร้าง Google Sheet ใหม่ > Extensions > Apps Script > วางโค้ดจาก `apps-script/Code.gs` > Save
2. เลือกฟังก์ชัน `setup` แล้วกด Run (อนุญาตสิทธิ์ Sheet และ Drive) จะได้ชีต `Plan`, `Pickup_Log`, `Road_Log` และโฟลเดอร์ `Delivery_Photos`
3. คัดลอกข้อมูลแถว 2 ลงไปจากชีต `Input` ใน Excel ไปวางที่ `Plan!A2`
4. Deploy > New deployment > Web app > Execute as **Me**, Who has access **Anyone** > คัดลอก URL ที่ลงท้ายด้วย `/exec`
5. เปิด `config.js` วาง URL ลงใน `API_URL`
6. อัปไฟล์ทั้งหมด (ยกเว้นโฟลเดอร์ `apps-script`) ขึ้น repo GitHub Pages
7. เปิด `qr.html` แล้วพิมพ์ QR ทั้ง 2 ใบ

เมื่อแก้ `Code.gs` ภายหลัง ต้อง Deploy > Manage deployments > Edit > Version: New version ทุกครั้ง (URL เดิม)

## การใช้งาน
- Dashboard แสดงแผนของวันปัจจุบัน ดูวันอื่นได้จากช่องวันที่ หรือ `dashboard.html?date=2026-09-30`
- QR Task Code ต้องมีข้อความเป็น Task Code ตรงตัว เช่น `D20260930-01`
- รูปถูกย่อเหลือด้านยาว 1600 px ก่อนส่ง จำนวนและขนาดรวมตรวจจากรูปหลังย่อ
