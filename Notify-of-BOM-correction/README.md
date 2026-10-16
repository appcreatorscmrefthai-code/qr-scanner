# แจ้งแก้ไข BOM (Notify-of-BOM-correction) — Supabase

ข้อมูลอยู่ใน Supabase project เดียวกับ BOM_Packing (ตารางขึ้นต้นด้วย `bomc_`) ไม่ใช้ Google Sheet / Apps Script แล้ว

| ไฟล์ | ใช้ทำอะไร |
|---|---|
| `index.html` | หน้าเว็บ (แจ้งงาน / Dashboard / นำเข้า Excel) |
| `supabase/bomc_setup.sql` | สร้างตาราง สิทธิ์ ฟังก์ชัน และที่เก็บรูป (รันครั้งเดียว รันซ้ำได้) |
| `excel/modBOMC.bas` | มาโครสำหรับไฟล์ Excel กลาง "แจ้งแก้ไข BOM" (`.bas.utf8` = สำเนาไว้อ่าน) |

## ตั้งค่าครั้งแรก

1. **Supabase** → เปิด project ของ BOM_Packing → SQL Editor → New query → วางทั้งไฟล์ `supabase/bomc_setup.sql` → Run
2. **ไฟล์ Excel กลาง** "แจ้งแก้ไข BOM"
   1. File → Save As → ชนิด **Excel Macro-Enabled Workbook (.xlsm)**
   2. Alt+F11 → File → Import File → เลือก `excel/modBOMC.bas`
   3. Alt+F8 → `BOMC_CreateMenu` → Run (ได้ชีต "เมนูระบบ" พร้อม 2 ปุ่ม)
   4. ให้ชีต "แจ้งแก้ไข BOM by Line" มีข้อมูลล่าสุดจาก Google Sheet ก่อน
   5. กดปุ่ม **2) ส่ง PD number / Released products ขึ้นระบบ**
   6. กดปุ่ม **1) ซิงก์ข้อมูลแจ้งแก้ไข BOM** → ตอบ "ใช่" เพื่อย้ายข้อมูลเดิมขึ้นระบบ (ทำครั้งเดียว)
3. **GitHub** → commit + push `index.html` (และโฟลเดอร์ `supabase`, `excel`) ใน repo scm-dev
4. เปิดหน้าเว็บ (เติม `?v=` ต่อท้ายลิงก์กันแคช) ลองแจ้งงาน 1 รายการ แล้วกดปุ่ม 1 ใน Excel ดูว่าข้อมูลลงชีต

## ใช้งานประจำ

- **แจ้งงาน / Dashboard**: ไม่ต้อง login
- **นำเข้า Excel** (ไฟล์ "แจ้งแก้ไข BOM by PN"): ต้อง login (ผู้ใช้เดียวกับหน้า BOM Packing)
  - `Item Number` / `rmcode` → รหัสเดิม, `New Item` / `แก้ไขBOM-PD` → รหัสที่เอาไปใช้ (ชื่อวัตถุดิบดึงจาก Released products)
  - ข้ามแถวที่ซ้ำกับข้อมูลในระบบให้อัตโนมัติ
- **เอ็นจิเนียร์ / วันที่แก้ไข / สถานะของงาน**: แก้ในชีต "แจ้งแก้ไข BOM by Line" แล้วกดปุ่ม 1 (ห้ามแก้/ลบคอลัมน์ ID)
- **PD number / Released products มีข้อมูลใหม่**: วางข้อมูลในชีต แล้วกดปุ่ม 2
