# แจ้งแก้ไข BOM (Notify-of-BOM-correction) — Supabase

ข้อมูลอยู่ใน Supabase project เดียวกับ BOM_Packing (ตารางขึ้นต้นด้วย `bomc_`) — Google Sheet ใช้แค่ส่ง PD number / Released products ขึ้นระบบ

| ไฟล์ | ใช้ทำอะไร |
|---|---|
| `index.html` | หน้าเว็บ/แอป (แจ้งงาน / Dashboard / นำเข้า Excel / ผู้ใช้) — ต้องเข้าสู่ระบบ เครื่องจำไว้ |
| `supabase/bomc_setup.sql` | ตาราง สิทธิ์ ฟังก์ชัน ที่เก็บรูป (รันซ้ำได้) |
| `excel/modBOMC.bas` | มาโครไฟล์ Excel กลาง: ดึงข้อมูลลงชีต "แจ้งแก้ไข BOM by Line" (`.bas.utf8` = สำเนาไว้อ่าน) |
| `apps-script/SupabaseSync.gs` | ส่ง PD number (ชีต Dashboard) / Released products (ชีต Master Product) ขึ้นระบบทุก 1 ชม. |

## สิทธิ์ผู้ใช้

| สิทธิ์ | ทำได้ |
|---|---|
| Viewer | ดู Dashboard อย่างเดียว |
| Edit1 | แจ้งงาน + นำเข้า Excel |
| Edit2 | Edit1 + แก้สถานะของงาน / เอ็นจิเนียร์ผู้รับผิดชอบ (วันที่แก้ไข ระบบใส่ให้เอง) |
| Admin | ทุกอย่าง + ลบรายการ + ตั้งค่าผู้ใช้ (แท็บ "ผู้ใช้") |

- ผู้แจ้ง = ชื่อที่แสดงของผู้ใช้ที่ login (เปลี่ยนเองไม่ได้)
- ชื่อผู้ใช้สั้น เช่น `pu` ระบบเก็บเป็น `pu@bomc.local` (เข้าสู่ระบบพิมพ์แค่ `pu`)

## ตั้งค่า (v2)

1. Supabase → SQL Editor → วางทั้งไฟล์ `supabase/bomc_setup.sql` → Run
2. ตั้งตัวเองเป็น Admin (SQL Editor):
   `select public.bomc_make_admin('อีเมลของคุณ', 'ชื่อที่แสดง');`
3. ผู้ใช้ที่ใส่ใน `SB_EMAIL` ของ Apps Script (Google Sheet ทั้ง 2 ไฟล์) ต้องเป็น Admin — ถ้าเป็นอีเมลเดียวกับข้อ 2 ไม่ต้องทำอะไร
4. GitHub → push `index.html` → เปิดเว็บ → login → แท็บ "ผู้ใช้" → เพิ่มผู้ใช้ + ตั้งสิทธิ์
5. Excel กลาง → Alt+F11 → ลบ module `modBOMC` เดิม → Import `excel/modBOMC.bas` → Alt+F8 → `BOMC_CreateMenu`
6. มือถือหน้างาน: เปิดลิงก์ → login ครั้งเดียว → ติดตั้งแอป (Android: ปุ่ม "ติดตั้งแอป" / iPhone: แชร์ → เพิ่มไปยังหน้าจอโฮม)

## ใช้งานประจำ

- **แจ้งงาน**: สแกน/คีย์ รหัสงาน FG → เพิ่มรายการวัตถุดิบ
- **Dashboard**: ตารางครบทุกคอลัมน์, กรองตามสถานะ/ผู้แจ้ง/ค้นหา, สลับมุมมอง "ตามงาน"
  - Edit2/Admin: กด "แก้ไข" ที่แถว หรือติ๊กหลายแถว → แก้ สถานะ / เอ็นจิเนียร์
- **นำเข้า Excel** (ไฟล์ "แจ้งแก้ไข BOM by PN"): `Item Number`/`rmcode` → รหัสเดิม, `New Item`/`แก้ไขBOM-PD` → รหัสที่เอาไปใช้, ข้ามแถวซ้ำอัตโนมัติ
- **Excel กลาง**: กดปุ่ม "ดึงข้อมูลแจ้งแก้ไข BOM ล่าสุด" (ดึงลงอย่างเดียว ค่าที่แก้ในชีตจะถูกเขียนทับ)
- **PD number / Released products**: แก้ใน Google Sheet ตามปกติ ระบบส่งขึ้นเองทุก 1 ชม.
