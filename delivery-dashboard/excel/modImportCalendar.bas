Attribute VB_Name = "modImportCalendar"
Option Explicit

' ============================================================================
'  Delivery Tracking : ดึงแผนส่งของ (export-tasks) + ใบจองรถ (1Template_TB) ลงชีต Plan
'  รุ่น 2026.10.15-c  (เติม Task Code อัตโนมัติ / งานต่างประเทศ / รอบเดียว / Task Status = Used)
'  ต้องใช้คู่กับ modDeliveryPlan รุ่น y3 ขึ้นไป (ฟังก์ชัน DP_WebNextSeq)
'
'  มาโคร (Alt+F8) :
'    DP_ImportCalendar    ทำตามขั้นตอนใน Sheet1 ทั้งหมด
'    DP_AddImportButton   สร้างปุ่ม "ดึงแผนจาก Calendar" ในชีต Plan (รันครั้งเดียว)
'
'  ขั้นตอน
'    1) เลือกไฟล์ export-tasks  -> คัดลอกชีต Sheet1 (ค่าอย่างเดียว) มาไว้ชีต Calendar Plan แล้วปิดไฟล์
'    2) เลือกไฟล์ 1Template_TB  -> คัดลอกชีต Input  (ค่าอย่างเดียว) มาไว้ชีต Transport Booking แล้วปิดไฟล์
'    3-4) กรองวันที่ตามชีต Plan ช่อง B1:C1 (C1 ว่าง = วันเดียว) และ Trans Type = outbound
'    5) จัดข้อมูล -> ชีต Calendar Plan เหลือ 5 คอลัมน์ : Client Name | Date | Transport | Schedule | Detail
'       Detail = ข้อความระหว่าง [ติ๊กถูกเขียว] กับ [สามเหลี่ยม] / [หัวใจม่วง] (หลายข้อความคั่นด้วย ", ")
'    6) วางต่อท้ายชีต Plan : A->D, B->B, C->E, D->F, E->C  และเติม J-X จากชีต Transport Booking
'       (key = Client Name เทียบกับคอลัมน์ "อ้างอิง LN" ของใบจองรถ, จับคู่คอลัมน์ตามชื่อหัวตาราง)
'    7) เติมข้อมูลเพิ่ม
'       A  Task Code   = D + ปปปปดดวว + "-" + ลำดับ ต่อจากเลขล่าสุดบนเว็บ (และเลขที่มีในชีต Plan / Plan_Backup)
'       งานต่างประเทศ (ดูจาก Client Name) : K ประเภทรถ / G Arrival Time 1 = Schedule + เวลา
'          DHL26000011             -> DHL       + 30 นาที
'          LCL26000001 SI          -> LCL       + 30 นาที
'          CL26000003 xxx 20FT     -> CL 20FT   + 2 ชม.
'          CL26000077 xxx 40FT/40  -> CL 40FT   + 4 ชม.
'          CL26000077 xxx 40HC     -> CL 40HC   + 4 ชม.
'       O  รอบขนส่ง    = รอบเดียว (งานต่างประเทศเสมอ / งานในประเทศเมื่อใบจองรถไม่ได้ระบุ)
'       Y  Task Status = Used ทุกแถว
'
'  หมายเหตุ : หาคอลัมน์จากชื่อหัวตาราง ไม่ใช้ตัวอักษรคอลัมน์ ถ้าไฟล์ต้นทางสลับลำดับคอลัมน์ก็ยังทำงานได้
' ============================================================================

Private Const APP_TITLE As String = "Delivery Tracking - ดึงแผน"
Private Const PLAN_SHEET As String = "Plan"
Private Const CAL_SHEET As String = "Calendar Plan"
Private Const TB_SHEET As String = "Transport Booking"
Private Const SRC_CAL_SHEET As String = "Sheet1"
Private Const SRC_TB_SHEET As String = "Input"
Private Const TRANS_TYPE As String = "outbound"
Private Const SKIP_CLIENT As String = "D/N NO"     ' Client Name ที่ขึ้นต้นด้วยคำนี้ ไม่นำมาใช้ (ไม่สนช่องว่าง/ตัวพิมพ์)
Private Const TB_KEY_HEAD As String = "อ้างอิง LN"
Private Const TB_NOTE_HEAD As String = "หมายเหตุ"
Private Const TB_CANCEL_WORD As String = "ยกเลิก"
Private Const LOOKUP_FIRST As Long = 10    ' คอลัมน์ J ของชีต Plan
Private Const LOOKUP_LAST As Long = 24     ' คอลัมน์ X ของชีต Plan
Private Const PLAN_LASTCOL As Long = 26    ' คอลัมน์ Z
Private Const LIST_MAX As Long = 15        ' จำนวนรายการสูงสุดที่แสดงในข้อความสรุป
Private Const COL_ARR1 As Long = 7         ' G Arrival Time 1
Private Const COL_VTYPE As Long = 11       ' K ประเภทรถ
Private Const COL_ROUND As Long = 15       ' O รอบขนส่ง
Private Const COL_STATUS As Long = 25      ' Y Task Status
Private Const OUT_LAST As Long = 25        ' เขียนลงชีต Plan ถึงคอลัมน์ Y
Private Const ROUND_ONE As String = "รอบเดียว"
Private Const STATUS_NEW As String = "Used"
Private Const BACKUP_SHEET As String = "Plan_Backup"
' เวลาที่รถต่างประเทศควรถึง (นาที นับจาก Schedule) : แก้ตัวเลขตรงนี้ได้
Private Const MIN_DHL As Long = 30
Private Const MIN_LCL As Long = 30
Private Const MIN_CL20 As Long = 120
Private Const MIN_CL40 As Long = 240
Private Const MIN_CL40HC As Long = 240

