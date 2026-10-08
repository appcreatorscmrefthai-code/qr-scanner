Attribute VB_Name = "modDeliveryPlan"
Option Explicit

' ============================================================================
'  Delivery Plan : ปุ่มใน Excel สำหรับส่งแผนขึ้นระบบ และดึงข้อมูลกลับลงไฟล์
'  รุ่น 2026.10.08-y1
'
'  โครงสร้างไฟล์ (รุ่นนี้)
'    Plan         = ชีตสำหรับ "ส่งค่า" อย่างเดียว : พิมพ์/วางงานใหม่ แล้วกด ส่งงานใหม่ขึ้นระบบ
'                   คอลัมน์ A-Y ตรงกับ Plan_Backup ทุกประการ  คอลัมน์ Z = "ส่งแล้ว ปปปป-ดด-วว ชช:นน" (ส่งแล้วไม่ส่งซ้ำ)
'                   งานที่ Task Code มีบนระบบอยู่แล้ว "ไม่ถูกเขียนทับ" ให้ไปแก้ที่ชีต Plan_Backup แทน
'                   (ไฟล์เก่าที่ส่งไปแล้วหรือคอลัมน์ Z เป็นเวลาซิงก์ ไม่ถูกแตะต้อง)
'    Plan_Backup  = ชีตสำรองข้อมูลงานจากเว็บ (ดึงด้วย DP_PullAll) คอลัมน์ Z = เวลาที่แถวนี้ตรงกับระบบ
'                   ถ้าต้องการแก้งานที่มีบนระบบแล้ว ให้แก้ค่าในชีตนี้ แล้วกด ส่งค่าที่แก้ไข (DP_SendChanges)
'                   จะส่งเฉพาะแถวที่ต่างจากบนระบบ และถามก่อนถ้าถูกแก้บนระบบหลังจากที่ดึงมาล่าสุด
'    Pickup_Log / Road_Log / Edit_Log / Task_Summary / Delay_Detail / Delay_Daily / Delay_Monthly
'                 = ชีตผลลัพธ์จากการดึง Log และ Delay Trend (ดึงใหม่ทุกครั้งจะล้างข้อมูลเดิมในชีตแล้วเขียนทับ ไม่สร้างชีตซ้ำ)
'
'  มาโครที่ใช้ (Alt+F8) :
'    DP_SendNew        ส่งงานใหม่จากชีต Plan ขึ้นระบบ (เสร็จแล้วดึงข้อมูลลง Plan_Backup และเติมพิกัดจุดส่งให้อัตโนมัติ)
'    DP_SendChanges    ส่งการแก้ไขจากชีต Plan_Backup (เฉพาะแถวที่ค่าต่างจากบนระบบ ถามก่อนถ้าถูกแก้บนระบบ แล้วเติมพิกัดจุดส่งอัตโนมัติ)
'    DP_PullAll        ดึงงานทั้งหมดจากระบบ ลงชีต Plan_Backup (ไม่ทับแถวที่แก้แล้วยังไม่ได้ส่ง ถ้าเลือกให้ข้าม)
'    DP_PullLogs       ดึง Log ทั้งหมด (Pickup_Log / Road_Log / Edit_Log) และสรุปรายงาน (Task_Summary)
'    DP_PullDelay      ดึง Delay Trend ตามช่วงวันที่ที่พิมพ์ (Delay_Detail / Delay_Daily / Delay_Monthly)
'    DP_PushGPS        เลือกไฟล์ข้อมูลรถปัจจุบันจากระบบ GPS (DTCUltimate) แล้วส่งตำแหน่งรถขึ้นระบบ
'    DP_FillPlaces     เติมพิกัดจุดส่งจากลิงก์แผนที่ (ทำให้อัตโนมัติหลังส่งงานอยู่แล้ว)
'    DP_BackupAll      ดึงทุกอย่างในครั้งเดียว (Plan_Backup + Log + Task_Summary + Delay) ทั้งช่วงข้อมูล ไม่บันทึกไฟล์
'    DP_BackupFill     ใช้กับงาน Backup อัตโนมัติ (Python) : รับ access token ไม่มีหน้าต่างใดๆ ผลลัพธ์อยู่ใน DP_LastBackupResult
'    DP_SetupButtons   สร้างปุ่มทั้งหมด (รันครั้งเดียว)
'    DP_SignOut        ออกจากระบบ (ลืมการเข้าสู่ระบบที่จำไว้ระหว่างเปิดไฟล์)
'
'  ความปลอดภัย : ไฟล์นี้ไม่มีรหัสผ่านหรือกุญแจลับ ใช้การเข้าสู่ระบบของผู้ใช้แต่ละคน
'  ค่า SB_KEY คือ Publishable key ซึ่งเปิดเผยได้ (สิทธิ์ถูกควบคุมในฐานข้อมูล)
' ============================================================================

Private Const SB_URL As String = "https://crtqzyhuntrhzvaztcew.supabase.co"
Private Const SB_KEY As String = "sb_publishable_B1LhtrrMidiBuhYXnGm8TQ_zuxkLNEe"
Private Const LOGIN_DOMAIN As String = "scmdelivery.local"

Private Const APP_TITLE As String = "Delivery Plan"
Private Const PLAN_SHEET As String = "Plan"            ' ชีตส่งงานใหม่ (ส่งค่าอย่างเดียว)
Private Const BACKUP_SHEET As String = "Plan_Backup"   ' ชีตสำรองงานจากเว็บ และใช้แก้งานเดิม
Private Const NCOL As Long = 25            ' คอลัมน์ A ถึง Y ของชีต Plan / Plan_Backup
Private Const COL_SYNC As Long = 26        ' คอลัมน์ Z : Plan = ส่งแล้ว..., Plan_Backup = เวลาที่ข้อมูลแถวนี้ตรงกับระบบครั้งล่าสุด
Private Const SENT_PREFIX As String = "ส่งแล้ว"
Private Const PLAN_HEADS As String = "Task Code|Date|Detail|Client Name|Transport|Schedule|Arrival Time 1|Arrival Time 2|Arrival Time 3|ชื่อบริษัทขนส่ง|ประเภทรถ|ทะเบียนรถ|ชื่อผู้ขับ|เบอร์โทรผู้ขับ|รอบขนส่ง|จุดที่ 1|Map1|ชื่อ-เบอร์โทรผู้รับ จุดที่ 1|จุดที่ 2|Map2|ชื่อ-เบอร์โทรผู้รับ จุดที่ 2|จุดที่ 3|Map3|ชื่อ-เบอร์โทรผู้รับ จุดที่ 3|Task Status|Synced"
Private Const PLAN_FIELDS As String = "task_code,date,detail,client,transport,schedule,arr1,arr2,arr3,company,vehicle_type,plate,driver,phone,round,stop1,map1,rec1,stop2,map2,rec2,stop3,map3,rec3,status"

Private mToken As String
Private mRefresh As String
Private mExpire As Date
Private mEmail As String
Private mStatus As Long
Private mSilent As Boolean            ' True = โหมดไม่มีหน้าต่าง (DP_BackupFill)
Private mOverrideToken As String      ' access token ที่ส่งมาจากภายนอก (DP_BackupFill) ใช้แทนการเข้าสู่ระบบ
Private mLastTell As String           ' ข้อความล่าสุดที่ควรแจ้งผู้ใช้ (ใช้รายงานข้อผิดพลาดในโหมดไม่มีหน้าต่าง)
Public DP_LastBackupResult As String  ' ผลลัพธ์บรรทัดเดียวของ DP_BackupFill / DP_BackupAll
Private Const SEP_CODE As Long = 30       ' อักขระคั่นช่องภายใน (ไม่มีในข้อความปกติ)
Private mBkTotal As Long
Private mBkAdded As Long
Private mBkUpdated As Long
Private mBkKept As Long
Private mBkOverwritten As Long
Private mBkLocal As Long

Private mLgP As Long
Private mLgR As Long
Private mLgE As Long
Private mLgS As Long
Private mDlD As Long
Private mDlDay As Long
Private mDlMon As Long
Private mMute As Boolean              ' True = ไม่แสดงหน้าต่างแจ้งเตือนชั่วคราว (ขั้นตอนอัตโนมัติที่ไม่ควรขัดจังหวะการส่งงาน)
Private Const DELAY_KEYS As String = "task_code,date,stop,stop_name,company,plate,plan,arrive,diff_min,ontime,source"
Private Const TREND_KEYS As String = "period,n,ontime,late,ontime_pct,avg_diff,avg_late,max_late,gps"

' ---------------------------------------------------------------------------
'  หน้าต่างข้อความ
' ---------------------------------------------------------------------------
Private Sub Tell(ByVal msg As String, Optional ByVal warn As Boolean = False)
    mLastTell = msg
    If mSilent Or mMute Then Exit Sub
    If warn Then
        MsgBox msg, vbExclamation, APP_TITLE
    Else
        MsgBox msg, vbInformation, APP_TITLE
    End If
End Sub

Private Function Confirm(ByVal msg As String) As Boolean
    If mSilent Then Exit Function
    Confirm = (MsgBox(msg, vbQuestion + vbYesNo, APP_TITLE) = vbYes)
End Function

' คืนค่า 1 = ใช่, 2 = ไม่, 0 = ยกเลิก
Private Function Choose3(ByVal msg As String) As Long
    Dim r As Long
    If mSilent Then Exit Function
    r = MsgBox(msg, vbExclamation + vbYesNoCancel, APP_TITLE)
    If r = vbYes Then
        Choose3 = 1
    ElseIf r = vbNo Then
        Choose3 = 2
    Else
        Choose3 = 0
    End If
End Function

Private Function Ask(ByVal prompt As String, Optional ByVal def As String = "") As String
    If mSilent Then Exit Function
    Ask = InputBox(prompt, APP_TITLE, def)
End Function

' ---------------------------------------------------------------------------
'  เรียกระบบผ่านอินเทอร์เน็ต (ใช้ตัวเรียกเว็บมาตรฐานของ Windows)
' ---------------------------------------------------------------------------
Private Function Http(ByVal method As String, ByVal path As String, Optional ByVal body As String = "", Optional ByVal token As String = "", Optional ByVal accept As String = "") As String
    Dim x As Object
    Set x = CreateObject("MSXML2.XMLHTTP.6.0")
    x.Open method, SB_URL & path, False
    x.setRequestHeader "apikey", SB_KEY
    If Len(token) > 0 Then x.setRequestHeader "Authorization", "Bearer " & token
    If Len(accept) > 0 Then x.setRequestHeader "Accept", accept
    x.setRequestHeader "If-Modified-Since", "Sat, 01 Jan 2000 00:00:00 GMT"
    If Len(body) > 0 Then
        x.setRequestHeader "Content-Type", "application/json; charset=utf-8"
        x.send body
    Else
        x.send
    End If
    mStatus = x.Status
    Http = x.responseText
End Function

Private Function UrlEnc(ByVal s As String) As String
    UrlEnc = Application.WorksheetFunction.EncodeURL(s)
End Function

Private Function SEP() As String
    SEP = Chr$(SEP_CODE)
End Function