' ---------------------------------------------------------------------------
'  มาโครหลัก
' ---------------------------------------------------------------------------
Public Sub DP_ImportCalendar()
    Dim wsPlan As Worksheet, wsCal As Worksheet, wsTb As Worksheet
    Dim hdr As Long, d1 As Date, d2 As Date, tmp As Date
    Dim fCal As Variant, fTb As Variant
    Dim cal As Variant, nCal As Long
    Dim nExist As Long, startRow As Long, i As Long, c As Long
    Dim outP() As Variant
    Dim keyCol As Long, noteCol As Long, colMap(LOOKUP_FIRST To LOOKUP_LAST) As Long, missHead As String
    Dim tb As Variant, tbHdr As Long, dAct As Object, dCnt As Object, dCan As Object
    Dim key As String, r As Long
    Dim nNo As Long, sNo As String, nCan As Long, sCan As String, nMulti As Long, sMulti As String, nBlank As Long
    Dim rangeText As String
    Dim vType As String, vMin As Long, isIntl() As Boolean, nIntl As Long, nUnk As Long, sUnk As String, nNoSch As Long, sNoSch As String
    Dim codeMsg As String

    ' ---- ตรวจชีต Plan และช่วงวันที่ B1:C1 ----
    Set wsPlan = FindSheet(PLAN_SHEET)
    If wsPlan Is Nothing Then
        Tell "ไม่พบชีต " & PLAN_SHEET & " ในไฟล์นี้", True
        Exit Sub
    End If
    hdr = PlanHeaderRow(wsPlan)
    If hdr = 0 Then
        Tell "ไม่พบหัวตารางในชีต " & PLAN_SHEET & " (คอลัมน์ A ต้องมีคำว่า Task Code)", True
        Exit Sub
    End If
    If Not ParseYMD(wsPlan.Range("B1").Value, d1) Then
        Tell "กรุณาใส่วันที่ที่ชีต " & PLAN_SHEET & " ช่อง B1 (และช่อง C1 ถ้าต้องการเป็นช่วงวันที่)", True
        Exit Sub
    End If
    If Len(Trim$(CStr(wsPlan.Range("C1").Value))) = 0 Then
        d2 = d1
    ElseIf Not ParseYMD(wsPlan.Range("C1").Value, d2) Then
        Tell "วันที่ในชีต " & PLAN_SHEET & " ช่อง C1 ไม่ถูกต้อง", True
        Exit Sub
    End If
    If d2 < d1 Then tmp = d1: d1 = d2: d2 = tmp
    rangeText = Format$(d1, "yyyy-mm-dd") & IIf(d2 > d1, " ถึง " & Format$(d2, "yyyy-mm-dd"), "")

    ' ---- เลือกไฟล์ต้นทางทั้ง 2 ไฟล์ตอนเริ่มต้น ----
    fCal = Application.GetOpenFilename("Excel Files (*.xls*),*.xls*", , "1/2 เลือกไฟล์ export-tasks (ข้อมูลอยู่ในชีต Sheet1)")
    If VarType(fCal) = vbBoolean Then Exit Sub
    fTb = Application.GetOpenFilename("Excel Files (*.xls*),*.xls*", , "2/2 เลือกไฟล์ 1Template_TB (ข้อมูลอยู่ในชีต Input)")
    If VarType(fTb) = vbBoolean Then Exit Sub

    On Error GoTo Fail
    Application.ScreenUpdating = False

    ' ---- 1) 2) คัดลอกข้อมูลจากไฟล์ต้นทาง (ค่าอย่างเดียว) ----
    Application.StatusBar = "กำลังคัดลอกข้อมูลจากไฟล์ export-tasks ..."
    Set wsCal = CopyFromFile(CStr(fCal), SRC_CAL_SHEET, CAL_SHEET)
    If wsCal Is Nothing Then GoTo Done
    Application.StatusBar = "กำลังคัดลอกข้อมูลจากไฟล์ใบจองรถ ..."
    Set wsTb = CopyFromFile(CStr(fTb), SRC_TB_SHEET, TB_SHEET)
    If wsTb Is Nothing Then GoTo Done

    ' ---- 3) 4) 5) กรองและจัดข้อมูล แล้วเขียนกลับชีต Calendar Plan ----
    Application.StatusBar = "กำลังจัดข้อมูล ..."
    If Not BuildCalendar(wsCal, d1, d2, cal, nCal) Then GoTo Done
    WriteCalendar wsCal, cal, nCal
    If nCal = 0 Then
        Application.ScreenUpdating = True
        Tell "ไม่พบงาน " & TRANS_TYPE & " วันที่ " & rangeText & " ในไฟล์ export-tasks" & vbCrLf & "(ยังไม่ได้เพิ่มข้อมูลลงชีต " & PLAN_SHEET & ")", True
        GoTo Done
    End If

    ' ---- กันการเพิ่มซ้ำ : ถ้าชีต Plan มีงานวันที่นี้อยู่แล้ว ให้ถามก่อน ----
    nExist = CountPlanDates(wsPlan, hdr, d1, d2)
    If nExist > 0 Then
        Application.ScreenUpdating = True
        If MsgBox("ชีต " & PLAN_SHEET & " มีงานวันที่ " & rangeText & " อยู่แล้ว " & CStr(nExist) & " แถว" & vbCrLf & vbCrLf & _
                  "ต้องการเพิ่มอีก " & CStr(nCal) & " แถวต่อท้ายหรือไม่?" & vbCrLf & "(ข้อมูลในชีต " & CAL_SHEET & " และ " & TB_SHEET & " อัปเดตแล้ว)", _
                  vbQuestion + vbYesNo + vbDefaultButton2, APP_TITLE) <> vbYes Then GoTo Done
        Application.ScreenUpdating = False
    End If

    ' ---- เตรียมข้อมูลใบจองรถ (Transport Booking) ----
    tb = wsTb.UsedRange.Value
    If Not IsArray(tb) Then
        Tell "ชีต " & TB_SHEET & " ไม่มีข้อมูล", True
        GoTo Done
    End If
    tbHdr = FindHeadRow(tb, TB_KEY_HEAD)
    If tbHdr = 0 Then
        Tell "ไม่พบหัวตาราง """ & TB_KEY_HEAD & """ ในชีต " & TB_SHEET, True
        GoTo Done
    End If
    keyCol = FindCol(tb, tbHdr, TB_KEY_HEAD)
    noteCol = FindCol(tb, tbHdr, TB_NOTE_HEAD)
    For c = LOOKUP_FIRST To LOOKUP_LAST
        colMap(c) = FindCol(tb, tbHdr, CStr(wsPlan.Cells(hdr, c).Value))
        If colMap(c) = 0 Then missHead = missHead & vbCrLf & "  " & ColLetter(c) & " : " & CStr(wsPlan.Cells(hdr, c).Value)
    Next c

    Set dAct = CreateObject("Scripting.Dictionary")   ' key -> แถวล่าสุดที่ไม่ถูกยกเลิก
    Set dCnt = CreateObject("Scripting.Dictionary")   ' key -> จำนวนใบจองที่ไม่ถูกยกเลิก
    Set dCan = CreateObject("Scripting.Dictionary")   ' key -> มีใบจองที่ถูกยกเลิก
    For r = tbHdr + 1 To UBound(tb, 1)
        key = KeyOf(tb(r, keyCol))
        If Len(key) > 0 Then
            If noteCol > 0 And InStr(1, SafeStr(tb(r, noteCol)), TB_CANCEL_WORD) > 0 Then
                dCan(key) = True
            Else
                dAct(key) = r
                dCnt(key) = dCnt(key) + 1
            End If
        End If
    Next r

    ' ---- 6) สร้างแถวใหม่ของชีต Plan (A-X) ----
    ReDim outP(1 To nCal, 1 To OUT_LAST)
    ReDim isIntl(1 To nCal)
    For i = 1 To nCal
        outP(i, 2) = cal(i + 1, 2)      ' Date
        outP(i, 3) = cal(i + 1, 5)      ' Detail
        outP(i, 4) = cal(i + 1, 1)      ' Client Name
        outP(i, 5) = cal(i + 1, 3)      ' Transport
        outP(i, 6) = cal(i + 1, 4)      ' Schedule

        isIntl(i) = IntlType(SafeStr(cal(i + 1, 1)), vType, vMin)
        key = KeyOf(cal(i + 1, 1))
        If Len(key) = 0 Then
            nBlank = nBlank + 1
        ElseIf dAct.Exists(key) Then
            r = dAct(key)
            For c = LOOKUP_FIRST To LOOKUP_LAST
                If colMap(c) > 0 Then outP(i, c) = SafeStr(tb(r, colMap(c)))
            Next c
            If dCnt(key) > 1 Then
                nMulti = nMulti + 1
                If nMulti <= LIST_MAX Then sMulti = sMulti & vbCrLf & "  " & CStr(cal(i + 1, 1)) & " (" & CStr(dCnt(key)) & " ใบ)"
            End If
        ElseIf isIntl(i) Then
            ' งานต่างประเทศไม่มีใบจองรถ : ไม่ต้องเตือน
        ElseIf dCan.Exists(key) Then
            nCan = nCan + 1
            If nCan <= LIST_MAX Then sCan = sCan & vbCrLf & "  " & CStr(cal(i + 1, 1))
        Else
            nNo = nNo + 1
            If nNo <= LIST_MAX Then sNo = sNo & vbCrLf & "  " & CStr(cal(i + 1, 1))
        End If

        ' ---- 7) เติมข้อมูลเพิ่ม (ทำหลังดึงใบจองรถ ค่าตามกติกานี้จึงใช้แทนค่าจากใบจอง) ----
        If isIntl(i) Then
            nIntl = nIntl + 1
            outP(i, COL_ROUND) = ROUND_ONE
            If Len(vType) = 0 Then
                nUnk = nUnk + 1
                If nUnk <= LIST_MAX Then sUnk = sUnk & vbCrLf & "  " & CStr(cal(i + 1, 1))
            Else
                outP(i, COL_VTYPE) = vType
                If VarType(outP(i, 6)) = vbDouble Then
                    outP(i, COL_ARR1) = AddMinutes(CDbl(outP(i, 6)), vMin)
                Else
                    nNoSch = nNoSch + 1
                    If nNoSch <= LIST_MAX Then sNoSch = sNoSch & vbCrLf & "  " & CStr(cal(i + 1, 1))
                End If
            End If
        ElseIf Len(Trim$(SafeStr(outP(i, COL_ROUND)))) = 0 Then
            outP(i, COL_ROUND) = ROUND_ONE
        End If
        outP(i, COL_STATUS) = STATUS_NEW
    Next i

    ' ---- A) Task Code ต่อจากเลขล่าสุดบนเว็บ ----
    Application.StatusBar = "กำลังเช็กเลข Task Code ล่าสุดจากเว็บ ..."
    If Not FillTaskCodes(outP, nCal, wsPlan, hdr, codeMsg) Then GoTo Done

    ' ---- วางต่อท้ายข้อมูลเดิมในชีต Plan ----
    startRow = lastRow(wsPlan, hdr) + 1
    With wsPlan
        .Range(.Cells(startRow, 1), .Cells(startRow + nCal - 1, 1)).NumberFormat = "@"
        .Range(.Cells(startRow, 2), .Cells(startRow + nCal - 1, 2)).NumberFormat = "yyyy-mm-dd"
        .Range(.Cells(startRow, 6), .Cells(startRow + nCal - 1, 9)).NumberFormat = "hh:mm"
        .Range(.Cells(startRow, 12), .Cells(startRow + nCal - 1, 12)).NumberFormat = "@"
        .Range(.Cells(startRow, 14), .Cells(startRow + nCal - 1, 14)).NumberFormat = "@"
        .Range(.Cells(startRow, 1), .Cells(startRow + nCal - 1, OUT_LAST)).Value = outP
    End With

    Application.StatusBar = False
    Application.ScreenUpdating = True
    On Error Resume Next
    Application.GoTo wsPlan.Cells(startRow, 1), False
    On Error GoTo 0

    Tell "เพิ่มงานลงชีต " & PLAN_SHEET & " " & CStr(nCal) & " แถว (แถว " & CStr(startRow) & "-" & CStr(startRow + nCal - 1) & ")" & vbCrLf & _
         "วันที่ " & rangeText & " / " & TRANS_TYPE & vbCrLf & codeMsg & _
         IIf(nIntl > 0, vbCrLf & "งานต่างประเทศ " & CStr(nIntl) & " งาน (เติมประเภทรถ / Arrival Time 1 / รอบเดียว ให้แล้ว)", "") & _
         IIf(nUnk > 0, vbCrLf & vbCrLf & "งาน CL ที่ไม่ทราบขนาดตู้ " & CStr(nUnk) & " งาน (กรุณาใส่ประเภทรถ CL 20FT / CL 40FT / CL 40HC และ Arrival Time 1 เอง):" & sUnk & IIf(nUnk > LIST_MAX, vbCrLf & "  ...", ""), "") & _
         IIf(nNoSch > 0, vbCrLf & vbCrLf & "งานต่างประเทศที่ไม่มี Schedule " & CStr(nNoSch) & " งาน (คำนวณ Arrival Time 1 ไม่ได้ กรุณาใส่เอง):" & sNoSch & IIf(nNoSch > LIST_MAX, vbCrLf & "  ...", ""), "") & _
         IIf(nNo > 0, vbCrLf & vbCrLf & "ไม่พบใบจองรถ " & CStr(nNo) & " งาน (J-X ว่าง):" & sNo & IIf(nNo > LIST_MAX, vbCrLf & "  ...", ""), "") & _
         IIf(nCan > 0, vbCrLf & vbCrLf & "ใบจองรถถูกยกเลิก " & CStr(nCan) & " งาน (J-X ว่าง):" & sCan & IIf(nCan > LIST_MAX, vbCrLf & "  ...", ""), "") & _
         IIf(nMulti > 0, vbCrLf & vbCrLf & "มีใบจองรถมากกว่า 1 ใบ (ใช้ใบล่าสุด) " & CStr(nMulti) & " งาน:" & sMulti & IIf(nMulti > LIST_MAX, vbCrLf & "  ...", ""), "") & _
         IIf(nBlank > 0, vbCrLf & vbCrLf & "ไม่มี Client Name (ค้นใบจองรถไม่ได้) " & CStr(nBlank) & " งาน", "") & _
         IIf(Len(missHead) > 0, vbCrLf & vbCrLf & "ไม่พบหัวตารางนี้ในใบจองรถ (คอลัมน์ว่าง):" & missHead, "") & _
         vbCrLf & vbCrLf & "ตรวจ Arrival Time ของงานในประเทศก่อนกดส่งงานใหม่ขึ้นระบบ"
    Exit Sub

Done:
    Application.CutCopyMode = False
    Application.StatusBar = False
    Application.ScreenUpdating = True
    Exit Sub
Fail:
    Application.CutCopyMode = False
    Application.StatusBar = False
    Application.ScreenUpdating = True
    Tell "เกิดข้อผิดพลาด: " & Err.Description, True
End Sub

' ปุ่มในชีต Plan (ใต้ปุ่มเดิม 8 ปุ่มทางขวาของคอลัมน์ Z)
Public Sub DP_AddImportButton()
    Dim ws As Worksheet, b As Object, i As Long
    Set ws = FindSheet(PLAN_SHEET)
    If ws Is Nothing Then
        Tell "ไม่พบชีต " & PLAN_SHEET, True
        Exit Sub
    End If
    For i = ws.Buttons.Count To 1 Step -1
        If ws.Buttons(i).name = "DPimp_1" Then ws.Buttons(i).Delete
    Next i
    Set b = ws.Buttons.Add(ws.Cells(1, PLAN_LASTCOL + 2).Left, ws.Cells(1, 1).Top + 2 + 56, 180, 24)
    b.name = "DPimp_1"
    b.Caption = "ดึงแผนจาก Calendar"
    b.OnAction = "DP_ImportCalendar"
    Tell "สร้างปุ่ม ""ดึงแผนจาก Calendar"" ในชีต " & PLAN_SHEET & " แล้ว (ลากย้ายตำแหน่งได้)"
End Sub

' ---------------------------------------------------------------------------
'  ขั้นตอน 1-2 : เปิดไฟล์ต้นทาง คัดลอกค่า แล้วปิดไฟล์
' ---------------------------------------------------------------------------
Private Function CopyFromFile(ByVal path As String, ByVal srcName As String, ByVal dstName As String) As Worksheet
    Dim wb As Workbook, ws As Worksheet, dst As Worksheet, wasOpen As Boolean
    Dim ur As Range, rng As Range, errMsg As String

    wasOpen = True
    On Error GoTo Fail
    Set wb = OpenedBook(path, wasOpen)
    If wb Is Nothing Then Exit Function

    On Error Resume Next
    Set ws = wb.Worksheets(srcName)
    On Error GoTo Fail
    If ws Is Nothing And wb.Worksheets.Count = 1 Then Set ws = wb.Worksheets(1)
    If ws Is Nothing Then
        If Not wasOpen Then wb.Close SaveChanges:=False
        Tell "ไม่พบชีต " & srcName & " ในไฟล์" & vbCrLf & path, True
        Exit Function
    End If

    Set dst = FindSheet(dstName)
    If dst Is Nothing Then
        Set dst = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
        dst.name = dstName
    End If
    dst.Cells.Clear

    Set ur = ws.UsedRange
    Set rng = ws.Range(ws.Cells(1, 1), ws.Cells(ur.row + ur.rows.Count - 1, ur.Column + ur.Columns.Count - 1))
    rng.Copy
    dst.Range("A1").PasteSpecial Paste:=xlPasteValuesAndNumberFormats
    Application.CutCopyMode = False

    If Not wasOpen Then wb.Close SaveChanges:=False
    Set CopyFromFile = dst
    Exit Function

Fail:
    errMsg = Err.Description
    Resume Cleanup
Cleanup:
    On Error Resume Next
    Application.CutCopyMode = False
    If Not wasOpen Then
        If Not wb Is Nothing Then wb.Close SaveChanges:=False
    End If
    On Error GoTo 0
    Err.Raise vbObjectError + 513, , errMsg
End Function

' เปิดไฟล์แบบอ่านอย่างเดียว (ถ้าเปิดอยู่แล้วใช้ตัวที่เปิดอยู่ และจะไม่ปิดให้)
Private Function OpenedBook(ByVal path As String, ByRef wasOpen As Boolean) As Workbook
    Dim wb As Workbook, fname As String
    fname = Mid$(path, InStrRev(path, Application.PathSeparator) + 1)
    For Each wb In Application.Workbooks
        If StrComp(wb.FullName, path, vbTextCompare) = 0 Then
            wasOpen = True
            Set OpenedBook = wb
            Exit Function
        End If
        If StrComp(wb.name, fname, vbTextCompare) = 0 Then
            Tell "มีไฟล์ชื่อ " & fname & " เปิดอยู่แล้ว (คนละโฟลเดอร์) กรุณาปิดไฟล์นั้นก่อน", True
            Exit Function
        End If
    Next wb
    wasOpen = False
    Set OpenedBook = Workbooks.Open(Filename:=path, UpdateLinks:=0, ReadOnly:=True)
End Function

' ---------------------------------------------------------------------------
'  ขั้นตอน 3-5 : กรองวันที่ + outbound และจัดข้อมูล
'  ผลลัพธ์ out(1 To n+1, 1 To 5) แถวที่ 1 = หัวตาราง
' ---------------------------------------------------------------------------
Private Function BuildCalendar(ByVal ws As Worksheet, ByVal d1 As Date, ByVal d2 As Date, ByRef out As Variant, ByRef n As Long) As Boolean
    Dim a As Variant, h As Long, r As Long, d As Date
    Dim cClient As Long, cDt As Long, cType As Long, cTrans As Long, cSch As Long, cDet As Long
    Dim miss As String, keep() As Long, k As Long

    a = ws.UsedRange.Value
    If Not IsArray(a) Then
        Tell "ชีต " & CAL_SHEET & " ไม่มีข้อมูล", True
        Exit Function
    End If
    h = FindHeadRow(a, "Client Name")
    If h = 0 Then
        Tell "ไม่พบหัวตาราง ""Client Name"" ในไฟล์ export-tasks", True
        Exit Function
    End If
    cClient = FindCol(a, h, "Client Name")
    cDt = FindCol(a, h, "Date")
    cType = FindCol(a, h, "Trans Type")
    cTrans = FindCol(a, h, "Transport")
    cSch = FindCol(a, h, "Schedule")
    cDet = FindCol(a, h, "Detail")
    If cDt = 0 Then miss = miss & " Date"
    If cType = 0 Then miss = miss & " ""Trans Type"""
    If cTrans = 0 Then miss = miss & " Transport"
    If cSch = 0 Then miss = miss & " Schedule"
    If cDet = 0 Then miss = miss & " Detail"
    If Len(miss) > 0 Then
        Tell "ไฟล์ export-tasks ไม่มีคอลัมน์:" & miss, True
        Exit Function
    End If

    ReDim keep(1 To UBound(a, 1))
    For r = h + 1 To UBound(a, 1)
        If ParseYMD(a(r, cDt), d) Then
            If d >= d1 And d <= d2 Then
                If StrComp(Trim$(SafeStr(a(r, cType))), TRANS_TYPE, vbTextCompare) = 0 Then
                    If Not IsSkipClient(a(r, cClient)) Then
                        k = k + 1
                        keep(k) = r
                    End If
                End If
            End If
        End If
    Next r

    n = k
    ReDim out(1 To n + 1, 1 To 5)
    out(1, 1) = "Client Name"
    out(1, 2) = "Date"
    out(1, 3) = "Transport"
    out(1, 4) = "Schedule"
    out(1, 5) = "Detail"
    For k = 1 To n
        r = keep(k)
        ParseYMD a(r, cDt), d
        out(k + 1, 1) = Trim$(Flatten(SafeStr(a(r, cClient)), False))
        out(k + 1, 2) = d
        out(k + 1, 3) = Flatten(SafeStr(a(r, cTrans)), False)
        out(k + 1, 4) = HmValue(a(r, cSch))
        out(k + 1, 5) = CleanDetail(SafeStr(a(r, cDet)))
    Next k
    BuildCalendar = True
End Function

' Client Name ที่ขึ้นต้นด้วย SKIP_CLIENT (เช่น "D/N NO : DN26-0151") = ข้าม
Private Function IsSkipClient(ByVal v As Variant) As Boolean
    Dim s As String, k As String
    s = UCase$(Replace(Replace(SafeStr(v), ChrW(160), ""), " ", ""))
    k = UCase$(Replace(SKIP_CLIENT, " ", ""))
    IsSkipClient = (Len(k) > 0 And Left$(s, Len(k)) = k)
End Function

Private Sub WriteCalendar(ByVal ws As Worksheet, ByVal out As Variant, ByVal n As Long)
    ws.Cells.Clear
    ws.Range("A:A,C:C,E:E").NumberFormat = "@"
    ws.Range("B:B").NumberFormat = "yyyy-mm-dd"
    ws.Range("D:D").NumberFormat = "hh:mm"
    ws.Range("A1").Resize(n + 1, 5).Value = out
    ws.Range("A1:E1").Font.Bold = True
    ws.Columns("A").ColumnWidth = 22
    ws.Columns("B").ColumnWidth = 12
    ws.Columns("C").ColumnWidth = 45
    ws.Columns("D").ColumnWidth = 9
    ws.Columns("E").ColumnWidth = 80
End Sub