' ---------------------------------------------------------------------------
'  ข้อความ JSON / CSV / วันที่
' ---------------------------------------------------------------------------
Private Function JsonEsc(ByVal s As String) As String
    Dim i As Long
    s = Replace(s, "\", "\\")
    s = Replace(s, """", "\""")
    s = Replace(s, vbCrLf, "\n")
    s = Replace(s, vbCr, "\n")
    s = Replace(s, vbLf, "\n")
    s = Replace(s, vbTab, "\t")
    For i = 0 To 31
        If InStr(s, Chr$(i)) > 0 Then s = Replace(s, Chr$(i), " ")
    Next i
    JsonEsc = s
End Function

' อ่านค่าของ key ระดับบนสุดจากข้อความ JSON (ข้อความหรือตัวเลข) ไม่พบคืนค่าว่าง
Private Function JsonStr(ByVal json As String, ByVal key As String) As String
    Dim p As Long, n As Long, ch As String, out As String
    n = Len(json)
    p = InStr(json, """" & key & """")
    If p = 0 Then Exit Function
    p = p + Len(key) + 2
    Do While p <= n
        ch = Mid$(json, p, 1)
        If ch <> " " And ch <> ":" Then Exit Do
        p = p + 1
    Loop
    If p > n Then Exit Function
    If Mid$(json, p, 1) <> """" Then
        Do While p <= n
            ch = Mid$(json, p, 1)
            If ch = "," Or ch = "}" Or ch = "]" Then Exit Do
            out = out & ch
            p = p + 1
        Loop
        out = Trim$(out)
        If out = "null" Then out = ""
        JsonStr = out
        Exit Function
    End If
    p = p + 1
    Do While p <= n
        ch = Mid$(json, p, 1)
        If ch = """" Then Exit Do
        If ch = "\" And p < n Then
            p = p + 1
            ch = Mid$(json, p, 1)
            Select Case ch
                Case "n": out = out & vbLf
                Case "r": out = out & vbCr
                Case "t": out = out & vbTab
                Case "u"
                    If p + 4 <= n Then
                        out = out & ChrW$(CLng("&H" & Mid$(json, p + 1, 4)))
                        p = p + 4
                    End If
                Case Else: out = out & ch
            End Select
        Else
            out = out & ch
        End If
        p = p + 1
    Loop
    JsonStr = out
End Function

' ข้อความ CSV -> ชุดของแถว  แต่ละแถวเก็บเป็นข้อความเดียว คั่นช่องด้วยอักขระ SEP (ใช้ Split(แถว, SEP) เพื่อแยกเป็นช่อง เริ่มที่ 0)
Private Function ParseCsv(ByVal s As String) As Collection
    Dim rows As New Collection
    Dim i As Long, n As Long, nf As Long
    Dim ch As String, cell As String, cur As String
    Dim inQ As Boolean, hasData As Boolean
    n = Len(s)
    i = 1
    Do While i <= n
        ch = Mid$(s, i, 1)
        If inQ Then
            If ch = """" Then
                If i < n And Mid$(s, i + 1, 1) = """" Then
                    cell = cell & """"
                    i = i + 1
                Else
                    inQ = False
                End If
            ElseIf ch = SEP Then
                cell = cell & " "
            Else
                cell = cell & ch
            End If
        ElseIf ch = """" Then
            inQ = True
            hasData = True
        ElseIf ch = "," Then
            If nf > 0 Then cur = cur & SEP
            cur = cur & cell
            nf = nf + 1
            cell = ""
            hasData = True
        ElseIf ch = vbCr Or ch = vbLf Then
            If ch = vbCr And i < n Then
                If Mid$(s, i + 1, 1) = vbLf Then i = i + 1
            End If
            If hasData Or Len(cell) > 0 Then
                If nf > 0 Then cur = cur & SEP
                cur = cur & cell
                rows.Add cur
            End If
            nf = 0
            cur = ""
            cell = ""
            hasData = False
        ElseIf ch = SEP Then
            cell = cell & " "
            hasData = True
        Else
            cell = cell & ch
            hasData = True
        End If
        i = i + 1
    Loop
    If hasData Or Len(cell) > 0 Then
        If nf > 0 Then cur = cur & SEP
        cur = cur & cell
        rows.Add cur
    End If
    Set ParseCsv = rows
End Function

' แยกแถวที่ได้จาก ParseCsv เป็นช่อง และเติมช่องว่างให้ครบอย่างน้อย minFields ช่อง
Private Function Fields(ByVal rowText As String, ByVal minFields As Long) As Variant
    Dim n As Long
    n = Len(rowText) - Len(Replace(rowText, SEP, "")) + 1
    If n < minFields Then rowText = rowText & String$(minFields - n, SEP)
    Fields = Split(rowText, SEP)
End Function

Private Function Pad2(ByVal n As Long) As String
    Pad2 = Right$("0" & CStr(n), 2)
End Function

' วันที่ -> "2026-10-06" (ใช้ปี ค.ศ. เสมอ แม้เครื่องตั้งปฏิทินเป็น พ.ศ.)
Private Function IsoDate(ByVal d As Date) As String
    Dim y As Long
    y = Year(d)
    If y > 2400 Then y = y - 543
    IsoDate = CStr(y) & "-" & Pad2(Month(d)) & "-" & Pad2(Day(d))
End Function

' "2026-10-06", "2026-10-06 14:30" หรือ "2026-10-06 14:30:05" -> วันที่  (ไม่ถูกรูปแบบคืน False)
Private Function ParseIso(ByVal s As String, ByRef d As Date) As Boolean
    On Error GoTo Bad
    s = Trim$(s)
    If Len(s) < 10 Then GoTo Bad
    If Mid$(s, 5, 1) <> "-" Or Mid$(s, 8, 1) <> "-" Then GoTo Bad
    d = DateSerial(CInt(Left$(s, 4)), CInt(Mid$(s, 6, 2)), CInt(Mid$(s, 9, 2)))
    If Len(s) >= 19 Then
        d = d + TimeSerial(CInt(Mid$(s, 12, 2)), CInt(Mid$(s, 15, 2)), CInt(Mid$(s, 18, 2)))
    ElseIf Len(s) >= 16 Then
        d = d + TimeSerial(CInt(Mid$(s, 12, 2)), CInt(Mid$(s, 15, 2)), 0)
    End If
    ParseIso = True
    Exit Function
Bad:
    ParseIso = False
End Function

' วันที่ที่ผู้ใช้พิมพ์ : 2026-10-06, 6/10/2026, 6/10/2569 -> "2026-10-06" (ไม่ถูกรูปแบบคืนค่าว่าง)
Private Function UserDate(ByVal s As String) As String
    Dim p() As String, y As Long, m As Long, d As Long
    On Error GoTo Bad
    s = Trim$(s)
    s = Replace(s, "/", "-")
    s = Replace(s, ".", "-")
    p = Split(s, "-")
    If UBound(p) <> 2 Then GoTo Bad
    If Len(p(0)) = 4 Then
        y = CLng(p(0)): m = CLng(p(1)): d = CLng(p(2))
    Else
        d = CLng(p(0)): m = CLng(p(1)): y = CLng(p(2))
    End If
    If y < 100 Then y = y + 2000
    If y > 2400 Then y = y - 543
    If m < 1 Or m > 12 Or d < 1 Or d > 31 Or y < 2000 Or y > 2100 Then GoTo Bad
    UserDate = CStr(y) & "-" & Pad2(m) & "-" & Pad2(d)
    Exit Function
Bad:
    UserDate = ""
End Function

' "7:30", "07.30" -> "07:30"  (ไม่ใช่เวลาคืนข้อความเดิม)
Private Function HmNorm(ByVal s As String) As String
    Dim p As Long, h As String, m As String
    s = Trim$(s)
    HmNorm = s
    p = InStr(s, ":")
    If p = 0 Then p = InStr(s, ".")
    If p < 2 Or p > 3 Then Exit Function
    h = Left$(s, p - 1)
    m = Mid$(s, p + 1, 2)
    If Len(m) <> 2 Then Exit Function
    If Not IsNumeric(h) Or Not IsNumeric(m) Then Exit Function
    HmNorm = Pad2(CLng(h)) & ":" & m
End Function

' ตัดช่องว่างซ้ำ และถือว่า "-" คือค่าว่าง (ใช้เทียบค่าในไฟล์กับค่าบนระบบ)
Private Function Norm(ByVal s As String) As String
    s = Replace(s, vbCr, " ")
    s = Replace(s, vbLf, " ")
    s = Replace(s, vbTab, " ")
    s = Replace(s, ChrW$(160), " ")
    s = Trim$(s)
    Do While InStr(s, "  ") > 0
        s = Replace(s, "  ", " ")
    Loop
    If s = "-" Then s = ""
    Norm = s
End Function

' ค่าสองค่าในคอลัมน์ c ต่างกันหรือไม่ (ทะเบียนรถไม่นับช่องว่าง เพราะระบบจัดรูปแบบทะเบียนให้ เช่น 9กข9999 = 9 กข 9999)
Private Function Differs(ByVal c As Long, ByVal a As String, ByVal b As String) As Boolean
    a = Norm(a)
    b = Norm(b)
    If c = 12 Then
        a = UCase$(Replace(a, " ", ""))
        b = UCase$(Replace(b, " ", ""))
    End If
    Differs = (a <> b)
End Function

' ข้อความที่จะเขียนลงช่อง : กันไม่ให้ Excel ตีความเป็นสูตร ตัวเลข หรือวันที่ (เช่น หมายเหตุที่ขึ้นต้นด้วย = หรือเวลา 19:00)
Private Function SafeText(ByVal s As String) As String
    Dim c As String
    c = Left$(s, 1)
    If c = "=" Or c = "+" Or c = "-" Or c = "@" Or c = "'" Or IsNumeric(s) Or IsDate(s) Then
        SafeText = "'" & s
    Else
        SafeText = s
    End If
End Function

' ---------------------------------------------------------------------------
'  ชุดข้อมูลแบบมีชื่อ (Collection ที่ใช้ key)
' ---------------------------------------------------------------------------
Private Function HasKey(ByVal c As Collection, ByVal key As String) As Boolean
    Dim v As Variant
    On Error GoTo Miss
    v = c.Item(key)
    HasKey = True
    Exit Function
Miss:
    HasKey = False
End Function

' ---------------------------------------------------------------------------
'  เข้าสู่ระบบ (จำไว้เฉพาะระหว่างที่ไฟล์เปิดอยู่ ไม่บันทึกลงไฟล์)
' ---------------------------------------------------------------------------
Private Sub StoreSession(ByVal r As String)
    Dim sec As Long
    mToken = JsonStr(r, "access_token")
    mRefresh = JsonStr(r, "refresh_token")
    sec = 3600
    If IsNumeric(JsonStr(r, "expires_in")) Then sec = CLng(JsonStr(r, "expires_in"))
    If sec < 300 Then sec = 300
    mExpire = DateAdd("s", sec - 120, Now)
End Sub

Private Function ErrText(ByVal r As String) As String
    Dim m As String
    m = JsonStr(r, "message")
    If Len(m) = 0 Then m = JsonStr(r, "msg")
    If Len(m) = 0 Then m = JsonStr(r, "error_description")
    If m = "FORBIDDEN" Then
        ' ล้างการเข้าสู่ระบบที่จำไว้ เพื่อให้กดปุ่มครั้งถัดไปแล้วเลือกผู้ใช้ใหม่ได้
        mToken = ""
        mRefresh = ""
        mEmail = ""
        m = "ผู้ใช้นี้ดูได้อย่างเดียว ไม่มีสิทธิ์ส่งหรือแก้ไขแผน" & vbCrLf & vbCrLf & "กดปุ่มอีกครั้งเพื่อเข้าสู่ระบบด้วยผู้ใช้ที่มีสิทธิ์แก้ไข"
    End If
    If m = "BAD_RANGE" Then m = "ช่วงวันที่ไม่ถูกต้อง หรือกว้างเกินที่ระบบกำหนด"
    If m = "AUTH" Then m = "บัญชีนี้ยังไม่ได้รับสิทธิ์ใช้งาน หรือถูกปิดการใช้งาน"
    If Len(m) = 0 Then m = "ระบบตอบกลับผิดปกติ (HTTP " & CStr(mStatus) & ")"
    ErrText = m
End Function

' คืนโทเคนที่ใช้ได้ (ถ้ายังไม่เข้าสู่ระบบจะถามอีเมลและรหัสผ่าน) ยกเลิกคืนค่าว่าง
Private Function GetToken() As String
    Dim r As String, email As String, pw As String
    If Len(mOverrideToken) > 0 Then
        GetToken = mOverrideToken
        Exit Function
    End If
    If mSilent Then Exit Function
    If Len(mToken) > 0 And Now < mExpire Then
        GetToken = mToken
        Exit Function
    End If
    If Len(mRefresh) > 0 Then
        r = Http("POST", "/auth/v1/token?grant_type=refresh_token", "{""refresh_token"":""" & JsonEsc(mRefresh) & """}")
        If mStatus = 200 Then
            StoreSession r
            GetToken = mToken
            Exit Function
        End If
        mToken = ""
        mRefresh = ""
    End If
    email = Trim$(Ask("เข้าสู่ระบบ Delivery Plan" & vbCrLf & vbCrLf & "อีเมลหรือชื่อผู้ใช้ (ต้องเป็นผู้ใช้ที่มีสิทธิ์แก้ไข)", mEmail))
    If Len(email) = 0 Then Exit Function
    email = LCase$(email)
    If InStr(email, "@") = 0 Then email = email & "@" & LOGIN_DOMAIN
    pw = Ask("รหัสผ่านของ " & email & vbCrLf & vbCrLf & "ข้อควรระวัง: ตัวอักษรที่พิมพ์จะแสดงบนจอ และระบบจะจำการเข้าสู่ระบบไว้จนกว่าจะปิดไฟล์นี้")
    If Len(pw) = 0 Then Exit Function
    r = Http("POST", "/auth/v1/token?grant_type=password", "{""email"":""" & JsonEsc(email) & """,""password"":""" & JsonEsc(pw) & """}")
    If mStatus <> 200 Then
        If mStatus = 400 Or mStatus = 401 Then
            Tell "เข้าสู่ระบบไม่สำเร็จ: อีเมลหรือรหัสผ่านไม่ถูกต้อง", True
        Else
            Tell "เข้าสู่ระบบไม่สำเร็จ: " & ErrText(r), True
        End If
        Exit Function
    End If
    StoreSession r
    mEmail = email
    GetToken = mToken
End Function

' เรียกระบบด้วยโทเคนของผู้ใช้ ถ้าโทเคนหมดอายุจะต่ออายุแล้วลองอีกครั้ง  (ok = False เมื่อผู้ใช้ยกเลิกการเข้าสู่ระบบ)
Private Function Api(ByVal method As String, ByVal path As String, ByVal body As String, ByVal accept As String, ByRef ok As Boolean) As String
    Dim t As String, r As String
    ok = False
    t = GetToken()
    If Len(t) = 0 Then Exit Function
    r = Http(method, path, body, t, accept)
    If mStatus = 401 Then
        mToken = ""
        t = GetToken()
        If Len(t) = 0 Then Exit Function
        r = Http(method, path, body, t, accept)
    End If
    ok = True
    Api = r
End Function

' ---------------------------------------------------------------------------
'  ชีต Plan (ส่งงานใหม่) และ Plan_Backup (สำรองงานจากเว็บ / แก้งานเดิม)
' ---------------------------------------------------------------------------
Private Sub ScreenOn(ByVal v As Boolean)
    On Error Resume Next
    Application.ScreenUpdating = v
    If v Then Application.StatusBar = False
End Sub

Private Function FindSheet(ByVal name As String) As Worksheet
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Worksheets(name)
    On Error GoTo 0
    Set FindSheet = ws
End Function

' เพิ่มชีตใหม่ต่อท้ายชีต afterWs แล้วกลับไปที่ชีตที่ผู้ใช้เปิดอยู่เดิม
Private Function NewSheet(ByVal name As String, ByVal afterWs As Worksheet) As Worksheet
    Dim ws As Worksheet, prev As Object
    On Error Resume Next
    Set prev = ActiveSheet
    On Error GoTo 0
    Set ws = ThisWorkbook.Worksheets.Add(After:=afterWs)
    ws.Name = name
    On Error Resume Next
    If Not prev Is Nothing Then prev.Activate
    On Error GoTo 0
    Set NewSheet = ws
End Function

Private Function PlanSheet() As Worksheet
    Dim ws As Worksheet
    Set ws = FindSheet(PLAN_SHEET)
    If ws Is Nothing Then Tell "ไม่พบชีตชื่อ " & PLAN_SHEET & " ในไฟล์นี้", True
    Set PlanSheet = ws
End Function

' แถวหัวตาราง = แถวที่คอลัมน์ A เขียนว่า Task Code (หาใน 10 แถวแรก) ไม่พบคืน 0
Private Function HeaderRow(ByVal ws As Worksheet) As Long
    Dim r As Long
    For r = 1 To 10
        If LCase$(Trim$(CStr(ws.Cells(r, 1).Value))) = "task code" Then
            HeaderRow = r
            Exit Function
        End If
    Next r
    HeaderRow = 0
End Function

' คัดลอกหัวตาราง (ค่า + รูปแบบ + ความกว้างคอลัมน์) จากชีต Plan ไปชีตสำรอง ให้หน้าตาเหมือนกัน
Private Sub CopyHeader(ByVal src As Worksheet, ByVal hp As Long, ByVal dst As Worksheet)
    Dim r As Long, c As Long
    On Error Resume Next
    src.Range(src.Cells(1, 1), src.Cells(hp, COL_SYNC)).Copy dst.Cells(1, 1)
    If Err.Number <> 0 Then
        Err.Clear
        For r = 1 To hp
            For c = 1 To COL_SYNC
                dst.Cells(r, c).Value = src.Cells(r, c).Value
                dst.Cells(r, c).Font.Bold = src.Cells(r, c).Font.Bold
                dst.Cells(r, c).Interior.Color = src.Cells(r, c).Interior.Color
            Next c
        Next r
    End If
    Err.Clear
    For c = 1 To COL_SYNC
        dst.Columns(c).ColumnWidth = src.Columns(c).ColumnWidth
    Next c
    Application.CutCopyMode = False
End Sub

' ชีตสำรอง Plan_Backup : makeIt = True จะสร้างให้ถ้ายังไม่มี (หัวตารางเหมือนชีต Plan) ไม่พบและไม่สร้างจะแจ้งเตือน
Private Function BackupSheet(ByVal makeIt As Boolean) As Worksheet
    Dim ws As Worksheet, wp As Worksheet, hp As Long, hdr As Long, h() As String, i As Long, isNew As Boolean
    Set ws = FindSheet(BACKUP_SHEET)
    If ws Is Nothing Then
        If Not makeIt Then
            Tell "ไม่พบชีต " & BACKUP_SHEET & " ในไฟล์นี้" & vbCrLf & "กดปุ่มดึงข้อมูลลง " & BACKUP_SHEET & " ก่อน (ระบบจะสร้างชีตให้)", True
            Exit Function
        End If
        Set wp = FindSheet(PLAN_SHEET)
        If wp Is Nothing Then
            Set ws = NewSheet(BACKUP_SHEET, ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
        Else
            Set ws = NewSheet(BACKUP_SHEET, wp)
        End If
        isNew = True
        If Not wp Is Nothing Then
            hp = HeaderRow(wp)
            If hp > 0 Then CopyHeader wp, hp, ws
        End If
    End If
    hdr = HeaderRow(ws)
    If hdr = 0 Then
        h = Split(PLAN_HEADS, "|")
        For i = 0 To UBound(h)
            ws.Cells(1, i + 1).Value = h(i)
        Next i
        ws.Rows(1).Font.Bold = True
        hdr = 1
    End If
    If isNew Then ws.Cells(hdr, COL_SYNC).Value = "Synced"
    EnsureSyncHeader ws, hdr, "Synced"
    BackupNote ws, hdr
    Set BackupSheet = ws
End Function

' ข้อความอธิบายบนชีต Plan_Backup (ตัวหนังสือด้านขวาของตาราง + ข้อความกำกับที่ช่องหัวตาราง Task Code)
Private Sub BackupNote(ByVal ws As Worksheet, ByVal hdr As Long)
    Dim t As String
    t = "ชีตนี้คือสำเนาสำรองของงานบนเว็บ (ดึงมาจากระบบ) ถ้าต้องการแก้งานที่ส่งขึ้นระบบแล้ว ให้แก้ค่าในชีตนี้ แล้วกด ส่งค่าที่แก้ไข (ส่งเฉพาะช่องที่ต่างจากบนระบบ)" & _
        " ส่วนงานใหม่ให้พิมพ์ที่ชีต " & PLAN_SHEET & " แล้วกด ส่งงานใหม่ขึ้นระบบ  คอลัมน์ Z = เวลาที่แถวนี้ตรงกับระบบล่าสุด (อย่าแก้)"
    On Error Resume Next
    If Len(Trim$(CStr(ws.Cells(4, COL_SYNC + 2).Value))) = 0 Then ws.Cells(4, COL_SYNC + 2).Value = t
    If ws.Cells(hdr, 1).Comment Is Nothing Then ws.Cells(hdr, 1).AddComment t
End Sub

' บันทึกผลล่าสุดของการ Backup ไว้ที่ช่องสถานะข้างตาราง (ใช้ดูย้อนหลังว่างาน Backup อัตโนมัติรันเมื่อไร)
Private Sub StampBackupResult(ByVal result As String)
    Dim ws As Worksheet
    Set ws = FindSheet(BACKUP_SHEET)
    If ws Is Nothing Then Exit Sub
    On Error Resume Next
    ws.Cells(5, COL_SYNC + 2).NumberFormat = "@"
    ws.Cells(5, COL_SYNC + 2).Value = "Backup ล่าสุด " & IsoDate(Date) & " " & HmNow() & " : " & result
End Sub

' ค่าในช่องเป็นข้อความสำหรับส่งขึ้นระบบ (วันที่ = ปปปป-ดด-วว, เวลา = ชช:นน)
Private Function CellText(ByVal ws As Worksheet, ByVal r As Long, ByVal c As Long) As String
    Dim v As Variant, t As String, x As Double
    v = ws.Cells(r, c).Value
    If IsError(v) Then Exit Function
    If IsEmpty(v) Then Exit Function
    If VarType(v) = vbString Then
        CellText = Trim$(CStr(v))
        If c >= 6 And c <= 9 Then CellText = HmNorm(CellText)
        Exit Function
    End If
    If c = 2 Then
        If VarType(v) = vbDate Or IsNumeric(v) Then
            CellText = IsoDate(CDate(v))
        Else
            CellText = Trim$(CStr(v))
        End If
    ElseIf c >= 6 And c <= 9 Then
        If VarType(v) = vbDate Or IsNumeric(v) Then
            x = CDbl(v)
            x = x - Int(x)
            x = x + 0.5 / 86400#
            CellText = Pad2(Int(x * 24)) & ":" & Pad2(Int(x * 1440) Mod 60)
        Else
            CellText = Trim$(CStr(v))
        End If
    Else
        t = CStr(ws.Cells(r, c).Text)
        If Len(t) = 0 Or InStr(t, "#") > 0 Then t = CStr(v)
        CellText = Trim$(t)
    End If
End Function

' เหมือน CellText แต่รับค่าที่อ่านมาเป็นอาร์เรย์ (อ่านทั้งช่วงครั้งเดียวเร็วกว่าอ่านทีละช่อง)
Private Function VText(ByVal v As Variant, ByVal c As Long) As String
    Dim x As Double
    If IsError(v) Then Exit Function
    If IsEmpty(v) Then Exit Function
    If VarType(v) = vbString Then
        VText = Trim$(CStr(v))
        If c >= 6 And c <= 9 Then VText = HmNorm(VText)
        Exit Function
    End If
    If c = 2 Then
        If VarType(v) = vbDate Or IsNumeric(v) Then
            VText = IsoDate(CDate(v))
        Else
            VText = Trim$(CStr(v))
        End If
    ElseIf c >= 6 And c <= 9 Then
        If VarType(v) = vbDate Or IsNumeric(v) Then
            x = CDbl(v)
            x = x - Int(x)
            x = x + 0.5 / 86400#
            VText = Pad2(Int(x * 24)) & ":" & Pad2(Int(x * 1440) Mod 60)
        Else
            VText = Trim$(CStr(v))
        End If
    Else
        VText = Trim$(CStr(v))
    End If
End Function

' ทุกแถวข้อมูลในชีต (แถวที่มี Task Code) เรียงจากบนลงล่าง
Private Function AllRows(ByVal ws As Worksheet, ByVal hdr As Long) As Collection
    Dim out As New Collection
    Dim r As Long, lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
    For r = hdr + 1 To lastRow
        If Len(Trim$(CStr(ws.Cells(r, 1).Value))) > 0 Then out.Add r
    Next r
    If out.Count = 0 Then Tell "ไม่พบแถวข้อมูลในชีต " & ws.Name & " (ต้องมี Task Code ใต้หัวตาราง)", True
    Set AllRows = out
End Function

' ดึงข้อมูลแผนของ Task Code ที่ระบุจากระบบ : คืนชุดข้อมูล key = Task Code (ตัวพิมพ์ใหญ่) ค่า = ข้อความ 27 ช่อง (25 คอลัมน์ + synced + updated_by) แยกด้วย Fields()
Private Function FetchPlan(ByVal codes As Collection, ByRef ok As Boolean) As Collection
    Dim out As New Collection, rows As Collection
    Dim i As Long, k As Long, lst As String, r As String, row As Variant
    Set FetchPlan = out
    i = 1
    Do While i <= codes.Count
        lst = ""
        For k = i To i + 39
            If k > codes.Count Then Exit For
            If Len(lst) > 0 Then lst = lst & ","
            lst = lst & """" & Replace(CStr(codes.Item(k)), """", "") & """"
        Next k
        r = Api("GET", "/rest/v1/v_plan?select=*&task_code=in.(" & UrlEnc(lst) & ")", "", "text/csv", ok)
        If Not ok Then Exit Function
        If mStatus <> 200 Then
            ok = False
            Tell "อ่านข้อมูลจากระบบไม่สำเร็จ: " & ErrText(r), True
            Exit Function
        End If
        Set rows = ParseCsv(r)
        For k = 2 To rows.Count
            row = Fields(CStr(rows.Item(k)), NCOL + 2)
            If Len(row(0)) > 0 Then
                If Not HasKey(out, UCase$(row(0))) Then out.Add CStr(rows.Item(k)), UCase$(row(0))
            End If
        Next k
        i = i + 40
    Loop
    ok = True
End Function

' ดึงงานทั้งหมดบนระบบ (เรียงตามวันที่ แล้ว Task Code) : คืนชุดข้อความของแต่ละแถว ใช้ Fields(แถว, 27)
Private Function FetchAllPlan(ByRef ok As Boolean) As Collection
    Dim out As New Collection, rows As Collection, r As String, offset As Long, k As Long
    Set FetchAllPlan = out
    ok = False
    offset = 0
    Do
        r = Api("GET", "/rest/v1/v_plan?select=*&order=date.asc,task_code.asc&limit=1000&offset=" & CStr(offset), "", "text/csv", ok)
        If Not ok Then Exit Function
        If mStatus <> 200 And mStatus <> 206 Then
            ok = False
            Tell "อ่านข้อมูลงานจากระบบไม่สำเร็จ: " & ErrText(r), True
            Exit Function
        End If
        Set rows = ParseCsv(r)
        For k = 2 To rows.Count
            out.Add CStr(rows.Item(k))
        Next k
        offset = offset + 1000
    Loop While rows.Count >= 1001
    ok = True
End Function

Private Sub EnsureSyncHeader(ByVal ws As Worksheet, ByVal hdr As Long, ByVal title As String)
    If Len(Trim$(CStr(ws.Cells(hdr, COL_SYNC).Value))) = 0 Then ws.Cells(hdr, COL_SYNC).Value = title
End Sub

Private Sub WriteSync(ByVal ws As Worksheet, ByVal r As Long, ByVal stamp As String)
    ws.Cells(r, COL_SYNC).NumberFormat = "@"
    ws.Cells(r, COL_SYNC).Value = stamp
End Sub

' เวลาปัจจุบัน ชช:นน
Private Function HmNow() As String
    HmNow = Pad2(Hour(Now)) & ":" & Pad2(Minute(Now))
End Function

Private Function SentStamp() As String
    SentStamp = SENT_PREFIX & " " & IsoDate(Date) & " " & HmNow()
End Function

Private Function IsSentStamp(ByVal z As String) As Boolean
    IsSentStamp = (Left$(Trim$(z), Len(SENT_PREFIX)) = SENT_PREFIX)
End Function

' ---------------------------------------------------------------------------
'  2) ดึงงานทั้งหมดจากระบบ ลงชีต Plan_Backup
'     แถวที่ผู้ใช้แก้ในชีตแล้วยังไม่ได้ส่ง (ค่าต่างจากระบบ แต่เวลาในคอลัมน์ Z ยังตรงกับระบบ) ถามก่อนว่าจะทับหรือข้าม
'     แถวที่ไม่มีบนระบบ (ผู้ใช้พิมพ์เอง / งานถูกลบจากระบบ) เก็บไว้ท้ายตาราง ไม่ลบ
' ---------------------------------------------------------------------------
' ช่องว่างเขียนเป็น "" (Excel ถือเป็นช่องว่าง) ไม่ใช้ Empty เพื่อไม่ให้ช่องกลายเป็น 0 ในบางโปรแกรม
Private Function NZ(ByVal v As Variant) As Variant
    If IsEmpty(v) Then
        NZ = ""
    Else
        NZ = v
    End If
End Function

Private Function ServerCellValue(ByVal sv As String, ByVal c As Long) As Variant
    Dim d As Date, p As Long
    ServerCellValue = ""
    If Len(sv) = 0 Then Exit Function
    If c = 2 Then
        If ParseIso(sv, d) Then
            ServerCellValue = d
        Else
            ServerCellValue = sv
        End If
    ElseIf c >= 6 And c <= 9 Then
        p = InStr(sv, ":")
        If p > 0 And IsNumeric(Left$(sv, p - 1)) And IsNumeric(Mid$(sv, p + 1, 2)) Then
            ServerCellValue = CDbl(TimeSerial(CInt(Left$(sv, p - 1)), CInt(Mid$(sv, p + 1, 2)), 0))
        Else
            ServerCellValue = sv
        End If
    Else
        ServerCellValue = sv
    End If
End Function

' เขียนงานทั้งหมดลงชีตสำรอง (ล้างข้อมูลเดิมแล้วเขียนทับทั้งช่วงครั้งเดียว) คืน False ถ้าผู้ใช้กดยกเลิก
Private Function WriteBackup(ByVal plan As Collection, ByVal ws As Worksheet, ByVal hdr As Long, ByVal askUser As Boolean) As Boolean
    Dim lastRow As Long, nOld As Long, vOld As Variant, i As Long, c As Long, key As String
    Dim srv As New Collection, f As Variant, g As Variant, idx As Long, oldOf As New Collection, keep As New Collection
    Dim localRows As New Collection, seen As New Collection
    Dim diff As Boolean, zl As String, nUnsent As Long, pick As Long, hasData As Boolean
    Dim nOut As Long, vals() As Variant, o As Long, clearTo As Long, ln As Long

    mBkTotal = 0: mBkAdded = 0: mBkUpdated = 0: mBkKept = 0: mBkOverwritten = 0: mBkLocal = 0

    ' งานบนระบบ : รหัส -> ลำดับในรายการ (ตัวแรกที่เจอ)
    For i = 1 To plan.Count
        f = Fields(CStr(plan.Item(i)), NCOL + 2)
        key = UCase$(Trim$(CStr(f(0))))
        If Len(key) > 0 Then
            If Not HasKey(srv, key) Then srv.Add i, key
        End If
    Next i

    ' ข้อมูลเดิมในชีต (อ่านครั้งเดียวทั้งช่วง)
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
    nOld = lastRow - hdr
    If nOld > 0 Then vOld = ws.Range(ws.Cells(hdr + 1, 1), ws.Cells(lastRow, COL_SYNC)).Value
    For i = 1 To nOld
        key = UCase$(VText(vOld(i, 1), 1))
        If Len(key) > 0 And Not HasKey(seen, key) And HasKey(srv, key) Then
            seen.Add True, key
            oldOf.Add i, key
            f = Fields(CStr(plan.Item(CLng(srv.Item(key)))), NCOL + 2)
            diff = False
            For c = 2 To NCOL
                If Differs(c, CStr(f(c - 1)), VText(vOld(i, c), c)) Then
                    diff = True
                    Exit For
                End If
            Next c
            If diff Then
                mBkUpdated = mBkUpdated + 1
                zl = VText(vOld(i, COL_SYNC), COL_SYNC)
                If zl = CStr(f(NCOL)) Then
                    nUnsent = nUnsent + 1
                    keep.Add i, key
                End If
            End If
        Else
            hasData = False
            For c = 1 To NCOL
                If Len(VText(vOld(i, c), c)) > 0 Then hasData = True: Exit For
            Next c
            If hasData Then localRows.Add i
        End If
    Next i

    If nUnsent > 0 Then
        If askUser Then
            pick = Choose3("ในชีต " & ws.Name & " มี " & CStr(nUnsent) & " งานที่แก้ค่าไว้แล้วแต่ยังไม่ได้ส่งขึ้นระบบ" & vbCrLf & vbCrLf & _
                           "กด Yes = ดึงทับ (ค่าที่แก้ไว้ในไฟล์จะหายไป)" & vbCrLf & _
                           "กด No = ข้าม " & CStr(nUnsent) & " งานนี้ (ยังคงค่าที่แก้ไว้ ดึงเฉพาะงานอื่น)" & vbCrLf & _
                           "กด Cancel = ยกเลิกการดึงข้อมูล (ไปกดส่งค่าที่แก้ไขก่อนได้)")
            If pick = 0 Then Exit Function
            If pick = 1 Then
                mBkOverwritten = nUnsent
                Set keep = New Collection
            End If
        End If
    End If
    mBkKept = keep.Count

    ' ประกอบข้อมูลที่จะเขียน : งานบนระบบตามลำดับ แล้วต่อด้วยแถวที่ไม่มีบนระบบ
    nOut = srv.Count + localRows.Count
    mBkTotal = srv.Count
    mBkLocal = localRows.Count
    If nOut > 0 Then
        ReDim vals(1 To nOut, 1 To COL_SYNC)
        o = 0
        For i = 1 To plan.Count
            f = Fields(CStr(plan.Item(i)), NCOL + 2)
            key = UCase$(Trim$(CStr(f(0))))
            If Len(key) > 0 Then
                If CLng(srv.Item(key)) = i Then
                    o = o + 1
                    If HasKey(keep, key) Then
                        idx = CLng(keep.Item(key))
                        For c = 1 To COL_SYNC
                            vals(o, c) = NZ(vOld(idx, c))
                        Next c
                    Else
                        For c = 1 To NCOL
                            If c = 1 Then
                                vals(o, c) = CStr(f(0))
                            Else
                                vals(o, c) = ServerCellValue(CStr(f(c - 1)), c)
                            End If
                        Next c
                        vals(o, COL_SYNC) = CStr(f(NCOL))
                    End If
                    If Not HasKey(oldOf, key) Then mBkAdded = mBkAdded + 1
                End If
            End If
        Next i
        For i = 1 To localRows.Count
            o = o + 1
            idx = CLng(localRows.Item(i))
            For c = 1 To COL_SYNC
                vals(o, c) = NZ(vOld(idx, c))
            Next c
        Next i
    End If

    ' ล้างของเดิมทั้งช่วงแล้วเขียนใหม่
    clearTo = lastRow
    If hdr + nOut > clearTo Then clearTo = hdr + nOut
    If clearTo > hdr Then ws.Range(ws.Cells(hdr + 1, 1), ws.Cells(clearTo, COL_SYNC)).ClearContents
    If nOut > 0 Then
        ln = hdr + nOut
        ws.Range(ws.Cells(hdr + 1, 1), ws.Cells(ln, COL_SYNC)).NumberFormat = "@"
        ws.Range(ws.Cells(hdr + 1, 2), ws.Cells(ln, 2)).NumberFormat = "yyyy-mm-dd"
        ws.Range(ws.Cells(hdr + 1, 6), ws.Cells(ln, 9)).NumberFormat = "hh:mm"
        ws.Range(ws.Cells(hdr + 1, 1), ws.Cells(ln, COL_SYNC)).Value = vals
    End If
    WriteBackup = True
End Function

Public Sub DP_PullAll()
    Dim ws As Worksheet, hdr As Long, plan As Collection, ok As Boolean

    On Error GoTo Fail
    ScreenOn False
    If Len(GetToken()) = 0 Then GoTo Done
    Set ws = BackupSheet(True)
    If ws Is Nothing Then GoTo Done
    hdr = HeaderRow(ws)
    Set plan = FetchAllPlan(ok)
    If Not ok Then GoTo Done
    If Not WriteBackup(plan, ws, hdr, True) Then GoTo Done
    ScreenOn True

    Tell "ดึงงานทั้งหมดจากระบบลงชีต " & BACKUP_SHEET & " แล้ว " & CStr(mBkTotal) & " งาน" & vbCrLf & _
         "เพิ่มใหม่ " & CStr(mBkAdded) & " งาน, อัปเดตค่าที่ต่างจากเดิม " & CStr(mBkUpdated - mBkKept) & " งาน" & _
         IIf(mBkKept > 0, vbCrLf & "ข้ามไม่ทับ " & CStr(mBkKept) & " งานที่แก้ไว้แล้วยังไม่ได้ส่ง (ใช้ปุ่มส่งค่าที่แก้ไข)", "") & _
         IIf(mBkLocal > 0, vbCrLf & "แถวที่ไม่พบบนระบบ (เก็บไว้ท้ายตาราง ไม่ลบ) " & CStr(mBkLocal) & " แถว", "")
    Exit Sub
Done:
    ScreenOn True
    Exit Sub
Fail:
    ScreenOn True
    Tell "เกิดข้อผิดพลาด: " & Err.Description & vbCrLf & vbCrLf & "ถ้าเป็นปัญหาการเชื่อมต่อ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่", True
End Sub

' ดึงข้อมูลลงชีต Plan_Backup แบบเงียบๆ หลังส่งงานใหม่ (ไม่ถามผู้ใช้ ไม่ทับแถวที่แก้ค้างอยู่ ถ้าผิดพลาดแค่แจ้งบรรทัดเดียว ไม่กระทบการส่ง)
Private Function RefreshBackupAuto(ByRef wsB As Worksheet, ByRef hdrB As Long) As String
    Dim plan As Collection, ok As Boolean
    On Error GoTo Fail
    mMute = True
    Set wsB = BackupSheet(True)
    If wsB Is Nothing Then GoTo Fail
    hdrB = HeaderRow(wsB)
    Set plan = FetchAllPlan(ok)
    If Not ok Then GoTo Fail
    If Not WriteBackup(plan, wsB, hdrB, False) Then GoTo Fail
    mMute = False
    RefreshBackupAuto = "อัปเดตชีต " & BACKUP_SHEET & " แล้ว (" & CStr(mBkTotal) & " งาน) งานใหม่จะอยู่ในชีตนั้น"
    Exit Function
Fail:
    mMute = False
    RefreshBackupAuto = "อัปเดตชีต " & BACKUP_SHEET & " อัตโนมัติไม่สำเร็จ (กดปุ่มดึงข้อมูลลง " & BACKUP_SHEET & " อีกครั้งได้)"
End Function

' ---------------------------------------------------------------------------
'  1) ส่งงานใหม่จากชีต Plan ขึ้นระบบ
'     - ส่งเฉพาะแถวที่ Task Code ยังไม่มีบนระบบ และยังไม่ได้ประทับ "ส่งแล้ว" ในคอลัมน์ Z
'     - Task Code ที่มีบนระบบแล้ว ไม่เขียนทับ (ให้แก้ที่ชีต Plan_Backup แล้วกดส่งค่าที่แก้ไข)
'     - ส่งสำเร็จแล้วประทับ "ส่งแล้ว วันที่ เวลา" ที่คอลัมน์ Z ดึงข้อมูลลง Plan_Backup และเติมพิกัดจุดส่งอัตโนมัติ
' ---------------------------------------------------------------------------
Public Sub DP_SendNew()
    Dim ws As Worksheet, hdr As Long, rows As Collection, codes As New Collection, rowOf As New Collection
    Dim server As Collection, colNames() As String, ok As Boolean
    Dim i As Long, c As Long, r As Long, code As String, z As String
    Dim dup As New Collection, nDup As Long, nNoDate As Long, noDate As String
    Dim newCodes As New Collection, newRows As New Collection
    Dim nExist As Long, exist As String, nOld As Long, nGone As Long, gone As String
    Dim body As String, resp As String, nSend As Long, nIns As Long, nUpd As Long, inBatch As Long, stamp As String
    Dim wsB As Worksheet, hdrB As Long, bkMsg As String, plMsg As String

    On Error GoTo Fail
    Set ws = PlanSheet()
    If ws Is Nothing Then Exit Sub
    hdr = HeaderRow(ws)
    If hdr = 0 Then
        Tell "ไม่พบหัวตารางในชีต " & PLAN_SHEET & " (คอลัมน์ A ต้องมีคำว่า Task Code)", True
        Exit Sub
    End If
    Set rows = AllRows(ws, hdr)
    If rows.Count = 0 Then Exit Sub

    ' คัดแถวที่ใช้ได้ : ข้าม Task Code ซ้ำในไฟล์ และแถวที่ไม่มีวันที่
    For i = 1 To rows.Count
        r = rows.Item(i)
        code = CellText(ws, r, 1)
        If HasKey(dup, UCase$(code)) Then
            nDup = nDup + 1
        Else
            dup.Add True, UCase$(code)
            If Len(CellText(ws, r, 2)) = 0 Then
                nNoDate = nNoDate + 1
                If nNoDate <= 10 Then noDate = noDate & vbCrLf & "  " & code & " (แถว " & CStr(r) & ")"
            Else
                codes.Add code
                rowOf.Add r
            End If
        End If
    Next i
    If codes.Count = 0 Then
        Tell "ไม่มีงานที่ส่งได้ (ทุกแถวไม่มีวันที่หรือ Task Code ซ้ำ)", True
        Exit Sub
    End If

    ' งานที่มีบนระบบแล้ว = ข้าม (ไม่เขียนทับ)  งานที่ประทับ "ส่งแล้ว" แต่ไม่พบบนระบบ = ข้าม (ไม่ส่งซ้ำ)  งานที่เหลือ = ส่ง
    Set server = FetchPlan(codes, ok)
    If Not ok Then Exit Sub
    For i = 1 To codes.Count
        code = UCase$(CStr(codes.Item(i)))
        z = Trim$(CStr(ws.Cells(CLng(rowOf.Item(i)), COL_SYNC).Value))
        If HasKey(server, code) Then
            If Len(z) = 0 Then
                nExist = nExist + 1
                If nExist <= 10 Then exist = exist & vbCrLf & "  " & CStr(codes.Item(i)) & " (แถว " & CStr(rowOf.Item(i)) & ")"
            Else
                nOld = nOld + 1
            End If
        ElseIf IsSentStamp(z) Then
            nGone = nGone + 1
            If nGone <= 10 Then gone = gone & vbCrLf & "  " & CStr(codes.Item(i)) & " (แถว " & CStr(rowOf.Item(i)) & ")"
        Else
            newCodes.Add CStr(codes.Item(i))
            newRows.Add CLng(rowOf.Item(i))
        End If
    Next i

    If newCodes.Count > 0 Then
        colNames = Split(PLAN_FIELDS, ",")
        stamp = SentStamp()
        EnsureSyncHeader ws, hdr, "สถานะการส่ง"
        body = ""
        inBatch = 0
        For i = 1 To newCodes.Count
            r = newRows.Item(i)
            If inBatch > 0 Then body = body & ","
            body = body & "{"
            For c = 1 To NCOL
                If c > 1 Then body = body & ","
                body = body & """" & colNames(c - 1) & """:""" & JsonEsc(CellText(ws, r, c)) & """"
            Next c
            body = body & "}"
            inBatch = inBatch + 1
            If inBatch = 100 Or i = newCodes.Count Then
                resp = Api("POST", "/rest/v1/rpc/plan_sync", "{""p_rows"":[" & body & "]}", "", ok)
                If Not ok Then Exit Sub
                If mStatus < 200 Or mStatus > 299 Then
                    Tell "ส่งแผนไม่สำเร็จ: " & ErrText(resp) & IIf(nSend > 0, vbCrLf & "(ส่งสำเร็จไปแล้ว " & CStr(nSend) & " งาน)", ""), True
                    Exit Sub
                End If
                If IsNumeric(JsonStr(resp, "inserted")) Then nIns = nIns + CLng(JsonStr(resp, "inserted"))
                If IsNumeric(JsonStr(resp, "updated")) Then nUpd = nUpd + CLng(JsonStr(resp, "updated"))
                ' ประทับ "ส่งแล้ว" ให้แถวของชุดที่ส่งสำเร็จ
                For c = i - inBatch + 1 To i
                    WriteSync ws, CLng(newRows.Item(c)), stamp
                Next c
                nSend = nSend + inBatch
                body = ""
                inBatch = 0
            End If
        Next i
    End If

    ' ส่งสำเร็จแล้ว : ดึงข้อมูลลง Plan_Backup และเติมพิกัดจุดส่ง (ถ้าไม่สำเร็จแค่แจ้ง ไม่ย้อนการส่ง)
    If nSend > 0 Then bkMsg = RefreshBackupAuto(wsB, hdrB)
    plMsg = AutoPlaces(ws, hdr, wsB, hdrB)

    Tell IIf(nSend > 0, "ส่งงานใหม่ขึ้นระบบ " & CStr(nSend) & " งาน", "ไม่มีงานใหม่ที่ต้องส่ง") & _
         IIf(nOld > 0, vbCrLf & "ส่งแล้ว/มีบนระบบอยู่แล้ว (ข้าม) " & CStr(nOld) & " งาน", "") & _
         IIf(nExist > 0, vbCrLf & vbCrLf & "มีอยู่แล้วในระบบ " & CStr(nExist) & " งาน (ไม่เขียนทับ) ให้แก้ที่ชีต " & BACKUP_SHEET & ":" & exist & IIf(nExist > 10, vbCrLf & "  ...", ""), "") & _
         IIf(nGone > 0, vbCrLf & vbCrLf & "ประทับส่งแล้วแต่ไม่พบบนระบบ " & CStr(nGone) & " งาน (ไม่ส่งซ้ำ ถ้าต้องการส่งใหม่ให้ลบข้อความในคอลัมน์ Z ของแถวนั้น):" & gone & IIf(nGone > 10, vbCrLf & "  ...", ""), "") & _
         IIf(nDup > 0, vbCrLf & "Task Code ซ้ำในชีต (ข้าม) " & CStr(nDup) & " แถว", "") & _
         IIf(nNoDate > 0, vbCrLf & vbCrLf & "ไม่ได้ส่ง เพราะยังไม่ได้ใส่วันที่ " & CStr(nNoDate) & " งาน:" & noDate & IIf(nNoDate > 10, vbCrLf & "  ...", ""), "") & _
         IIf(Len(bkMsg) > 0, vbCrLf & vbCrLf & bkMsg, "") & _
         IIf(Len(plMsg) > 0, vbCrLf & vbCrLf & plMsg, "")
    Exit Sub
Fail:
    mMute = False
    Tell "เกิดข้อผิดพลาด: " & Err.Description & vbCrLf & vbCrLf & "ถ้าเป็นปัญหาการเชื่อมต่อ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่", True
End Sub

' ---------------------------------------------------------------------------
'  1.1) ส่งการแก้ไขของงานที่มีบนระบบแล้ว : ทุกแถวในชีต Plan_Backup ที่ค่าต่างจากบนระบบ
' ---------------------------------------------------------------------------
Public Sub DP_SendChanges()
    Dim ws As Worksheet, hdr As Long, rows As Collection, codes As New Collection, rowOf As New Collection
    Dim server As Collection, colNames() As String, ok As Boolean
    Dim i As Long, c As Long, r As Long, code As String, row As Variant
    Dim plMsg As String
    Dim dup As New Collection, nNoDate As Long, nNotOnServer As Long
    Dim chgCodes As New Collection, chgRows As New Collection, chgConf As New Collection
    Dim diff As Boolean, nConf As Long, conflicts As String, pick As Long, theirs As String, mine As String
    Dim sendCodes As New Collection, sendRows As New Collection
    Dim body As String, resp As String, inBatch As Long, nRows As Long, nCells As Long, nSent As Long, nSkip As Long, nLock As Long

    On Error GoTo Fail
    Set ws = BackupSheet(False)
    If ws Is Nothing Then Exit Sub
    hdr = HeaderRow(ws)
    If hdr = 0 Then
        Tell "ไม่พบหัวตารางในชีต " & BACKUP_SHEET & " (คอลัมน์ A ต้องมีคำว่า Task Code)", True
        Exit Sub
    End If
    Set rows = AllRows(ws, hdr)
    If rows.Count = 0 Then Exit Sub

    For i = 1 To rows.Count
        r = rows.Item(i)
        code = CellText(ws, r, 1)
        If Not HasKey(dup, UCase$(code)) Then
            dup.Add True, UCase$(code)
            If Len(CellText(ws, r, 2)) = 0 Then
                nNoDate = nNoDate + 1
            Else
                codes.Add code
                rowOf.Add r
            End If
        End If
    Next i
    If codes.Count = 0 Then
        Tell "ไม่มีแถวที่ตรวจได้ (ทุกแถวไม่มีวันที่)", True
        Exit Sub
    End If

    ' หาแถวที่ค่าต่างจากบนระบบ (เฉพาะงานที่มีบนระบบแล้ว)
    Set server = FetchPlan(codes, ok)
    If Not ok Then Exit Sub
    For i = 1 To codes.Count
        code = UCase$(CStr(codes.Item(i)))
        r = rowOf.Item(i)
        If Not HasKey(server, code) Then
            nNotOnServer = nNotOnServer + 1
        Else
            row = Fields(CStr(server.Item(code)), NCOL + 2)
            diff = False
            For c = 2 To NCOL
                If Differs(c, CStr(row(c - 1)), CellText(ws, r, c)) Then
                    diff = True
                    Exit For
                End If
            Next c
            If diff Then
                chgCodes.Add CStr(codes.Item(i))
                chgRows.Add r
                theirs = CStr(row(NCOL))
                mine = Trim$(CStr(ws.Cells(r, COL_SYNC).Value))
                If mine <> theirs Then
                    nConf = nConf + 1
                    chgConf.Add True, code
                    If nConf <= 12 Then conflicts = conflicts & vbCrLf & "  " & CStr(codes.Item(i)) & "   (ล่าสุดบนระบบ: " & Left$(theirs, 16) & " โดย " & CStr(row(NCOL + 1)) & ")"
                End If
            End If
        End If
    Next i
    If nConf > 12 Then conflicts = conflicts & vbCrLf & "  ... และอีก " & CStr(nConf - 12) & " งาน"

    If chgCodes.Count = 0 Then
        Tell "ไม่มีงานที่ค่าต่างจากบนระบบ ไม่ต้องส่งการแก้ไข" & _
             IIf(nNotOnServer > 0, vbCrLf & vbCrLf & "มี " & CStr(nNotOnServer) & " แถวที่ยังไม่อยู่บนระบบ (ใช้ปุ่มส่งงานใหม่ที่ชีต " & PLAN_SHEET & ")", "")
        Exit Sub
    End If

    If nConf > 0 Then
        pick = Choose3("พบ " & CStr(chgCodes.Count) & " งานที่ค่าในไฟล์ต่างจากบนระบบ" & vbCrLf & _
                       "ในจำนวนนี้ " & CStr(nConf) & " งานถูกแก้บนระบบหลังจากที่ไฟล์นี้ตรงกับระบบครั้งล่าสุด" & vbCrLf & _
                       "(เช่น แก้ผ่าน Popup บน Dashboard หรือคนขับแก้ทะเบียนตอนเช็คอิน)" & conflicts & vbCrLf & vbCrLf & _
                       "กด Yes = ส่งทับทั้งหมด " & CStr(chgCodes.Count) & " งาน (ค่าบนระบบของงานเหล่านี้จะถูกแทนที่ด้วยค่าในไฟล์)" & vbCrLf & _
                       "กด No = ข้ามงานข้างต้น ส่งเฉพาะที่เหลือ " & CStr(chgCodes.Count - nConf) & " งาน" & vbCrLf & _
                       "กด Cancel = ยกเลิก ไม่ส่งอะไรเลย (ใช้ปุ่มดึงข้อมูลลง " & BACKUP_SHEET & " เพื่อดูค่าบนระบบก่อนได้)")
        If pick = 0 Then Exit Sub
    Else
        If Not Confirm("ส่งการแก้ไข " & CStr(chgCodes.Count) & " งานขึ้นระบบ ?" & vbCrLf & "(ค่าบนระบบของงานเหล่านี้จะถูกแทนที่ด้วยค่าในไฟล์)") Then Exit Sub
        pick = 1
    End If

    For i = 1 To chgCodes.Count
        If pick = 1 Or Not HasKey(chgConf, UCase$(CStr(chgCodes.Item(i)))) Then
            sendCodes.Add CStr(chgCodes.Item(i))
            sendRows.Add CLng(chgRows.Item(i))
        Else
            nSkip = nSkip + 1
        End If
    Next i
    If sendCodes.Count = 0 Then
        Tell "ไม่มีงานที่ต้องส่ง"
        Exit Sub
    End If

    colNames = Split(PLAN_FIELDS, ",")
    body = ""
    inBatch = 0
    For i = 1 To sendCodes.Count
        r = sendRows.Item(i)
        If inBatch > 0 Then body = body & ","
        body = body & "{"
        For c = 1 To NCOL
            If c > 1 Then body = body & ","
            body = body & """" & colNames(c - 1) & """:""" & JsonEsc(CellText(ws, r, c)) & """"
        Next c
        body = body & "}"
        inBatch = inBatch + 1
        If inBatch = 100 Or i = sendCodes.Count Then
            resp = Api("POST", "/rest/v1/rpc/plan_update", "{""p_rows"":[" & body & "]}", "", ok)
            If Not ok Then Exit Sub
            If mStatus < 200 Or mStatus > 299 Then
                Tell "ส่งการแก้ไขไม่สำเร็จ: " & ErrText(resp) & IIf(nSent > 0, vbCrLf & "(ส่งสำเร็จไปแล้ว " & CStr(nSent) & " งาน)", ""), True
                Exit Sub
            End If
            If IsNumeric(JsonStr(resp, "rows")) Then nRows = nRows + CLng(JsonStr(resp, "rows"))
            If IsNumeric(JsonStr(resp, "cells")) Then nCells = nCells + CLng(JsonStr(resp, "cells"))
            If IsNumeric(JsonStr(resp, "locked")) Then nLock = nLock + CLng(JsonStr(resp, "locked"))
            nSent = nSent + inBatch
            body = ""
            inBatch = 0
        End If
    Next i

    ' จดเวลาที่ข้อมูลตรงกับระบบลงคอลัมน์ Z ของแถวที่ส่ง
    Set server = FetchPlan(sendCodes, ok)
    If ok Then
        EnsureSyncHeader ws, hdr, "Synced"
        For i = 1 To sendCodes.Count
            code = UCase$(CStr(sendCodes.Item(i)))
            If HasKey(server, code) Then
                row = Fields(CStr(server.Item(code)), NCOL + 2)
                WriteSync ws, CLng(sendRows.Item(i)), CStr(row(NCOL))
            End If
        Next i
    End If

    plMsg = AutoPlaces(ws, hdr, Nothing, 0)
    Tell "ส่งการแก้ไขขึ้นระบบแล้ว " & CStr(nRows) & " งาน (แก้ " & CStr(nCells) & " ช่อง)" & vbCrLf & "บันทึกประวัติไว้ใน Edit_Log (ช่องทาง Excel (Macro))" & _
         IIf(nSkip > 0, vbCrLf & "ข้ามไป " & CStr(nSkip) & " งาน (ถูกแก้บนระบบ)", "") & _
         IIf(nLock > 0, vbCrLf & "ข้ามไป " & CStr(nLock) & " งานที่ถูกยกเลิกแล้ว (แก้ไขไม่ได้ ให้ผู้ดูแลกู้คืนงานก่อน)", "") & _
         IIf(nNotOnServer > 0, vbCrLf & "มี " & CStr(nNotOnServer) & " แถวที่ยังไม่อยู่บนระบบ (ใช้ปุ่มส่งงานใหม่ที่ชีต " & PLAN_SHEET & ")", "") & _
         IIf(Len(plMsg) > 0, vbCrLf & vbCrLf & plMsg, "")
    Exit Sub
Fail:
    Tell "เกิดข้อผิดพลาด: " & Err.Description & vbCrLf & vbCrLf & "ถ้าเป็นปัญหาการเชื่อมต่อ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่", True
End Sub

' ---------------------------------------------------------------------------
'  อ่านผลลัพธ์ JSON แบบอาร์เรย์ของออบเจ็กต์แบนๆ (ใช้กับ delay_detail / delay_trend)
' ---------------------------------------------------------------------------
' p ชี้ที่เครื่องหมาย " เปิด : คืนข้อความที่ถอดรหัสแล้ว และ p ชี้ถัดจากเครื่องหมาย " ปิด
Private Function JsonReadStr(ByVal j As String, ByRef p As Long) As String
    Dim q As Long, n As Long, seg As String, out As String, ch As String
    n = Len(j)
    p = p + 1
    q = InStr(p, j, """")
    If q = 0 Then q = n + 1
    seg = Mid$(j, p, q - p)
    If InStr(seg, "\") = 0 Then
        JsonReadStr = seg
        p = q + 1
        Exit Function
    End If
    Do While p <= n
        ch = Mid$(j, p, 1)
        If ch = """" Then
            p = p + 1
            Exit Do
        End If
        If ch = "\" And p < n Then
            p = p + 1
            ch = Mid$(j, p, 1)
            Select Case ch
                Case "n": out = out & vbLf
                Case "r": out = out & vbCr
                Case "t": out = out & vbTab
                Case "u"
                    If p + 4 <= n Then
                        out = out & ChrW$(CLng("&H" & Mid$(j, p + 1, 4)))
                        p = p + 4
                    End If
                Case Else: out = out & ch
            End Select
        Else
            out = out & ch
        End If
        p = p + 1
    Loop
    JsonReadStr = out
End Function

' keysCsv = ชื่อ key ที่ต้องการ เรียงตามลำดับช่อง  ผลลัพธ์ = ชุดของแถว แต่ละแถวคือข้อความคั่นช่องด้วย SEP (ใช้ Fields(แถว, จำนวนช่อง)) ค่า null = ว่าง
Private Function JsonRows(ByVal j As String, ByVal keysCsv As String) As Collection
    Dim out As New Collection, keys() As String, vals() As String, nk As Long, n As Long, p As Long, q As Long
    Dim ch As String, key As String, v As String, s As String, i As Long, inObj As Boolean
    keys = Split(keysCsv, ",")
    nk = UBound(keys) + 1
    ReDim vals(0 To nk - 1)
    n = Len(j)
    p = 1
    Do While p <= n
        ch = Mid$(j, p, 1)
        If Not inObj Then
            If ch = "{" Then
                inObj = True
                For i = 0 To nk - 1
                    vals(i) = ""
                Next i
            End If
            p = p + 1
        ElseIf ch = "}" Then
            s = ""
            For i = 0 To nk - 1
                If i > 0 Then s = s & SEP
                s = s & Replace(vals(i), SEP, " ")
            Next i
            out.Add s
            inObj = False
            p = p + 1
        ElseIf ch = """" Then
            key = JsonReadStr(j, p)
            Do While p <= n
                ch = Mid$(j, p, 1)
                If ch <> " " And ch <> ":" And ch <> vbLf And ch <> vbCr And ch <> vbTab Then Exit Do
                p = p + 1
            Loop
            If p > n Then Exit Do
            If Mid$(j, p, 1) = """" Then
                v = JsonReadStr(j, p)
            Else
                q = p
                Do While q <= n
                    ch = Mid$(j, q, 1)
                    If ch = "," Or ch = "}" Then Exit Do
                    q = q + 1
                Loop
                v = Trim$(Mid$(j, p, q - p))
                If v = "null" Then v = ""
                p = q
            End If
            For i = 0 To nk - 1
                If keys(i) = key Then
                    vals(i) = v
                    Exit For
                End If
            Next i
        Else
            p = p + 1
        End If
    Loop
    Set JsonRows = out
End Function

' เรียกฟังก์ชันของระบบ (RPC) คืนข้อความ JSON  (ok = False เมื่อผิดพลาด/ยกเลิกการเข้าสู่ระบบ)
Private Function RpcJson(ByVal fn As String, ByVal body As String, ByRef ok As Boolean) As String
    Dim r As String
    r = Api("POST", "/rest/v1/rpc/" & fn, body, "", ok)
    If Not ok Then Exit Function
    If mStatus < 200 Or mStatus > 299 Then
        ok = False
        Tell "ดึงข้อมูลจากระบบไม่สำเร็จ (" & fn & "): " & ErrText(r), True
        Exit Function
    End If
    RpcJson = r
End Function

' แบ่งช่วงวันที่เป็นรายปีปฏิทิน (ระบบจำกัดช่วงต่อครั้ง) : ชุดของข้อความ "จาก|ถึง" (ปปปป-ดด-วว)
Private Function YearChunks(ByVal s1 As String, ByVal s2 As String) As Collection
    Dim out As New Collection, d1 As Date, d2 As Date, y As Long, a As Date, b As Date
    Set YearChunks = out
    If Not ParseIso(s1, d1) Then Exit Function
    If Not ParseIso(s2, d2) Then Exit Function
    For y = Year(d1) To Year(d2)
        a = DateSerial(y, 1, 1)
        If a < d1 Then a = d1
        b = DateSerial(y, 12, 31)
        If b > d2 Then b = d2
        out.Add IsoDate(a) & "|" & IsoDate(b)
    Next y
End Function


' Delay รายจุด ตามช่วงวันที่ : ชุดของแถว (คีย์ตาม DELAY_KEYS)
Private Function FetchDelayDetail(ByVal s1 As String, ByVal s2 As String, ByRef ok As Boolean) As Collection
    Dim out As New Collection, ch As Collection, i As Long, k As Long, a() As String, r As String, rows As Collection
    Set FetchDelayDetail = out
    ok = True
    Set ch = YearChunks(s1, s2)
    For i = 1 To ch.Count
        a = Split(CStr(ch.Item(i)), "|")
        r = RpcJson("delay_detail", "{""p_from"":""" & a(0) & """,""p_to"":""" & a(1) & """}", ok)
        If Not ok Then Exit Function
        Set rows = JsonRows(r, DELAY_KEYS)
        For k = 1 To rows.Count
            out.Add CStr(rows.Item(k))
        Next k
    Next i
End Function

' สรุป Delay รายวัน (grp = "day") หรือรายเดือน ("month") : ชุดของแถว (คีย์ตาม TREND_KEYS)
Private Function FetchDelayTrend(ByVal s1 As String, ByVal s2 As String, ByVal grp As String, ByRef ok As Boolean) As Collection
    Dim out As New Collection, ch As Collection, i As Long, k As Long, a() As String, r As String, rows As Collection
    Set FetchDelayTrend = out
    ok = True
    Set ch = YearChunks(s1, s2)
    For i = 1 To ch.Count
        a = Split(CStr(ch.Item(i)), "|")
        r = RpcJson("delay_trend", "{""p_from"":""" & a(0) & """,""p_to"":""" & a(1) & """,""p_group"":""" & grp & """}", ok)
        If Not ok Then Exit Function
        Set rows = JsonRows(r, TREND_KEYS)
        For k = 1 To rows.Count
            out.Add CStr(rows.Item(k))
        Next k
    Next i
End Function

' ---------------------------------------------------------------------------
'  ตัวช่วยเขียนตารางผลลัพธ์ (Log / สรุป / Delay) : ล้างข้อมูลเดิมในชีตแล้วเขียนทับ ไม่สร้างชีตซ้ำ ไม่บันทึกไฟล์
' ---------------------------------------------------------------------------
Private Function OutSheet(ByVal name As String) As Worksheet
    Dim ws As Worksheet
    Set ws = FindSheet(name)
    If ws Is Nothing Then
        Set ws = NewSheet(name, ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
    End If
    Set OutSheet = ws
End Function

' fmts = รูปแบบของแต่ละคอลัมน์คั่นด้วย , : dt = วันที่เวลา, dm = วันที่เวลา(ไม่มีวินาที), d = วันที่, ว่าง = ทั่วไป
Private Sub PutTable(ByVal ws As Worksheet, ByVal heads As String, ByVal vals As Variant, ByVal nRows As Long, ByVal fmts As String)
    Dim h() As String, f() As String, nc As Long, i As Long, lastRow As Long, lastCol As Long, k As Long, fm As String
    h = Split(heads, "|")
    f = Split(fmts, ",")
    nc = UBound(h) + 1
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
    k = ws.Cells(ws.Rows.Count, nc).End(xlUp).Row
    If k > lastRow Then lastRow = k
    lastCol = nc
    On Error Resume Next
    k = ws.UsedRange.Column + ws.UsedRange.Columns.Count - 1
    If Err.Number = 0 Then
        If k > lastCol And k <= 200 Then lastCol = k
    End If
    Err.Clear
    On Error GoTo 0
    If lastRow >= 2 Then ws.Range(ws.Cells(2, 1), ws.Cells(lastRow, lastCol)).ClearContents
    If lastCol > nc Then ws.Range(ws.Cells(1, nc + 1), ws.Cells(1, lastCol)).ClearContents
    For i = 0 To nc - 1
        ws.Cells(1, i + 1).Value = h(i)
    Next i
    ws.Rows(1).Font.Bold = True
    If nRows > 0 Then
        For k = 1 To nRows
            For i = 1 To nc
                If IsEmpty(vals(k, i)) Then vals(k, i) = ""
            Next i
        Next k
        ws.Range(ws.Cells(2, 1), ws.Cells(nRows + 1, nc)).NumberFormat = "General"
        For i = 0 To nc - 1
            fm = ""
            If i <= UBound(f) Then fm = f(i)
            Select Case fm
                Case "dt": ws.Range(ws.Cells(2, i + 1), ws.Cells(nRows + 1, i + 1)).NumberFormat = "yyyy-mm-dd hh:mm:ss"
                Case "dm": ws.Range(ws.Cells(2, i + 1), ws.Cells(nRows + 1, i + 1)).NumberFormat = "yyyy-mm-dd hh:mm"
                Case "d": ws.Range(ws.Cells(2, i + 1), ws.Cells(nRows + 1, i + 1)).NumberFormat = "yyyy-mm-dd"
            End Select
        Next i
        ws.Range(ws.Cells(2, 1), ws.Cells(nRows + 1, nc)).Value = vals
    End If
End Sub

' ข้อความวันที่-เวลา -> ค่าวันที่ (ไม่ถูกรูปแบบคืนข้อความเดิม ว่างคืนค่าว่าง)
Private Function TsVal(ByVal s As String) As Variant
    Dim d As Date
    TsVal = ""
    s = Trim$(s)
    If Len(s) = 0 Then Exit Function
    If ParseIso(s, d) Then
        TsVal = d
    Else
        TsVal = SafeText(s)
    End If
End Function

' ข้อความตัวเลข -> ตัวเลข (ว่างคืนค่าว่าง ไม่ใช่ตัวเลขคืนข้อความเดิม)
Private Function NumVal(ByVal s As String) As Variant
    Dim i As Long, ch As String, dig As Boolean
    NumVal = ""
    s = Trim$(s)
    If Len(s) = 0 Then Exit Function
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        If ch >= "0" And ch <= "9" Then
            dig = True
        ElseIf ch <> "-" And ch <> "." Then
            NumVal = SafeText(s)
            Exit Function
        End If
    Next i
    If dig Then
        NumVal = Val(s)
    Else
        NumVal = SafeText(s)
    End If
End Function

' ตัวเลขจากค่าที่อาจว่าง
Private Function N0(ByVal v As Variant) As Double
    If IsEmpty(v) Then Exit Function
    N0 = Val(CStr(v))
End Function

Private Function TxtVal(ByVal s As String) As Variant
    TxtVal = ""
    If Len(s) = 0 Then Exit Function
    TxtVal = SafeText(s)
End Function

' ---------------------------------------------------------------------------
'  3) Log + สรุปรายงานต่อ Task
' ---------------------------------------------------------------------------

' ดึงหนึ่งมุมมอง (ทุกแถว เรียงตาม id) : ชุดของแถว CSV (ไม่รวมหัวตาราง)
Private Function FetchView(ByVal view As String, ByRef ok As Boolean) As Collection
    Dim out As New Collection, rows As Collection, r As String, offset As Long, k As Long
    Set FetchView = out
    ok = False
    offset = 0
    Do
        r = Api("GET", "/rest/v1/" & view & "?select=*&order=id&limit=1000&offset=" & CStr(offset), "", "text/csv", ok)
        If Not ok Then Exit Function
        If mStatus <> 200 And mStatus <> 206 Then
            ok = False
            Tell "อ่าน Log ไม่สำเร็จ (" & view & "): " & ErrText(r), True
            Exit Function
        End If
        Set rows = ParseCsv(r)
        For k = 2 To rows.Count
            out.Add CStr(rows.Item(k))
        Next k
        offset = offset + 1000
    Loop While rows.Count >= 1001
    ok = True
End Function

' Task Code (ตัวพิมพ์ใหญ่) -> ลำดับในรายการงาน
Private Function PlanIndex(ByVal plan As Collection) As Collection
    Dim out As New Collection, i As Long, f As Variant, key As String
    For i = 1 To plan.Count
        f = Fields(CStr(plan.Item(i)), NCOL + 2)
        key = UCase$(Trim$(CStr(f(0))))
        If Len(key) > 0 Then
            If Not HasKey(out, key) Then out.Add i, key
        End If
    Next i
    Set PlanIndex = out
End Function

' ชื่อจุดส่งลำดับที่ n (นับเฉพาะจุดที่มีชื่อ ตรงกับการนับในระบบ) slot = ช่องเวลานัดที่ตรงกัน (1-3) ถ้าไม่มีจุดส่งเลย จุดที่ 1 = ข้อมูล Detail
Private Function StopInfo(ByVal f As Variant, ByVal n As Long, ByRef slot As Long) As String
    Dim k As Long, cnt As Long, nm As String
    slot = 0
    For k = 1 To 3
        nm = Norm(CStr(f(12 + 3 * k)))
        If Len(nm) > 0 Then
            cnt = cnt + 1
            If cnt = n Then
                slot = k
                StopInfo = nm
                Exit Function
            End If
        End If
    Next k
    If cnt = 0 And n = 1 Then
        slot = 1
        StopInfo = Norm(CStr(f(2)))
    End If
End Function

Private Function PlanRow(ByVal plan As Collection, ByVal pidx As Collection, ByVal code As String) As Variant
    Dim key As String
    key = UCase$(Trim$(code))
    If HasKey(pidx, key) Then PlanRow = Fields(CStr(plan.Item(CLng(pidx.Item(key)))), NCOL + 2)
End Function

Private Function BuildPickup(ByVal rows As Collection, ByVal plan As Collection, ByVal pidx As Collection) As Variant
    Dim v() As Variant, k As Long, row As Variant, f As Variant, n As Long
    n = rows.Count
    If n = 0 Then Exit Function
    ReDim v(1 To n, 1 To 11)
    For k = 1 To n
        ' v_pickup_log = id0,task_date1,ts2,task_code3,note4,photo_count5,photos6,source7
        row = Fields(CStr(rows.Item(k)), 8)
        v(k, 1) = TsVal(CStr(row(2)))
        v(k, 2) = TsVal(CStr(row(1)))
        v(k, 3) = TxtVal(CStr(row(3)))
        f = PlanRow(plan, pidx, CStr(row(3)))
        If IsArray(f) Then
            v(k, 4) = TxtVal(CStr(f(9)))
            v(k, 5) = TxtVal(CStr(f(11)))
            v(k, 6) = TxtVal(CStr(f(12)))
        End If
        v(k, 7) = TxtVal(CStr(row(4)))
        v(k, 8) = NumVal(CStr(row(5)))
        v(k, 9) = TxtVal(CStr(row(6)))
        v(k, 10) = TxtVal(CStr(row(7)))
        v(k, 11) = NumVal(CStr(row(0)))
    Next k
    BuildPickup = v
End Function

Private Function BuildRoad(ByVal rows As Collection, ByVal plan As Collection, ByVal pidx As Collection) As Variant
    Dim v() As Variant, k As Long, row As Variant, f As Variant, n As Long, sn As Long, slot As Long
    n = rows.Count
    If n = 0 Then Exit Function
    ReDim v(1 To n, 1 To 19)
    For k = 1 To n
        ' v_road_log = id0,task_date1,ts2,task_code3,type_th4,stop5,plate6,old_plate7,note8,eta1 9,eta2 10,eta3 11,road_count12,road13,unload_count14,unload15,finish16,source17
        row = Fields(CStr(rows.Item(k)), 18)
        v(k, 1) = TsVal(CStr(row(2)))
        v(k, 2) = TsVal(CStr(row(1)))
        v(k, 3) = TxtVal(CStr(row(3)))
        v(k, 4) = TxtVal(CStr(row(4)))
        v(k, 5) = NumVal(CStr(row(5)))
        If IsNumeric(CStr(row(5))) And Len(CStr(row(5))) > 0 Then
            sn = CLng(CStr(row(5)))
            f = PlanRow(plan, pidx, CStr(row(3)))
            If IsArray(f) Then v(k, 6) = TxtVal(StopInfo(f, sn, slot))
        End If
        v(k, 7) = TxtVal(CStr(row(6)))
        v(k, 8) = TxtVal(CStr(row(7)))
        v(k, 9) = TxtVal(CStr(row(8)))
        v(k, 10) = TxtVal(CStr(row(9)))
        v(k, 11) = TxtVal(CStr(row(10)))
        v(k, 12) = TxtVal(CStr(row(11)))
        v(k, 13) = NumVal(CStr(row(12)))
        v(k, 14) = TxtVal(CStr(row(13)))
        v(k, 15) = NumVal(CStr(row(14)))
        v(k, 16) = TxtVal(CStr(row(15)))
        If CStr(row(16)) = "t" Or CStr(row(16)) = "true" Then v(k, 17) = "ใช่"
        v(k, 18) = TxtVal(CStr(row(17)))
        v(k, 19) = NumVal(CStr(row(0)))
    Next k
    BuildRoad = v
End Function

Private Function BuildEdit(ByVal rows As Collection) As Variant
    Dim v() As Variant, k As Long, row As Variant, n As Long
    n = rows.Count
    If n = 0 Then Exit Function
    ReDim v(1 To n, 1 To 9)
    For k = 1 To n
        ' v_edit_log = id0,task_date1,ts2,task_code3,source4,field5,old_value6,new_value7,by_user8
        row = Fields(CStr(rows.Item(k)), 9)
        v(k, 1) = TsVal(CStr(row(2)))
        v(k, 2) = TsVal(CStr(row(1)))
        v(k, 3) = TxtVal(CStr(row(3)))
        v(k, 4) = TxtVal(CStr(row(4)))
        v(k, 5) = TxtVal(CStr(row(5)))
        v(k, 6) = TxtVal(CStr(row(6)))
        v(k, 7) = TxtVal(CStr(row(7)))
        v(k, 8) = TxtVal(CStr(row(8)))
        v(k, 9) = NumVal(CStr(row(0)))
    Next k
    BuildEdit = v
End Function

' ประเภทรายการใน Road_Log (ข้อความไทยจาก v_road_log) -> รหัส
Private Function RoadKind(ByVal t As String) As Long
    Select Case t
        Case "เช็คอิน": RoadKind = 1
        Case "รถออก": RoadKind = 2
        Case "ถึงหน้างาน": RoadKind = 3
        Case "ลงงานเสร็จ": RoadKind = 4
        Case "กลับถึงต้นทาง": RoadKind = 5
        Case Else: RoadKind = 0
    End Select
End Function

' สรุปหนึ่งแถวต่อหนึ่ง Task : คอลัมน์ตามหัวตาราง SUMMARY_HEADS
Private Function BuildSummary(ByVal plan As Collection, ByVal pidx As Collection, ByVal roads As Collection, ByVal picks As Collection, ByVal dly As Collection) As Variant
    Dim nT As Long, ag() As Variant, i As Long, k As Long, row As Variant, f As Variant, key As String, ts As String, src As String
    Dim kind As Long, sn As Long, bs As Long, s As Long, slot As Long, nm As String, pt As String, v() As Variant, c0 As Long, x As String
    nT = plan.Count
    If nT = 0 Then Exit Function
    ReDim ag(1 To nT, 1 To 25)

    ' ag : 1 เช็คอินเวลา 2 ที่มา 3 รถออกเวลา 4 ที่มา 5 กลับเวลา 6 ที่มา 7 รูปคลัง 8 รูปถนน 9 จบงาน 10 ล่าสุด
    '      จุด s (1-3) ฐาน = 10+(s-1)*5 : +1 ถึงเวลา +2 ที่มา +3 ลงงานเวลา +4 รูปลงงาน +5 ช้า/เร็วนาที
    For i = 1 To nT
        f = Fields(CStr(plan.Item(i)), NCOL + 2)
        x = Left$(CStr(f(NCOL)), 19)
        ag(i, 10) = x
    Next i

    For k = 1 To roads.Count
        row = Fields(CStr(roads.Item(k)), 18)
        key = UCase$(Trim$(CStr(row(3))))
        If HasKey(pidx, key) Then
            i = CLng(pidx.Item(key))
            ts = CStr(row(2))
            src = CStr(row(17))
            If ts > CStr(ag(i, 10)) Then ag(i, 10) = ts
            If IsNumeric(CStr(row(12))) And Len(CStr(row(12))) > 0 Then ag(i, 8) = N0(ag(i, 8)) + Val(CStr(row(12)))
            If CStr(row(16)) = "t" Or CStr(row(16)) = "true" Then ag(i, 9) = "ใช่"
            kind = RoadKind(CStr(row(4)))
            Select Case kind
                Case 1
                    If IsEmpty(ag(i, 1)) Then
                        ag(i, 1) = ts: ag(i, 2) = src
                    ElseIf ts < CStr(ag(i, 1)) Then
                        ag(i, 1) = ts: ag(i, 2) = src
                    End If
                Case 2
                    If IsEmpty(ag(i, 3)) Then
                        ag(i, 3) = ts: ag(i, 4) = src
                    ElseIf ts < CStr(ag(i, 3)) Then
                        ag(i, 3) = ts: ag(i, 4) = src
                    End If
                Case 5
                    If IsEmpty(ag(i, 5)) Then
                        ag(i, 5) = ts: ag(i, 6) = src
                    ElseIf ts < CStr(ag(i, 5)) Then
                        ag(i, 5) = ts: ag(i, 6) = src
                    End If
                Case 3, 4
                    If IsNumeric(CStr(row(5))) And Len(CStr(row(5))) > 0 Then
                        s = CLng(CStr(row(5)))
                        If s >= 1 And s <= 3 Then
                            bs = 10 + (s - 1) * 5
                            If IsEmpty(ag(i, bs + 1)) Then
                                ag(i, bs + 1) = ts: ag(i, bs + 2) = src
                            ElseIf ts < CStr(ag(i, bs + 1)) Then
                                ag(i, bs + 1) = ts: ag(i, bs + 2) = src
                            End If
                            If kind = 4 Then
                                If IsEmpty(ag(i, bs + 3)) Then
                                    ag(i, bs + 3) = ts
                                ElseIf ts < CStr(ag(i, bs + 3)) Then
                                    ag(i, bs + 3) = ts
                                End If
                                If IsNumeric(CStr(row(14))) And Len(CStr(row(14))) > 0 Then ag(i, bs + 4) = N0(ag(i, bs + 4)) + Val(CStr(row(14)))
                            End If
                        End If
                    End If
            End Select
        End If
    Next k

    For k = 1 To picks.Count
        row = Fields(CStr(picks.Item(k)), 8)
        key = UCase$(Trim$(CStr(row(3))))
        If HasKey(pidx, key) Then
            i = CLng(pidx.Item(key))
            ts = CStr(row(2))
            If ts > CStr(ag(i, 10)) Then ag(i, 10) = ts
            If IsNumeric(CStr(row(5))) And Len(CStr(row(5))) > 0 Then ag(i, 7) = N0(ag(i, 7)) + Val(CStr(row(5)))
        End If
    Next k

    ' ช้า/เร็ว (นาที) จาก delay_detail ของระบบ  (DELAY_KEYS : task_code0,date1,stop2,stop_name3,company4,plate5,plan6,arrive7,diff_min8,ontime9,source10)
    For k = 1 To dly.Count
        row = Fields(CStr(dly.Item(k)), 11)
        key = UCase$(Trim$(CStr(row(0))))
        If HasKey(pidx, key) Then
            i = CLng(pidx.Item(key))
            If IsNumeric(CStr(row(2))) And Len(CStr(row(2))) > 0 Then
                s = CLng(CStr(row(2)))
                If s >= 1 And s <= 3 Then
                    bs = 10 + (s - 1) * 5
                    ag(i, bs + 5) = CStr(row(8))
                    If IsEmpty(ag(i, bs + 1)) And Len(CStr(row(7))) > 0 Then
                        ag(i, bs + 1) = CStr(row(7))
                        ag(i, bs + 2) = CStr(row(10))
                    End If
                End If
            End If
        End If
    Next k

    ReDim v(1 To nT, 1 To 38)
    For i = 1 To nT
        f = Fields(CStr(plan.Item(i)), NCOL + 2)
        v(i, 1) = TsVal(CStr(f(1)))
        v(i, 2) = TxtVal(CStr(f(0)))
        v(i, 3) = TxtVal(CStr(f(11)))
        v(i, 4) = TxtVal(CStr(f(12)))
        v(i, 5) = TxtVal(CStr(f(9)))
        v(i, 6) = TxtVal(CStr(f(14)))
        v(i, 7) = TxtVal(CStr(f(24)))
        v(i, 8) = TsVal(CStr(ag(i, 1)))
        v(i, 9) = TxtVal(CStr(ag(i, 2)))
        v(i, 10) = TsVal(CStr(ag(i, 3)))
        v(i, 11) = TxtVal(CStr(ag(i, 4)))
        For s = 1 To 3
            c0 = 12 + (s - 1) * 7
            bs = 10 + (s - 1) * 5
            nm = StopInfo(f, s, slot)
            If Len(nm) > 0 Then
                v(i, c0) = TxtVal(nm)
                If slot > 0 Then
                    pt = HmNorm(CStr(f(5 + slot)))
                    If Len(pt) > 0 Then v(i, c0 + 1) = SafeText(pt)
                End If
                v(i, c0 + 2) = TsVal(CStr(ag(i, bs + 1)))
                v(i, c0 + 3) = TxtVal(CStr(ag(i, bs + 2)))
                v(i, c0 + 4) = TsVal(CStr(ag(i, bs + 3)))
                v(i, c0 + 5) = NumVal(CStr(ag(i, bs + 5)))
                v(i, c0 + 6) = N0(ag(i, bs + 4))
            End If
        Next s
        v(i, 33) = TsVal(CStr(ag(i, 5)))
        v(i, 34) = TxtVal(CStr(ag(i, 6)))
        v(i, 35) = N0(ag(i, 7))
        v(i, 36) = N0(ag(i, 8))
        If CStr(ag(i, 9)) = "ใช่" Then v(i, 37) = "ใช่" Else v(i, 37) = "ยังไม่จบ"
        v(i, 38) = TsVal(CStr(ag(i, 10)))
    Next i
    BuildSummary = v
End Function

Private Function PickupHeads() As String
    PickupHeads = "Timestamp|วันที่งาน|Task Code|ชื่อบริษัทขนส่ง|ทะเบียนรถ|ชื่อผู้ขับ|หมายเหตุ|จำนวนรูป (คลังสินค้า)|ลิงก์รูปจากคลังสินค้า|ที่มา (คน/GPS)|ID"
End Function

Private Function RoadHeads() As String
    RoadHeads = "Timestamp|วันที่งาน|Task Code|ประเภท|จุดที่|ชื่อจุดส่ง|ทะเบียนรถ|ทะเบียนเดิม (ถ้าแก้ไข)|หมายเหตุ|คาดว่าจะถึงจุดที่ 1|คาดว่าจะถึงจุดที่ 2|คาดว่าจะถึงจุดที่ 3|จำนวนรูปบนถนน|ลิงก์รูปบนถนน|จำนวนรูปลงงาน|ลิงก์รูปลงงาน|จบงาน|ที่มา (คน/GPS)|ID"
End Function

Private Function EditHeads() As String
    EditHeads = "Timestamp|วันที่งาน|Task Code|ช่องทาง|รายการที่แก้ไข|ค่าเดิม|ค่าใหม่|ผู้แก้ไข|ID"
End Function

Private Function SummaryHeads() As String
    Dim h As String, s As Long, p As String
    h = "วันที่งาน|Task Code|ทะเบียนรถ|ชื่อผู้ขับ|ชื่อบริษัทขนส่ง|รอบขนส่ง|สถานะงาน|เช็คอิน (เวลา)|เช็คอิน (ที่มา)|รถออก (เวลา)|รถออก (ที่มา)"
    For s = 1 To 3
        p = "จุดที่ " & CStr(s) & " "
        h = h & "|" & p & "ชื่อจุดส่ง|" & p & "เวลานัด|" & p & "ถึงหน้างาน (เวลา)|" & p & "ถึงหน้างาน (ที่มา)|" & p & "ลงงานเสร็จ (เวลา)|" & p & "ช้า(+)/เร็ว(-) นาที|" & p & "จำนวนรูปลงงาน"
    Next s
    h = h & "|กลับถึงต้นทาง (เวลา)|กลับถึงต้นทาง (ที่มา)|จำนวนรูปคลังสินค้า|จำนวนรูปบนถนน|จบงาน|อัปเดตล่าสุด"
    SummaryHeads = h
End Function

Private Function SummaryFmts() As String
    Dim f(1 To 38) As String, i As Long, s As Long, c0 As Long, o As String
    f(1) = "d": f(8) = "dt": f(10) = "dt": f(33) = "dt": f(38) = "dt"
    For s = 1 To 3
        c0 = 12 + (s - 1) * 7
        f(c0 + 2) = "dt"
        f(c0 + 4) = "dt"
    Next s
    For i = 1 To 38
        If i > 1 Then o = o & ","
        o = o & f(i)
    Next i
    SummaryFmts = o
End Function

' ดึง Log ทั้ง 3 มุมมอง แล้วเขียนชีต Pickup_Log / Road_Log / Edit_Log / Task_Summary (เขียนทับ) : plan = งานทั้งหมด dly = Delay รายจุด (ว่างได้)
Private Function WriteLogSheets(ByVal plan As Collection, ByVal dly As Collection) As Boolean
    Dim ok As Boolean, picks As Collection, roads As Collection, edits As Collection, pidx As Collection
    Dim vals As Variant

    Set picks = FetchView("v_pickup_log", ok)
    If Not ok Then Exit Function
    Set roads = FetchView("v_road_log", ok)
    If Not ok Then Exit Function
    Set edits = FetchView("v_edit_log", ok)
    If Not ok Then Exit Function
    Set pidx = PlanIndex(plan)

    vals = BuildPickup(picks, plan, pidx)
    PutTable OutSheet("Pickup_Log"), PickupHeads(), vals, picks.Count, "dt,d"
    vals = BuildRoad(roads, plan, pidx)
    PutTable OutSheet("Road_Log"), RoadHeads(), vals, roads.Count, "dt,d"
    vals = BuildEdit(edits)
    PutTable OutSheet("Edit_Log"), EditHeads(), vals, edits.Count, "dt,d"
    vals = BuildSummary(plan, pidx, roads, picks, dly)
    PutTable OutSheet("Task_Summary"), SummaryHeads(), vals, plan.Count, SummaryFmts()
    mLgP = picks.Count
    mLgR = roads.Count
    mLgE = edits.Count
    mLgS = plan.Count
    WriteLogSheets = True
End Function

' ช่วงวันที่เก่าสุด-ใหม่สุดของงานทั้งหมด (ข้อความ ปปปป-ดด-วว)
Private Sub PlanRange(ByVal plan As Collection, ByRef s1 As String, ByRef s2 As String)
    Dim i As Long, f As Variant, d As String
    s1 = "": s2 = ""
    For i = 1 To plan.Count
        f = Fields(CStr(plan.Item(i)), NCOL + 2)
        d = Left$(CStr(f(1)), 10)
        If Len(d) = 10 Then
            If Len(s1) = 0 Then
                s1 = d: s2 = d
            ElseIf d < s1 Then
                s1 = d
            ElseIf d > s2 Then
                s2 = d
            End If
        End If
    Next i
End Sub

' ดึง Log ทั้งหมด (รูปคลังสินค้า / สถานะรถ / ประวัติแก้ไข) และสรุปต่อ Task เขียนทับชีต Pickup_Log / Road_Log / Edit_Log / Task_Summary
Public Sub DP_PullLogs()
    Dim plan As Collection, dly As Collection, ok As Boolean, s1 As String, s2 As String, note As String

    On Error GoTo Fail
    If Len(GetToken()) = 0 Then Exit Sub
    ScreenOn False
    Set plan = FetchAllPlan(ok)
    If Not ok Then GoTo Done
    Set dly = New Collection
    PlanRange plan, s1, s2
    If Len(s1) > 0 Then
        mMute = True
        Set dly = FetchDelayDetail(s1, s2, ok)
        mMute = False
        If Not ok Then
            Set dly = New Collection
            note = vbCrLf & vbCrLf & "หมายเหตุ: ดึงข้อมูลช้า/เร็ว (Delay) ไม่สำเร็จ คอลัมน์ ช้า(+)/เร็ว(-) นาที ใน Task_Summary จึงเว้นว่าง"
        End If
    End If
    If Not WriteLogSheets(plan, dly) Then GoTo Done
    ScreenOn True
    Tell "ดึง Log ทั้งหมดจากระบบเรียบร้อย (เขียนทับข้อมูลเดิมในชีต)" & vbCrLf & vbCrLf & _
         "Pickup_Log (รูปจากคลังสินค้า) : " & CStr(mLgP) & " รายการ" & vbCrLf & _
         "Road_Log (สถานะรถ รวมรถออก) : " & CStr(mLgR) & " รายการ" & vbCrLf & _
         "Edit_Log : " & CStr(mLgE) & " รายการ" & vbCrLf & _
         "Task_Summary (สรุปต่อ Task) : " & CStr(mLgS) & " งาน" & note
    Exit Sub
Done:
    mMute = False
    ScreenOn True
    Exit Sub
Fail:
    mMute = False
    ScreenOn True
    Tell "เกิดข้อผิดพลาด: " & Err.Description & vbCrLf & vbCrLf & "ถ้าเป็นปัญหาการเชื่อมต่อ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่", True
End Sub

' ---------------------------------------------------------------------------
'  4) Delay Trend : เวลาถึงจริง เทียบเวลานัดของแต่ละจุด ตามช่วงวันที่ ไปที่ Delay_Detail / Delay_Daily / Delay_Monthly
' ---------------------------------------------------------------------------

Private Function BuildDelayDetail(ByVal rows As Collection) As Variant
    Dim v() As Variant, k As Long, row As Variant, n As Long
    n = rows.Count
    If n = 0 Then Exit Function
    ReDim v(1 To n, 1 To 11)
    For k = 1 To n
        row = Fields(CStr(rows.Item(k)), 11)
        v(k, 1) = TsVal(CStr(row(1)))
        v(k, 2) = TxtVal(CStr(row(0)))
        v(k, 3) = NumVal(CStr(row(2)))
        v(k, 4) = TxtVal(CStr(row(3)))
        v(k, 5) = TxtVal(CStr(row(4)))
        v(k, 6) = TxtVal(CStr(row(5)))
        v(k, 7) = TsVal(CStr(row(6)))
        v(k, 8) = TsVal(CStr(row(7)))
        v(k, 9) = NumVal(CStr(row(8)))
        If CStr(row(9)) = "true" Then
            v(k, 10) = "ทันเวลา"
        ElseIf CStr(row(9)) = "false" Then
            v(k, 10) = "ช้า"
        End If
        v(k, 11) = TxtVal(CStr(row(10)))
    Next k
    BuildDelayDetail = v
End Function

Private Function BuildDelayTrend(ByVal rows As Collection, ByVal asDate As Boolean) As Variant
    Dim v() As Variant, k As Long, row As Variant, n As Long, j As Long
    n = rows.Count
    If n = 0 Then Exit Function
    ReDim v(1 To n, 1 To 9)
    For k = 1 To n
        row = Fields(CStr(rows.Item(k)), 9)
        If asDate Then
            v(k, 1) = TsVal(CStr(row(0)))
        Else
            v(k, 1) = TxtVal(CStr(row(0)))
        End If
        For j = 1 To 8
            v(k, j + 1) = NumVal(CStr(row(j)))
        Next j
    Next k
    BuildDelayTrend = v
End Function

Private Function TrendHeads(ByVal first As String) As String
    TrendHeads = first & "|จำนวนจุดส่ง|ทันเวลา|ช้า|% ทันเวลา|ช้า(+)/เร็ว(-) เฉลี่ย (นาที)|ช้าเฉลี่ย เฉพาะที่ช้า (นาที)|ช้าสุด (นาที)|เวลาถึงจาก GPS (จุด)"
End Function

Private Function DelayHeads() As String
    DelayHeads = "วันที่งาน|Task Code|จุดที่|ชื่อจุดส่ง|ชื่อบริษัทขนส่ง|ทะเบียนรถ|เวลานัด|เวลาถึงจริง|ช้า(+)/เร็ว(-) นาที|ผล|ที่มา (คน/GPS)"
End Function

' เขียนชีต Delay ทั้ง 3 ชีต (เขียนทับ)
Private Sub WriteDelaySheets(ByVal detail As Collection, ByVal daily As Collection, ByVal monthly As Collection)
    Dim vals As Variant
    vals = BuildDelayDetail(detail)
    PutTable OutSheet("Delay_Detail"), DelayHeads(), vals, detail.Count, "d,,,,,,dm,dm"
    vals = BuildDelayTrend(daily, True)
    PutTable OutSheet("Delay_Daily"), TrendHeads("วันที่"), vals, daily.Count, "d"
    vals = BuildDelayTrend(monthly, False)
    PutTable OutSheet("Delay_Monthly"), TrendHeads("เดือน"), vals, monthly.Count, ""
    mDlD = detail.Count
    mDlDay = daily.Count
    mDlMon = monthly.Count
End Sub

' ดึง Delay (3 ชุด) ของช่วงวันที่ แล้วเขียนชีต : detail ที่ดึงมาแล้ว (ถ้ามี) ใช้ซ้ำได้
Private Function DelayPull(ByVal s1 As String, ByVal s2 As String, ByVal detail As Collection) As Boolean
    Dim ok As Boolean, daily As Collection, monthly As Collection
    If detail Is Nothing Then
        Set detail = FetchDelayDetail(s1, s2, ok)
        If Not ok Then Exit Function
    End If
    Set daily = FetchDelayTrend(s1, s2, "day", ok)
    If Not ok Then Exit Function
    Set monthly = FetchDelayTrend(s1, s2, "month", ok)
    If Not ok Then Exit Function
    WriteDelaySheets detail, daily, monthly
    DelayPull = True
End Function

Public Sub DP_PullDelay()
    Dim a As String, b As String, s1 As String, s2 As String, t As String

    On Error GoTo Fail
    If Len(GetToken()) = 0 Then Exit Sub
    a = Ask("Delay Trend : ดึงตั้งแต่วันที่" & vbCrLf & "(พิมพ์เช่น 2026-10-01 หรือ 1/10/2569)", IsoDate(DateSerial(Year(Date), Month(Date), 1)))
    If Len(Trim$(a)) = 0 Then Exit Sub
    b = Ask("Delay Trend : ถึงวันที่" & vbCrLf & "(พิมพ์เช่น 2026-10-31 หรือ 31/10/2569)", IsoDate(Date))
    If Len(Trim$(b)) = 0 Then Exit Sub
    s1 = UserDate(a)
    s2 = UserDate(b)
    If Len(s1) = 0 Or Len(s2) = 0 Then
        Tell "รูปแบบวันที่ไม่ถูกต้อง (ใช้ ปปปป-ดด-วว หรือ วว/ดด/ปปปป)", True
        Exit Sub
    End If
    If s2 < s1 Then
        t = s1: s1 = s2: s2 = t
    End If
    ScreenOn False
    If Not DelayPull(s1, s2, Nothing) Then
        ScreenOn True
        Exit Sub
    End If
    ScreenOn True
    Tell "ดึง Delay Trend ช่วง " & s1 & " ถึง " & s2 & " เรียบร้อย (เขียนทับข้อมูลเดิมในชีต)" & vbCrLf & vbCrLf & _
         "Delay_Detail (รายจุด) : " & CStr(mDlD) & " แถว" & vbCrLf & _
         "Delay_Daily (รายวัน) : " & CStr(mDlDay) & " วัน" & vbCrLf & _
         "Delay_Monthly (รายเดือน) : " & CStr(mDlMon) & " เดือน"
    Exit Sub
Fail:
    ScreenOn True
    Tell "เกิดข้อผิดพลาด: " & Err.Description & vbCrLf & vbCrLf & "ถ้าเป็นปัญหาการเชื่อมต่อ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่", True
End Sub

' ---------------------------------------------------------------------------
'  5) Backup ทั้งหมดในครั้งเดียว : Plan_Backup + Log + Task_Summary + Delay (ทั้งช่วงข้อมูล) ไม่บันทึกไฟล์
'     DP_BackupAll = ใช้เอง (มีหน้าต่างสรุป)   DP_BackupFill = งาน Backup อัตโนมัติ (ไม่มีหน้าต่าง รับ token)
' ---------------------------------------------------------------------------
' คืนผลลัพธ์บรรทัดเดียว : "OK|plan=..|..." หรือ "ERROR|ข้อความ"
Private Function RunBackup() As String
    Dim ws As Worksheet, hdr As Long, plan As Collection, dly As Collection, ok As Boolean
    Dim s1 As String, s2 As String, td As String, notes As String, okT As Boolean

    mLastTell = ""
    If Len(GetToken()) = 0 Then
        RunBackup = "ERROR|ไม่มี token หรือยกเลิกการเข้าสู่ระบบ"
        Exit Function
    End If
    Set ws = BackupSheet(True)
    hdr = HeaderRow(ws)
    Set plan = FetchAllPlan(ok)
    If Not ok Then
        RunBackup = "ERROR|อ่านงานจากระบบไม่สำเร็จ " & mLastTell
        Exit Function
    End If
    If Not WriteBackup(plan, ws, hdr, Not mSilent) Then
        RunBackup = "ERROR|ยกเลิกการดึงข้อมูล"
        Exit Function
    End If

    PlanRange plan, s1, s2
    td = IsoDate(Date)
    If Len(s1) = 0 Then
        s1 = td
        s2 = td
    ElseIf td > s2 Then
        s2 = td
    End If
    mMute = True
    Set dly = FetchDelayDetail(s1, s2, ok)
    mMute = False
    If Not ok Then
        notes = notes & "|delay=ERR(" & Replace(mLastTell, "|", "/") & ")"
        Set dly = New Collection
    End If
    If Not WriteLogSheets(plan, dly) Then
        RunBackup = "ERROR|ดึง Log ไม่สำเร็จ " & mLastTell
        Exit Function
    End If
    If ok Then
        mMute = True
        okT = DelayPull(s1, s2, dly)
        mMute = False
        If Not okT Then notes = notes & "|delay_trend=ERR(" & Replace(mLastTell, "|", "/") & ")"
    End If
    RunBackup = "OK|plan=" & CStr(mBkTotal) & "|pickup=" & CStr(mLgP) & "|road=" & CStr(mLgR) & "|edit=" & CStr(mLgE) & "|summary=" & CStr(mLgS) & _
                "|delay_detail=" & CStr(IIf(ok, mDlD, 0)) & "|delay_daily=" & CStr(IIf(ok, mDlDay, 0)) & "|delay_monthly=" & CStr(IIf(ok, mDlMon, 0)) & _
                "|unsent_kept=" & CStr(mBkKept) & "|range=" & s1 & ".." & s2 & notes
End Function

Public Sub DP_BackupAll()
    Dim res As String, t As String
    On Error GoTo Fail
    ScreenOn False
    res = RunBackup()
    ScreenOn True
    DP_LastBackupResult = res
    If Left$(res, 2) = "OK" Then
        StampBackupResult res
        t = "Backup ทั้งหมดเรียบร้อย (เขียนทับข้อมูลในชีต ยังไม่ได้บันทึกไฟล์ ให้กด Save เอง)" & vbCrLf & vbCrLf & _
            BACKUP_SHEET & " : " & CStr(mBkTotal) & " งาน" & IIf(mBkKept > 0, " (ข้ามไม่ทับ " & CStr(mBkKept) & " งานที่แก้ไว้แล้วยังไม่ได้ส่ง)", "") & vbCrLf & _
            "Pickup_Log : " & CStr(mLgP) & " / Road_Log : " & CStr(mLgR) & " / Edit_Log : " & CStr(mLgE) & vbCrLf & _
            "Task_Summary : " & CStr(mLgS) & " งาน" & vbCrLf & _
            "Delay_Detail : " & CStr(mDlD) & " / Delay_Daily : " & CStr(mDlDay) & " / Delay_Monthly : " & CStr(mDlMon)
        If InStr(res, "ERR") > 0 Then t = t & vbCrLf & vbCrLf & "มีบางส่วนดึงไม่สำเร็จ : " & Mid$(res, InStr(res, "|delay") + 1)
        Tell t
    ElseIf Len(mLastTell) = 0 Then
        Tell Mid$(res, 7), True
    End If
    Exit Sub
Fail:
    ScreenOn True
    DP_LastBackupResult = "ERROR|" & Err.Description
    Tell "เกิดข้อผิดพลาด: " & Err.Description & vbCrLf & vbCrLf & "ถ้าเป็นปัญหาการเชื่อมต่อ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่", True
End Sub

' สำหรับงาน Backup อัตโนมัติ (เช่น Python ผ่าน COM) : accessToken = JWT ของผู้ใช้ Supabase ที่ล็อกอินไว้แล้ว
'   ไม่มี MsgBox / InputBox ใดๆ  ไม่เรียก Save/SaveAs (ให้งานภายนอกตัดสินใจเอง)  ผลลัพธ์บรรทัดเดียวอยู่ใน DP_LastBackupResult
'   (อ่านผ่าน COM ได้ด้วย Application.Run "modDeliveryPlan.DP_GetLastBackupResult")
Public Sub DP_BackupFill(ByVal accessToken As String)
    On Error GoTo Fail
    DP_LastBackupResult = ""
    mSilent = True
    mOverrideToken = Trim$(accessToken)
    If Len(mOverrideToken) = 0 Then
        DP_LastBackupResult = "ERROR|ไม่ได้ส่ง access token"
        GoTo Done
    End If
    ScreenOn False
    DP_LastBackupResult = RunBackup()
    GoTo Done
Fail:
    DP_LastBackupResult = "ERROR|" & Err.Description
Done:
    On Error Resume Next
    mSilent = False
    mMute = False
    mOverrideToken = ""
    ScreenOn True
    If Left$(DP_LastBackupResult, 2) = "OK" Then StampBackupResult DP_LastBackupResult
End Sub

Public Function DP_GetLastBackupResult() As String
    DP_GetLastBackupResult = DP_LastBackupResult
End Function

' ---------------------------------------------------------------------------
'  ส่งตำแหน่งรถจากไฟล์ GPS : เลือกไฟล์ "ข้อมูลรถปัจจุบัน" ที่ Export จาก DTCUltimate (ไม่ต้องเปิดไฟล์ก่อน)
' ---------------------------------------------------------------------------
' หาคอลัมน์ตามชื่อหัวตารางในแถวที่ระบุ (ไม่พบคืน 0)
Private Function FindCol(ByVal ws As Worksheet, ByVal hdr As Long, ByVal title As String) As Long
    Dim c As Long
    For c = 1 To 60
        If Trim$(CStr(ws.Cells(hdr, c).Value)) = title Then
            FindCol = c
            Exit Function
        End If
    Next c
End Function

' เวลาในไฟล์ -> "yyyy-mm-dd hh:nn:ss" (เวลาไทย) ถ้าอ่านไม่ได้คืนค่าว่าง
Private Function GpsTime(ByVal v As Variant) As String
    Dim s As String, p() As String, d() As String, y As Long
    If IsError(v) Then Exit Function
    If VarType(v) = vbDate Then
        GpsTime = Format$(v, "yyyy-mm-dd hh:nn:ss")
        Exit Function
    End If
    s = Trim$(CStr(v))
    If s Like "####-##-## ##:##:##" Then
        GpsTime = s
    ElseIf s Like "##/##/#### ##:##:##" Then
        y = CLng(Mid$(s, 7, 4))
        If y > 2400 Then y = y - 543
        GpsTime = Format$(y, "0000") & "-" & Mid$(s, 4, 2) & "-" & Left$(s, 2) & Mid$(s, 11)
    End If
End Function

Private Function GpsNum(ByVal v As Variant) As String
    Dim s As String
    If IsError(v) Then GpsNum = "0": Exit Function
    s = Replace(Trim$(CStr(v)), ",", ".")
    GpsNum = Replace(CStr(Val(s)), ",", ".")
End Function

Public Sub DP_PushGPS()
    Dim fn As Variant, wb As Workbook, ws As Worksheet, hdr As Long, r As Long, c As Long, lastR As Long
    Dim cP As Long, cT As Long, cS As Long, cLa As Long, cLo As Long, cSt As Long
    Dim body As String, inBatch As Long, resp As String, ok As Boolean
    Dim nRows As Long, nSaved As Long, nSkip As Long, nEv As Long, t As String, plate As String, la As String, lo As String
    Dim prevAlerts As Boolean, failed As Boolean, failMsg As String, spd As String, stt As String, wasOpen As Boolean, w As Workbook

    On Error GoTo Fail
    fn = Application.GetOpenFilename("ไฟล์ Excel (*.xlsx;*.xls;*.xlsm),*.xlsx;*.xls;*.xlsm", , "เลือกไฟล์ข้อมูลรถปัจจุบันจากระบบ GPS")
    If VarType(fn) = vbBoolean Then Exit Sub

    prevAlerts = Application.DisplayAlerts
    Application.ScreenUpdating = False
    Application.DisplayAlerts = False
    For Each w In Workbooks
        If LCase$(w.FullName) = LCase$(CStr(fn)) Then
            Set wb = w
            wasOpen = True
        End If
    Next w
    If wb Is Nothing Then Set wb = Workbooks.Open(CStr(fn), 0, True)
    Application.DisplayAlerts = prevAlerts
    Set ws = wb.Worksheets(1)

    For r = 1 To 20
        If FindCol(ws, r, "ทะเบียนรถ") > 0 Then hdr = r: Exit For
    Next r
    If hdr = 0 Then
        If Not wasOpen Then wb.Close False
        Application.ScreenUpdating = True
        Tell "ไม่พบหัวตาราง ""ทะเบียนรถ"" ในไฟล์นี้ กรุณาเลือกไฟล์ ""ข้อมูลรถปัจจุบัน"" ที่ Export จากระบบ GPS", True
        Exit Sub
    End If
    cP = FindCol(ws, hdr, "ทะเบียนรถ")
    cT = FindCol(ws, hdr, "เวลากล่อง")
    cS = FindCol(ws, hdr, "ความเร็ว")
    cLa = FindCol(ws, hdr, "ละติจูด")
    cLo = FindCol(ws, hdr, "ลองจิจูด")
    cSt = FindCol(ws, hdr, "สถานะ")
    If cT = 0 Or cLa = 0 Or cLo = 0 Then
        If Not wasOpen Then wb.Close False
        Application.ScreenUpdating = True
        Tell "ไฟล์นี้ไม่มีคอลัมน์ เวลากล่อง / ละติจูด / ลองจิจูด", True
        Exit Sub
    End If

    lastR = ws.Cells(ws.Rows.Count, cP).End(xlUp).Row
    For r = hdr + 1 To lastR
        plate = Trim$(CStr(ws.Cells(r, cP).Value))
        If Len(plate) > 0 Then
            t = GpsTime(ws.Cells(r, cT).Value)
            la = GpsNum(ws.Cells(r, cLa).Value)
            lo = GpsNum(ws.Cells(r, cLo).Value)
            If Len(t) = 0 Or la = "0" Or lo = "0" Then
                nSkip = nSkip + 1
            Else
                If inBatch > 0 Then body = body & ","
                spd = "0"
                If cS > 0 Then spd = GpsNum(ws.Cells(r, cS).Value)
                stt = ""
                If cSt > 0 Then stt = JsonEsc(CStr(ws.Cells(r, cSt).Value))
                body = body & "{""plate"":""" & JsonEsc(plate) & """,""time"":""" & t & """,""lat"":" & la & ",""lng"":" & lo & _
                       ",""speed"":" & spd & ",""status"":""" & stt & """}"
                inBatch = inBatch + 1
                nRows = nRows + 1
                If inBatch = 200 Then
                    resp = Api("POST", "/rest/v1/rpc/gps_push", "{""p_rows"":[" & body & "]}", "", ok)
                    If Not ok Then
                        failed = True
                    ElseIf mStatus < 200 Or mStatus > 299 Then
                        failed = True
                        failMsg = ErrText(resp)
                    Else
                        If IsNumeric(JsonStr(resp, "saved")) Then nSaved = nSaved + CLng(JsonStr(resp, "saved"))
                        If IsNumeric(JsonStr(resp, "skipped")) Then nSkip = nSkip + CLng(JsonStr(resp, "skipped"))
                        If IsNumeric(JsonStr(resp, "events")) Then nEv = nEv + CLng(JsonStr(resp, "events"))
                        body = "": inBatch = 0
                    End If
                    If failed Then Exit For
                End If
            End If
        End If
    Next r
    If Not wasOpen Then wb.Close False
    Set wb = Nothing
    Application.ScreenUpdating = True
    If failed Then
        If Len(failMsg) > 0 Then Tell "ส่งตำแหน่งไม่สำเร็จ: " & failMsg, True
        Exit Sub
    End If

    If inBatch > 0 Then
        resp = Api("POST", "/rest/v1/rpc/gps_push", "{""p_rows"":[" & body & "]}", "", ok)
        If Not ok Then Exit Sub
        If mStatus < 200 Or mStatus > 299 Then
            Tell "ส่งตำแหน่งไม่สำเร็จ: " & ErrText(resp), True
            Exit Sub
        End If
        If IsNumeric(JsonStr(resp, "saved")) Then nSaved = nSaved + CLng(JsonStr(resp, "saved"))
        If IsNumeric(JsonStr(resp, "skipped")) Then nSkip = nSkip + CLng(JsonStr(resp, "skipped"))
        If IsNumeric(JsonStr(resp, "events")) Then nEv = nEv + CLng(JsonStr(resp, "events"))
    End If

    Tell "ส่งตำแหน่งรถขึ้นระบบแล้ว " & CStr(nSaved) & " คัน" & _
         IIf(nSkip > 0, vbCrLf & "ข้าม (ข้อมูลไม่ครบ/ไม่ใช่ข้อมูลใหม่) " & CStr(nSkip) & " แถว", "") & _
         IIf(nEv > 0, vbCrLf & "GPS บันทึกสถานะรถให้อัตโนมัติ " & CStr(nEv) & " รายการ", "") & vbCrLf & vbCrLf & _
         "ดูตำแหน่งรถล่าสุดได้ที่หน้า ตั้งค่า ETA / GPS บนเว็บ"
    Exit Sub
Fail:
    Application.DisplayAlerts = True
    Application.ScreenUpdating = True
    On Error Resume Next
    If Not wb Is Nothing And Not wasOpen Then wb.Close False
    Tell "เกิดข้อผิดพลาด: " & Err.Description & vbCrLf & vbCrLf & "ถ้าเป็นปัญหาการเชื่อมต่อ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่", True
End Sub

' ---------------------------------------------------------------------------
'  ปุ่มบนชีต Plan และการออกจากระบบ
' ---------------------------------------------------------------------------
' ---------------------------------------------------------------------------
'  เติมพิกัดจุดส่งจากลิงก์แผนที่ในชีต Plan (ช่อง Map1-3)
'  ลิงก์เต็มระบบอ่านพิกัดเองได้ ลิงก์ย่อ (maps.app.goo.gl) ต้องตามไปดูลิงก์จริงที่ Google ก่อน
'  อ่านพิกัดจากหมุดจริง (!3d..!4d..) ก่อน ไม่ใช่จุดกลางแผนที่ (@..) และไม่เขียนทับพิกัดที่ตั้งไว้แล้ว
' ---------------------------------------------------------------------------
Private Function UrlDecode(ByVal s As String) As String
    Dim i As Long, out As String, v As Long
    i = 1
    Do While i <= Len(s)
        If Mid$(s, i, 1) = "%" And i + 2 <= Len(s) Then
            v = -1
            On Error Resume Next
            v = CLng("&H" & Mid$(s, i + 1, 2))
            On Error GoTo 0
            If v >= 0 And v < 128 Then
                out = out & Chr$(v)
                i = i + 3
            Else
                out = out & "%"
                i = i + 1
            End If
        Else
            out = out & Mid$(s, i, 1)
            i = i + 1
        End If
    Loop
    UrlDecode = out
End Function

' อ่านตัวเลข (เช่น 13.769657) ที่ขึ้นต้นที่ตำแหน่ง p
Private Function ReadNum(ByVal s As String, ByVal p As Long) As String
    Dim ch As String, q As Long
    q = p
    Do While q <= Len(s)
        ch = Mid$(s, q, 1)
        If (ch >= "0" And ch <= "9") Or ch = "." Or (q = p And ch = "-") Then
            q = q + 1
        Else
            Exit Do
        End If
    Loop
    ReadNum = Mid$(s, p, q - p)
End Function

Private Function CheckLL(ByVal la As String, ByVal lo As String) As String
    Dim a As Double, b As Double
    If InStr(la, ".") = 0 Or InStr(lo, ".") = 0 Then Exit Function
    a = Val(la)
    b = Val(lo)
    If a < -90 Or a > 90 Or b < -180 Or b > 180 Then Exit Function
    If a = 0 And b = 0 Then Exit Function
    CheckLL = Trim$(Str$(a)) & "|" & Trim$(Str$(b))
End Function

' หาพิกัดในข้อความ/ลิงก์ : คืน "ละติจูด|ลองจิจูด" ถ้าไม่พบคืนค่าว่าง
Private Function CoordFromText(ByVal s As String) As String
    Dim t As String, p As Long, p2 As Long, la As String, lo As String, k As Variant, kl As Long
    t = UrlDecode(UrlDecode(s))
    p = InStr(t, "!3d")
    If p > 0 Then
        p2 = InStr(p, t, "!4d")
        If p2 > 0 Then
            la = ReadNum(t, p + 3)
            lo = ReadNum(t, p2 + 3)
            CoordFromText = CheckLL(la, lo)
            If Len(CoordFromText) > 0 Then Exit Function
        End If
    End If
    For Each k In Array("@", "q=", "ll=", "center=", "query=", "destination=")
        kl = Len(CStr(k))
        p = InStr(t, CStr(k))
        If p > 0 Then
            la = ReadNum(t, p + kl)
            p2 = p + kl + Len(la)
            If Len(la) > 0 And Mid$(t, p2, 1) = "," Then
                lo = ReadNum(t, p2 + 1)
                CoordFromText = CheckLL(la, lo)
                If Len(CoordFromText) > 0 Then Exit Function
            End If
        End If
    Next k
End Function

Private Function IsShortLink(ByVal u As String) As Boolean
    u = LCase$(u)
    IsShortLink = (InStr(u, "goo.gl") > 0 Or InStr(u, "//g.co/") > 0 Or InStr(u, "maps.app") > 0)
End Function

' ตามลิงก์ย่อไปทีละขั้น (ไม่เกิน 6 ขั้น) คืนลิงก์สุดท้าย (หรือลิงก์เดิมถ้าเรียกไม่สำเร็จ)
Private Function ResolveMapLink(ByVal url As String) As String
    Dim x As Object, i As Long, cur As String, loc As String, st As Long, p As Long, body As String
    cur = url
    On Error GoTo Done
    For i = 1 To 6
        Set x = CreateObject("WinHttp.WinHttpRequest.5.1")
        x.SetTimeouts 5000, 5000, 10000, 15000
        x.Option(6) = False
        x.Open "GET", cur, False
        x.SetRequestHeader "User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
        x.SetRequestHeader "Accept-Language", "th,en;q=0.8"
        x.Send
        st = x.Status
        If st >= 300 And st < 400 Then
            loc = ""
            On Error Resume Next
            loc = x.GetResponseHeader("Location")
            On Error GoTo Done
            If Len(loc) = 0 Then Exit For
            If Left$(loc, 1) = "/" Then
                p = InStr(9, cur, "/")
                If p > 0 Then loc = Left$(cur, p - 1) & loc
            End If
            cur = loc
            If Len(CoordFromText(cur)) > 0 Then Exit For
        Else
            If st = 200 Then
                body = x.ResponseText
                p = InStr(body, "!3d")
                If p > 0 Then cur = cur & " " & Mid$(body, p, 60)
            End If
            Exit For
        End If
    Next i
Done:
    ResolveMapLink = cur
End Function

' อ่านรายการข้อความจาก JSON แบบ ["a","b"]
Private Function JsonStrArray(ByVal j As String) As Collection
    Dim out As New Collection, i As Long, ch As String, cur As String, inS As Boolean
    i = 1
    Do While i <= Len(j)
        ch = Mid$(j, i, 1)
        If inS Then
            If ch = "\" Then
                i = i + 1
                ch = Mid$(j, i, 1)
                If ch = "u" Then
                    cur = cur & ChrW$(CLng("&H" & Mid$(j, i + 1, 4)))
                    i = i + 4
                ElseIf ch = "n" Or ch = "r" Or ch = "t" Then
                    cur = cur & " "
                Else
                    cur = cur & ch
                End If
            ElseIf ch = """" Then
                out.Add cur
                cur = ""
                inS = False
            Else
                cur = cur & ch
            End If
        ElseIf ch = """" Then
            inS = True
        End If
        i = i + 1
    Loop
    Set JsonStrArray = out
End Function

' กุญแจเทียบชื่อจุดส่ง = ตัวพิมพ์เล็ก ไม่มีช่องว่าง (เหมือน place_key ในฐานข้อมูล)
Private Function PlaceKey(ByVal s As String) As String
    s = Norm(s)
    s = Replace(s, " ", "")
    PlaceKey = LCase$(s)
End Function

Private Function MapUrlOf(ByVal ws As Worksheet, ByVal r As Long, ByVal c As Long) As String
    Dim t As String
    t = CellText(ws, r, c)
    If LCase$(Left$(t, 4)) <> "http" Then
        If ws.Cells(r, c).Hyperlinks.Count > 0 Then t = ws.Cells(r, c).Hyperlinks(1).Address
    End If
    If LCase$(Left$(t, 4)) = "http" Then MapUrlOf = t
End Function

' เติมพิกัดให้จุดส่งที่ยังไม่มีพิกัด จากลิงก์แผนที่ในชีต ws (และ ws2 ถ้ามี) คืนข้อความสรุป (ว่าง = ไม่มีอะไรต้องทำ)
' ใช้หลังส่งงาน : ถ้าทำไม่สำเร็จจะไม่ทำให้การส่งงานล้มเหลว (คืนข้อความบรรทัดเดียวแทน)
Private Function AutoPlaces(ByVal ws As Worksheet, ByVal hdr As Long, ByVal ws2 As Worksheet, ByVal hdr2 As Long) As String
    Dim ok As Boolean, r As String, miss As Collection, want As New Collection, tried As New Collection
    Dim lastR As Long, rr As Long, k As Long, nm As String, key As String, url As String, co As String, p As Long
    Dim body As String, nOk As Long, nRes As Long, nFail As Long, fails As String, i As Long
    Dim sIdx As Long, cur As Worksheet, h As Long

    On Error GoTo Fail
    r = Api("POST", "/rest/v1/rpc/places_missing", "{}", "", ok)
    If Not ok Then Exit Function
    If mStatus < 200 Or mStatus > 299 Then
        AutoPlaces = "เติมพิกัดจุดส่งอัตโนมัติไม่สำเร็จ (กดปุ่มเติมพิกัดจุดส่งอีกครั้งได้)"
        Exit Function
    End If
    Set miss = JsonStrArray(r)
    If miss.Count = 0 Then Exit Function
    For i = 1 To miss.Count
        key = PlaceKey(CStr(miss.Item(i)))
        If Len(key) > 0 Then
            If Not HasKey(want, key) Then want.Add "1", key
        End If
    Next i

    For sIdx = 1 To 2
        Set cur = Nothing
        h = 0
        If sIdx = 1 Then
            Set cur = ws
            h = hdr
        Else
            Set cur = ws2
            h = hdr2
        End If
        If Not cur Is Nothing And h > 0 Then
            lastR = cur.Cells(cur.Rows.Count, 1).End(xlUp).Row
            For rr = h + 1 To lastR
                For k = 0 To 2
                    nm = Norm(CellText(cur, rr, 16 + 3 * k))
                    If Len(nm) > 0 Then
                        key = PlaceKey(nm)
                        If HasKey(want, key) And Not HasKey(tried, key) Then
                            url = MapUrlOf(cur, rr, 17 + 3 * k)
                            If Len(url) > 0 And nRes < 60 Then
                                tried.Add "1", key
                                co = CoordFromText(url)
                                If Len(co) = 0 And IsShortLink(url) Then
                                    nRes = nRes + 1
                                    If Not mSilent Then Application.StatusBar = "กำลังอ่านพิกัดจากลิงก์แผนที่ " & CStr(nRes) & " ..."
                                    co = CoordFromText(ResolveMapLink(url))
                                End If
                                If Len(co) > 0 Then
                                    p = InStr(co, "|")
                                    If Len(body) > 0 Then body = body & ","
                                    body = body & "{""name"":""" & JsonEsc(nm) & """,""lat"":" & Left$(co, p - 1) & ",""lng"":" & Mid$(co, p + 1) & "}"
                                    nOk = nOk + 1
                                Else
                                    nFail = nFail + 1
                                    If nFail <= 6 Then fails = fails & vbCrLf & "  - " & nm
                                End If
                            End If
                        End If
                    End If
                Next k
            Next rr
        End If
    Next sIdx
    Application.StatusBar = False

    If Len(body) > 0 Then
        r = Api("POST", "/rest/v1/rpc/places_auto", "{""p_rows"":[" & body & "]}", "", ok)
        If Not ok Or mStatus < 200 Or mStatus > 299 Then
            AutoPlaces = "เติมพิกัดจุดส่งไม่สำเร็จ: " & ErrText(r)
            Exit Function
        End If
        AutoPlaces = "เติมพิกัดจุดส่งอัตโนมัติจากลิงก์แผนที่ " & CStr(nOk) & " จุด"
    End If
    If nFail > 0 Then
        If Len(AutoPlaces) > 0 Then AutoPlaces = AutoPlaces & vbCrLf
        AutoPlaces = AutoPlaces & "อ่านพิกัดจากลิงก์ไม่ได้ " & CStr(nFail) & " จุด (ใส่เองที่หน้า ตั้งค่า ETA / GPS):" & fails
    End If
    Exit Function
Fail:
    Application.StatusBar = False
    AutoPlaces = "เติมพิกัดจุดส่งอัตโนมัติไม่สำเร็จ (กดปุ่มเติมพิกัดจุดส่งอีกครั้งได้)"
End Function

' ปุ่ม "เติมพิกัดจุดส่งจากลิงก์" : ทำเฉพาะจุดส่งที่ยังไม่มีพิกัด อ่านลิงก์จากทั้งชีต Plan และ Plan_Backup (ใช้กับงานที่ส่งขึ้นระบบไปก่อนหน้านี้ได้)
Public Sub DP_FillPlaces()
    Dim ws As Worksheet, hdr As Long, wsB As Worksheet, hdrB As Long, m As String
    On Error GoTo Fail
    Set ws = FindSheet(PLAN_SHEET)
    Set wsB = FindSheet(BACKUP_SHEET)
    If ws Is Nothing And wsB Is Nothing Then
        Tell "ไม่พบชีต " & PLAN_SHEET & " หรือ " & BACKUP_SHEET & " ในไฟล์นี้", True
        Exit Sub
    End If
    If Not ws Is Nothing Then hdr = HeaderRow(ws)
    If Not wsB Is Nothing Then hdrB = HeaderRow(wsB)
    If hdr = 0 And hdrB = 0 Then
        Tell "ไม่พบหัวตาราง (คอลัมน์ A ต้องมีคำว่า Task Code) ในชีต " & PLAN_SHEET & " หรือ " & BACKUP_SHEET, True
        Exit Sub
    End If
    If Len(GetToken()) = 0 Then Exit Sub
    m = AutoPlaces(ws, hdr, wsB, hdrB)
    If Len(m) = 0 Then m = "ไม่มีจุดส่งที่ต้องเติมพิกัด (มีพิกัดครบแล้ว หรือไม่มีลิงก์แผนที่ในชีต)"
    Tell m
    Exit Sub
Fail:
    Application.StatusBar = False
    Tell "เกิดข้อผิดพลาด: " & Err.Description, True
End Sub

' สร้างปุ่มบนชีต ws (แถวละ 4 ปุ่ม) ลบปุ่มเดิมของมาโครนี้ก่อน
Private Sub MakeButtons(ByVal ws As Worksheet)
    Dim i As Long, b As Object, x As Double, y As Double, caps As Variant, macros As Variant
    For i = ws.Buttons.Count To 1 Step -1
        If Left$(ws.Buttons(i).Name, 6) = "DPbtn_" Then ws.Buttons(i).Delete
    Next i
    caps = Array("ส่งงานใหม่ (" & PLAN_SHEET & ")", "ส่งค่าที่แก้ไข (" & BACKUP_SHEET & ")", "ดึงข้อมูลลง " & BACKUP_SHEET, "ดึง Log", "Delay Trend", "ส่งตำแหน่ง GPS", "เติมพิกัดจุดส่ง", "Backup ทั้งหมด")
    macros = Array("DP_SendNew", "DP_SendChanges", "DP_PullAll", "DP_PullLogs", "DP_PullDelay", "DP_PushGPS", "DP_FillPlaces", "DP_BackupAll")
    x = ws.Cells(1, COL_SYNC + 2).Left
    y = ws.Cells(1, 1).Top + 2
    For i = 0 To 7
        Set b = ws.Buttons.Add(x + (i Mod 4) * 190, y + (i \ 4) * 28, 180, 24)
        b.Name = "DPbtn_" & CStr(i + 1)
        b.Caption = caps(i)
        b.OnAction = macros(i)
    Next i
End Sub

Public Sub DP_SetupButtons()
    Dim ws As Worksheet, wsB As Worksheet
    Set ws = PlanSheet()
    If ws Is Nothing Then Exit Sub
    Set wsB = BackupSheet(True)
    MakeButtons ws
    If Not wsB Is Nothing Then MakeButtons wsB
    Tell "สร้างปุ่ม 8 ปุ่มไว้ทางขวาของตาราง (ถัดจากคอลัมน์ Z) ในชีต " & PLAN_SHEET & " และ " & BACKUP_SHEET & " เรียบร้อย" & vbCrLf & _
         "ส่งงานใหม่ : พิมพ์ที่ชีต " & PLAN_SHEET & vbCrLf & "แก้งานเดิม : แก้ที่ชีต " & BACKUP_SHEET & " แล้วกด ส่งค่าที่แก้ไข" & vbCrLf & "ลากย้ายตำแหน่งปุ่มได้ตามต้องการ"
End Sub

Public Sub DP_SignOut()
    mToken = ""
    mRefresh = ""
    mEmail = ""
    Tell "ออกจากระบบแล้ว ครั้งต่อไปที่กดปุ่มจะถามอีเมลและรหัสผ่านใหม่"
End Sub