' ---------------------------------------------------------------------------
'  ขั้นตอน 5.5 : ตัดข้อความใน Detail
'  เอาข้อความหลัง [ติ๊กถูกเขียว] จนถึงสัญลักษณ์ถัดไป ([สามเหลี่ยม] [หัวใจม่วง] [หัวใจเขียว] [สามเหลี่ยมแดง]
'  [ตกใจแดง] [กรรไกร] [ติ๊กถูกเขียว] หรือเส้น ---) ถ้ามีหลายช่วงคั่นด้วย ", "
'  ไม่มี [ติ๊กถูกเขียว] เลย (เช่นงาน D/N โรงสี) = ใช้ข้อความเดิมทั้งหมดต่อเป็นบรรทัดเดียว
' ---------------------------------------------------------------------------
Private Function CleanDetail(ByVal s As String) As String
    Dim chk As String, p As Long, st As Long, en As Long, piece As String, res As String
    s = Replace(s, vbCrLf, vbLf)
    s = Replace(s, vbCr, vbLf)
    chk = ChrW(&H2705)                                  ' ติ๊กถูกเขียว
    p = InStr(1, s, chk)
    If p = 0 Then
        CleanDetail = Flatten(s, False)
        Exit Function
    End If
    Do While p > 0
        st = p + Len(chk)
        en = NextMarker(s, st)
        piece = Flatten(Mid$(s, st, en - st), True)
        If Len(piece) > 0 Then
            If Len(res) > 0 Then res = res & ", "
            res = res & piece
        End If
        p = InStr(en, s, chk)
    Loop
    CleanDetail = res
End Function

' ตำแหน่งของสัญลักษณ์ตัวถัดไปหลังตำแหน่ง st (ไม่พบ = ความยาวข้อความ + 1)
Private Function NextMarker(ByVal s As String, ByVal st As Long) As Long
    Dim m As Variant, p As Long, best As Long
    Dim hi As String
    hi = ChrW(&HD83D&)
    best = Len(s) + 1
    For Each m In Array(ChrW(&H25B6), _
                        hi & ChrW(&HDC9C&), _
                        hi & ChrW(&HDC9A&), _
                        hi & ChrW(&HDD3B&), _
                        ChrW(&H2757), _
                        ChrW(&H2702), _
                        ChrW(&H2705), _
                        "---")
        ' สามเหลี่ยม, หัวใจม่วง, หัวใจเขียว, สามเหลี่ยมแดง, ตกใจแดง, กรรไกร, ติ๊กถูกเขียว, ---
        p = InStr(st, s, CStr(m))
        If p > 0 And p < best Then best = p
    Next m
    NextMarker = best
End Function

' รวมหลายบรรทัดเป็นบรรทัดเดียว ตัดช่องว่างซ้ำ (stripVS = ลบตัวกำกับ emoji FE0F ที่ค้าง)
Private Function Flatten(ByVal s As String, ByVal stripVS As Boolean) As String
    s = Replace(s, vbCr, " ")
    s = Replace(s, vbLf, " ")
    s = Replace(s, vbTab, " ")
    s = Replace(s, ChrW(160), " ")
    If stripVS Then s = Replace(s, ChrW(&HFE0F&), "")
    Do While InStr(1, s, "  ") > 0
        s = Replace(s, "  ", " ")
    Loop
    Flatten = Trim$(s)
End Function

' ---------------------------------------------------------------------------
'  ตัวช่วย
' ---------------------------------------------------------------------------
Private Sub Tell(ByVal msg As String, Optional ByVal warn As Boolean = False)
    Application.ScreenUpdating = True
    MsgBox msg, IIf(warn, vbExclamation, vbInformation), APP_TITLE
End Sub

Private Function FindSheet(ByVal name As String) As Worksheet
    On Error Resume Next
    Set FindSheet = ThisWorkbook.Worksheets(name)
    On Error GoTo 0
End Function

Private Function PlanHeaderRow(ByVal ws As Worksheet) As Long
    Dim r As Long
    For r = 1 To 10
        If LCase$(Trim$(CStr(ws.Cells(r, 1).Value))) = "task code" Then
            PlanHeaderRow = r
            Exit Function
        End If
    Next r
End Function

' แถวสุดท้ายที่มีข้อมูลในคอลัมน์ A-Z (อย่างน้อย = แถวหัวตาราง)
Private Function lastRow(ByVal ws As Worksheet, ByVal hdr As Long) As Long
    Dim c As Long, r As Long, m As Long
    m = hdr
    For c = 1 To PLAN_LASTCOL
        r = ws.Cells(ws.rows.Count, c).End(xlUp).row
        If r > m Then m = r
    Next c
    lastRow = m
End Function

Private Function CountPlanDates(ByVal ws As Worksheet, ByVal hdr As Long, ByVal d1 As Date, ByVal d2 As Date) As Long
    Dim r As Long, lr As Long, d As Date, n As Long
    lr = lastRow(ws, hdr)
    For r = hdr + 1 To lr
        If ParseYMD(ws.Cells(r, 2).Value, d) Then
            If d >= d1 And d <= d2 Then n = n + 1
        End If
    Next r
    CountPlanDates = n
End Function

' หาแถวหัวตาราง (ใน 10 แถวแรก) ที่มีข้อความ headText
Private Function FindHeadRow(ByVal a As Variant, ByVal headText As String) As Long
    Dim r As Long, c As Long
    For r = 1 To Application.WorksheetFunction.Min(10, UBound(a, 1))
        For c = 1 To UBound(a, 2)
            If StrComp(Trim$(SafeStr(a(r, c))), headText, vbTextCompare) = 0 Then
                FindHeadRow = r
                Exit Function
            End If
        Next c
    Next r
End Function

Private Function FindCol(ByVal a As Variant, ByVal h As Long, ByVal headText As String) As Long
    Dim c As Long
    headText = Trim$(Replace(headText, ChrW(160), " "))
    If Len(headText) = 0 Then Exit Function
    For c = 1 To UBound(a, 2)
        If StrComp(Trim$(Replace(SafeStr(a(h, c)), ChrW(160), " ")), headText, vbTextCompare) = 0 Then
            FindCol = c
            Exit Function
        End If
    Next c
End Function

Private Function SafeStr(ByVal v As Variant) As String
    If IsError(v) Or IsEmpty(v) Or IsNull(v) Then Exit Function
    SafeStr = CStr(v)
End Function

' key สำหรับจับคู่ Client Name กับ อ้างอิง LN (ตัดช่องว่าง ไม่สนตัวพิมพ์ "-" = ว่าง)
Private Function KeyOf(ByVal v As Variant) As String
    Dim s As String
    s = UCase$(Replace(Trim$(Replace(SafeStr(v), ChrW(160), " ")), " ", ""))
    If s = "-" Then s = ""
    KeyOf = s
End Function

' วันที่จากค่าในเซลล์ : วันที่จริง / ข้อความ yyyy-mm-dd / ข้อความ d/m/yyyy (ปี พ.ศ. จะแปลงเป็น ค.ศ.)
Private Function ParseYMD(ByVal v As Variant, ByRef d As Date) As Boolean
    Dim s As String, p() As String, y As Long
    On Error GoTo Bad
    If VarType(v) = vbDate Then
        d = DateSerial(Year(v), Month(v), Day(v))
        ParseYMD = True
        Exit Function
    End If
    If IsNumeric(v) And Not VarType(v) = vbString Then
        If v > 20000 And v < 80000 Then
            d = CDate(Int(CDbl(v)))
            ParseYMD = True
        End If
        Exit Function
    End If
    s = Trim$(SafeStr(v))
    If Len(s) >= 10 Then
        If Left$(s, 10) Like "####-##-##" Then
            y = CLng(Left$(s, 4))
            If y > 2400 Then y = y - 543
            d = DateSerial(y, CLng(Mid$(s, 6, 2)), CLng(Mid$(s, 9, 2)))
            ParseYMD = True
            Exit Function
        End If
    End If
    If s Like "#*/#*/####*" Then
        p = Split(Split(s, " ")(0), "/")
        y = CLng(p(2))
        If y > 2400 Then y = y - 543
        d = DateSerial(y, CLng(p(1)), CLng(p(0)))
        ParseYMD = True
    End If
    Exit Function
Bad:
    ParseYMD = False
End Function

' เวลา "08:00" / "8.30" / "08.30 น." -> ค่าเวลา  (ว่าง = ว่าง, อ่านไม่ได้ = ข้อความเดิม)
Private Function HmValue(ByVal v As Variant) As Variant
    Dim s As String, p() As String
    If IsError(v) Or IsEmpty(v) Then HmValue = Empty: Exit Function
    If VarType(v) = vbDate Or (IsNumeric(v) And VarType(v) <> vbString) Then
        HmValue = CDbl(v) - Int(CDbl(v))
        Exit Function
    End If
    s = Trim$(Replace(Replace(CStr(v), "น.", ""), ".", ":"))
    If Len(s) = 0 Then HmValue = Empty: Exit Function
    If s Like "#:##" Or s Like "##:##" Or s Like "#:##:##" Or s Like "##:##:##" Then
        p = Split(s, ":")
        If CLng(p(0)) < 24 And CLng(p(1)) < 60 Then
            HmValue = CDbl(TimeSerial(CLng(p(0)), CLng(p(1)), 0))
            Exit Function
        End If
    End If
    HmValue = CStr(v)
End Function

' ---------------------------------------------------------------------------
'  งานต่างประเทศ : ดูจากคำแรกของ Client Name
'    DHL + ตัวเลข = DHL / LCL + ตัวเลข = LCL / CL + ตัวเลข = CL ตามขนาดตู้ในข้อความถัดไป (20 / 40 / 40HC)
'  คืน True = งานต่างประเทศ  vType = ประเภทรถ ("" = CL ที่ไม่ทราบขนาดตู้)  mins = นาทีที่บวกจาก Schedule
' ---------------------------------------------------------------------------
Private Function IntlType(ByVal client As String, ByRef vType As String, ByRef mins As Long) As Boolean
    Dim t() As String, w As String, nx As String, k As Long, first As String
    vType = ""
    mins = 0
    client = UCase$(Trim$(Replace(Replace(client, ChrW(160), " "), vbTab, " ")))
    Do While InStr(1, client, "  ") > 0
        client = Replace(client, "  ", " ")
    Loop
    If Len(client) = 0 Then Exit Function
    t = Split(client, " ")
    first = Replace(t(0), "-", "")
    If first Like "DHL#*" Then
        vType = "DHL": mins = MIN_DHL: IntlType = True
    ElseIf first Like "LCL#*" Then
        vType = "LCL": mins = MIN_LCL: IntlType = True
    ElseIf first Like "CL#*" Then
        IntlType = True
        For k = 1 To UBound(t)
            w = SizeWord(t(k))
            nx = ""
            If k < UBound(t) Then nx = SizeWord(t(k + 1))
            If w Like "40HC*" Or w Like "40HQ*" Or ((w = "40" Or w = "40FT") And (nx Like "HC*" Or nx Like "HQ*")) Then
                vType = "CL 40HC": mins = MIN_CL40HC
                Exit For
            ElseIf w = "40" Or w Like "40FT*" Or w Like "40GP*" Or w Like "40DC*" Or w Like "40ST*" Then
                vType = "CL 40FT": mins = MIN_CL40
                Exit For
            ElseIf w = "20" Or w Like "20FT*" Or w Like "20GP*" Or w Like "20DC*" Or w Like "20ST*" Then
                vType = "CL 20FT": mins = MIN_CL20
                Exit For
            End If
        Next k
    End If
End Function

' คำบอกขนาดตู้ : ตัดเครื่องหมาย ' ’ " ( ) , . - _ ออก และตัดจำนวนตู้  เช่น "40'HC" -> "40HC", "(20')" -> "20", "1X40HC" -> "40HC"
Private Function SizeWord(ByVal w As String) As String
    Dim ch As Variant
    For Each ch In Array("'", ChrW(&H2019), Chr(34), "(", ")", ",", ".", "-", "_")
        w = Replace(w, CStr(ch), "")
    Next ch
    If w Like "#X##*" Then w = Mid$(w, 3)
    SizeWord = w
End Function

' เวลา (เศษส่วนของวัน) + นาที  (เกินเที่ยงคืนวนกลับ 00:00)
Private Function AddMinutes(ByVal t As Double, ByVal mins As Long) As Double
    Dim m As Long
    m = CLng(Round(t * 1440, 0)) + mins
    m = ((m Mod 1440) + 1440) Mod 1440
    AddMinutes = m / 1440#
End Function

' ---------------------------------------------------------------------------
'  Task Code : D + ปปปปดดวว + "-" + ลำดับ 2 หลัก (เช่น D20261016-04)
'  ลำดับต่อจากเลขที่มากที่สุดของ : เลขล่าสุดบนเว็บ และ Task Code ที่มีอยู่แล้วในชีต Plan / Plan_Backup ของวันนั้น
'  เว็บเช็กไม่ได้ (ไม่ได้เข้าสู่ระบบ / ไม่มีเน็ต) : ถามว่าจะใช้เลขจากในไฟล์อย่างเดียวหรือไม่ (No = ยกเลิก ไม่เพิ่มแถว)
' ---------------------------------------------------------------------------
Private Function FillTaskCodes(ByRef outP() As Variant, ByVal n As Long, ByVal wsPlan As Worksheet, ByVal hdr As Long, ByRef msg As String) As Boolean
    Dim seq As Object, i As Long, d As Date, k As String, web As Long, ok As Boolean, webFail As Boolean
    Dim wsB As Worksheet, firstCode As String, lastCode As String, nCode As Long, nNoDate As Long

    Set seq = CreateObject("Scripting.Dictionary")
    ScanCodes wsPlan, hdr, seq                                   ' เลขในไฟล์ (รวมแถวที่ยังไม่ได้ส่งขึ้นระบบ)
    Set wsB = FindSheet(BACKUP_SHEET)
    If Not wsB Is Nothing Then ScanCodes wsB, PlanHeaderRow(wsB), seq

    ' เลขบนเว็บ : เรียกครั้งเดียวต่อวันที่
    For i = 1 To n
        If ParseYMD(outP(i, 2), d) Then
            k = "W" & Format$(d, "yyyymmdd")
            If Not seq.Exists(k) And Not webFail Then
                Application.ScreenUpdating = True
                ok = False
                web = DP_WebNextSeq(d, ok)
                Application.ScreenUpdating = False
                If ok Then
                    seq(k) = True
                    If web - 1 > SeqOf(seq, d) Then seq(DayKey(d)) = web - 1
                Else
                    webFail = True
                End If
            End If
        End If
    Next i
    If webFail Then
        Application.ScreenUpdating = True
        If MsgBox("เช็กเลข Task Code ล่าสุดจากเว็บไม่ได้ (ยังไม่ได้เข้าสู่ระบบ หรือไม่มีอินเทอร์เน็ต)" & vbCrLf & vbCrLf & _
                  "ใช้เลขต่อจาก Task Code ที่มีในชีต " & PLAN_SHEET & " / " & BACKUP_SHEET & " แทนหรือไม่?" & vbCrLf & _
                  "(เลขอาจซ้ำกับงานที่สร้างบนเว็บ ถ้าซ้ำ ตอนกดส่งระบบจะไม่ส่งงานนั้นและแจ้งให้ทราบ)" & vbCrLf & vbCrLf & _
                  "No = ยกเลิก ยังไม่เพิ่มแถว (เข้าสู่ระบบแล้วกดดึงแผนใหม่)", _
                  vbExclamation + vbYesNo + vbDefaultButton2, APP_TITLE) <> vbYes Then Exit Function
        Application.ScreenUpdating = False
    End If

    For i = 1 To n
        If ParseYMD(outP(i, 2), d) Then
            seq(DayKey(d)) = SeqOf(seq, d) + 1
            outP(i, 1) = "D" & Format$(d, "yyyymmdd") & "-" & Format$(seq(DayKey(d)), "00")
            nCode = nCode + 1
            If Len(firstCode) = 0 Then firstCode = outP(i, 1)
            lastCode = outP(i, 1)
        Else
            nNoDate = nNoDate + 1
        End If
    Next i
    If nCode > 0 Then msg = "Task Code " & firstCode & IIf(nCode > 1, " ถึง " & lastCode, "") & _
                            IIf(webFail, " (ใช้เลขจากในไฟล์ ไม่ได้เช็กจากเว็บ)", " (ต่อจากเลขล่าสุดบนเว็บ)")
    If nNoDate > 0 Then msg = msg & vbCrLf & "ไม่มีวันที่ ใส่ Task Code ไม่ได้ " & CStr(nNoDate) & " แถว"
    FillTaskCodes = True
End Function

' เลขลำดับสูงสุดของแต่ละวันจากคอลัมน์ A (รูปแบบ Dปปปปดดวว-nn)
Private Sub ScanCodes(ByVal ws As Worksheet, ByVal hdr As Long, ByVal seq As Object)
    Dim a As Variant, r As Long, s As String, p As Long, k As String, v As Long, lr As Long, tail As String
    If hdr = 0 Then Exit Sub
    lr = ws.Cells(ws.rows.Count, 1).End(xlUp).row
    If lr <= hdr Then Exit Sub
    a = ws.Range(ws.Cells(hdr + 1, 1), ws.Cells(lr + 1, 1)).Value       ' +1 แถว ให้เป็นตารางเสมอแม้มีแถวเดียว
    For r = 1 To UBound(a, 1)
        s = UCase$(Trim$(SafeStr(a(r, 1))))
        If s Like "D########-#*" Then
            p = InStr(1, s, "-")
            tail = Mid$(s, p + 1)
            If Len(tail) <= 4 And Not tail Like "*[!0-9]*" Then
                k = "D" & Mid$(s, 2, 8)
                v = CLng(tail)
                If v > SeqKey(seq, k) Then seq(k) = v
            End If
        End If
    Next r
End Sub

Private Function DayKey(ByVal d As Date) As String
    DayKey = "D" & Format$(d, "yyyymmdd")
End Function

Private Function SeqKey(ByVal seq As Object, ByVal k As String) As Long
    If seq.Exists(k) Then SeqKey = CLng(seq(k))
End Function

Private Function SeqOf(ByVal seq As Object, ByVal d As Date) As Long
    SeqOf = SeqKey(seq, DayKey(d))
End Function

Private Function ColLetter(ByVal c As Long) As String
    ColLetter = Split(Cells(1, c).Address(True, False), "$")(0)
End Function
