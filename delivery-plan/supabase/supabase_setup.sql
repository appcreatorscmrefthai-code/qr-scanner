-- =====================================================================
-- Delivery Plan : ตั้งค่าฐานข้อมูล Supabase   (รุ่น 2026.10.08-s11)
-- วิธีใช้ : Supabase > SQL Editor > New query > วางทั้งไฟล์นี้ > กด Run
-- รันซ้ำได้ ข้อมูลเดิมไม่หาย (ใช้ตอนผมส่งรุ่นแก้ไขมาให้)
-- =====================================================================

-- ---------- 1. ตาราง ----------
create table if not exists public.plan (
  task_code    text primary key,
  date         date not null,
  detail       text not null default '',
  client       text not null default '',          -- LN Num
  transport    text not null default '',
  schedule     text not null default '',          -- เวลานัดที่ต้นทาง HH:MM
  arr1         text not null default '',          -- เวลานัดถึงจุดที่ 1-3 HH:MM
  arr2         text not null default '',
  arr3         text not null default '',
  company      text not null default '',
  vehicle_type text not null default '',
  plate        text not null default '',
  driver       text not null default '',
  phone        text not null default '',
  round        text not null default '',          -- มีคำว่า "กลับ" = งานไป-กลับ
  stop1 text not null default '', map1 text not null default '', rec1 text not null default '',
  stop2 text not null default '', map2 text not null default '', rec2 text not null default '',
  stop3 text not null default '', map3 text not null default '', rec3 text not null default '',
  status       text not null default '',          -- Task Status : Canceled = งานยกเลิก
  key          text not null default substr(replace(gen_random_uuid()::text, '-', ''), 1, 16),   -- รหัสลับประจำงาน (อยู่ในลิงก์ QR)
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   text not null default ''
);
create index if not exists plan_date_idx on public.plan (date);

create table if not exists public.pickup_log (
  id        bigint generated always as identity primary key,
  time      timestamptz not null default now(),
  task_code text not null references public.plan (task_code) on update cascade,
  note      text not null default '',
  photos    text[] not null default '{}'
);
create index if not exists pickup_log_task_idx on public.pickup_log (task_code);

create table if not exists public.road_log (
  id        bigint generated always as identity primary key,
  time      timestamptz not null default now(),
  task_code text not null references public.plan (task_code) on update cascade,
  type      text not null check (type in ('checkin', 'depart', 'eta', 'road', 'arrive', 'unload', 'return')),
  stop      int  not null default 0,
  plate     text not null default '',
  old_plate text not null default '',
  note      text not null default '',
  eta1 text not null default '', eta2 text not null default '', eta3 text not null default '',
  road      text[] not null default '{}',
  unload    text[] not null default '{}',
  finish    boolean not null default false
);
create index if not exists road_log_task_idx on public.road_log (task_code);

create table if not exists public.edit_log (
  id        bigint generated always as identity primary key,
  time      timestamptz not null default now(),
  task_code text not null,
  source    text not null default '',
  field     text not null default '',
  old_value text not null default '',
  new_value text not null default '',
  by_user   text not null default ''
);
create index if not exists edit_log_task_idx on public.edit_log (task_code);

-- ที่มาของรายการใน Log : 'คน' = ผู้จัดส่ง/ผู้โหลดกรอกเอง, 'GPS' = ระบบบันทึกจากตำแหน่งรถ
alter table public.pickup_log add column if not exists source text not null default 'คน';
alter table public.road_log   add column if not exists source text not null default 'คน';
-- รุ่น s10 : เพิ่มรายการ 'depart' (รถออกจากต้นทาง) ใน road_log ; pickup_log ใช้เก็บรูปจากคลังสินค้าอย่างเดียว
alter table public.road_log drop constraint if exists road_log_type_check;
alter table public.road_log add constraint road_log_type_check check (type in ('checkin', 'depart', 'eta', 'road', 'arrive', 'unload', 'return'));
update public.pickup_log set source = 'GPS' where source <> 'GPS' and note like 'GPS อัตโนมัติ%';
update public.road_log   set source = 'GPS' where source <> 'GPS' and note like 'GPS อัตโนมัติ%';

-- ผู้ใช้ของ Dashboard : admin = ทำได้ทุกอย่าง (รวมลบงาน), edit = ส่งแผนและแก้ไขได้, viewer = ดูอย่างเดียว (ดูลิงก์และรูปได้)
create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  email   text not null default '',
  name    text not null default '',
  role    text not null default 'viewer' check (role in ('admin', 'edit', 'viewer')),
  active  boolean not null default true
);

-- ย้ายสิทธิ์จากรุ่นเก่า (edit / view) เป็น admin / edit / viewer : view -> viewer, และผู้ใช้ edit คนแรกสุดเป็น admin ถ้ายังไม่มี admin
alter table public.profiles drop constraint if exists profiles_role_check;
update public.profiles set role = 'viewer' where role = 'view';
alter table public.profiles add constraint profiles_role_check check (role in ('admin', 'edit', 'viewer'));
alter table public.profiles alter column role set default 'viewer';
update public.profiles set role = 'admin'
where not exists (select 1 from public.profiles where role = 'admin')
  and user_id = (select pp.user_id from public.profiles pp join auth.users u on u.id = pp.user_id where pp.role = 'edit' order by u.created_at limit 1);

-- ---------- 2. ตัวช่วย ----------
create or replace function public.hm(v text) returns text
language sql immutable as $$
  select case when m is null or m[1]::int > 23 or m[2]::int > 59 then ''
              else lpad(m[1], 2, '0') || ':' || m[2] end
  from (select regexp_match(coalesce(v, ''), '(\d{1,2})[:.](\d{2})') as m) x
$$;

create or replace function public.blank(v text) returns text
language sql immutable as $$
  select case when s = '-' then '' else s end
  from (select btrim(regexp_replace(coalesce(v, ''), '\s+', ' ', 'g')) as s) x
$$;

-- ทะเบียนรถ : "3 ฒผ 2186", "ฒผ 2186" หรือ "70-1234"  (ไม่ถูกรูปแบบคืนค่าว่าง)
create or replace function public.norm_plate(v text) returns text
language plpgsql immutable as $$
declare s text := btrim(regexp_replace(coalesce(v, ''), '\s+', ' ', 'g')); m text[];
begin
  m := regexp_match(s, '^(\d)?\s*([ก-ฮ]{2,3})\s*(\d{1,4})$');
  if m is not null then return coalesce(m[1] || ' ', '') || m[2] || ' ' || m[3]; end if;
  m := regexp_match(s, '^(\d{2})\s*-\s*(\d{4})$');
  if m is not null then return m[1] || '-' || m[2]; end if;
  return '';
end $$;

-- วันที่จาก Excel/Sheet : 2026-10-06, 6/10/2026, 06-10-2569 (พ.ศ.)
create or replace function public.to_date_loose(v text) returns date
language plpgsql immutable as $$
declare s text := btrim(coalesce(v, '')); m text[]; y int;
begin
  m := regexp_match(s, '^(\d{4})-(\d{1,2})-(\d{1,2})');
  if m is not null then
    y := m[1]::int; if y > 2400 then y := y - 543; end if;
    return make_date(y, m[2]::int, m[3]::int);
  end if;
  m := regexp_match(s, '^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})');
  if m is not null then
    y := m[3]::int; if y > 2400 then y := y - 543; end if;
    return make_date(y, m[2]::int, m[1]::int);
  end if;
  return null;
end $$;

create or replace function public.is_canceled(v text) returns boolean
language sql immutable as $$ select coalesce(v, '') ~* '(cancel|ยกเลิก)' $$;

create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and active)
$$;

create or replace function public.can_edit() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and active and role in ('admin', 'edit'))
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and active and role = 'admin')
$$;

-- ตรวจสิทธิ์เปิดฟอร์มมือถือ : ลิงก์ QR ไม่ใช้รหัสลับแล้ว (สร้างงานใหม่ด้วย Task Code เดิมแล้วลิงก์เดิมยังใช้ได้)
-- ตัวกัน : งานต้องไม่ถูกยกเลิก และวันที่งานต้องอยู่ในช่วง วันนี้-3 ถึง วันนี้+1 (เวลาไทย) ; p_key ที่ส่งมาจาก QR รุ่นเก่าไม่ถูกใช้ตรวจ
create or replace function public.form_window_ok(p_date date) returns boolean
language sql stable as $$
  select p_date between (now() at time zone 'Asia/Bangkok')::date - 3 and (now() at time zone 'Asia/Bangkok')::date + 1
$$;

create or replace function public.task_check(p_code text, p_key text) returns public.plan
language plpgsql stable security definer set search_path = public as $$
declare t public.plan;
begin
  select * into t from public.plan where upper(task_code) = upper(btrim(coalesce(p_code, '')));
  if not found then raise exception 'ไม่พบงานนี้ กรุณาตรวจ Task Code หรือสแกน QR ใหม่'; end if;
  if public.is_canceled(t.status) then raise exception 'งานนี้ถูกยกเลิกแล้ว (%)', t.task_code; end if;
  if not public.form_window_ok(t.date) then raise exception 'ลิงก์นี้ใช้ได้เฉพาะงานของวันนี้ (งานวันที่ %) กรุณาติดต่อผู้ประสานงาน', t.date; end if;
  return t;
end $$;

-- ---------- 3. ฟอร์มมือถือ (ไม่ต้องเข้าสู่ระบบ ใช้รหัสลับจาก QR) ----------
create or replace function public.form_task(p_code text, p_key text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t public.plan;
begin
  t := public.task_check(p_code, p_key);
  return jsonb_build_object(
    'plan', to_jsonb(t) - 'key',
    'pickup', (select coalesce(jsonb_agg(to_jsonb(l) order by l.id), '[]'::jsonb) from public.pickup_log l where l.task_code = t.task_code),
    'road',   (select coalesce(jsonb_agg(to_jsonb(l) order by l.id), '[]'::jsonb) from public.road_log l where l.task_code = t.task_code),
    'now', now());
end $$;

-- รายการรูปที่ส่งมา : รับเฉพาะรูปในโฟลเดอร์ของงานนี้ ไม่ซ้ำ ไม่เกินจำนวนสูงสุด
drop function if exists public.photo_list(jsonb, text, int);
create or replace function public.photo_list(p jsonb, p_prefix text, p_max int, p_key text) returns text[]
language sql immutable as $$
  select coalesce((array_agg(v order by ord))[1:p_max], '{}')
  from (select v, min(ord) as ord
        from jsonb_array_elements_text(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) with ordinality a(v, ord)
        where left(v, length(p_prefix)) = p_prefix and split_part(v, '/', 2) in ('p', p_key) and v !~ '\.\.' and length(v) < 300
        group by v) d
$$;

-- เวลาอ้างอิงของหน้าต่างอัปรูปลงงาน : ล่าสุดของรายการ ถึง/ลงงาน ของจุดนั้น (p_stop = 0 : รายการ 'กลับถึงต้นทาง') ; ยังไม่มีคืน null
create or replace function public.stop_photo_ref(p_task text, p_stop int) returns timestamptz
language sql stable security definer set search_path = public as $$
  select max(l.time) from public.road_log l
  where l.task_code = p_task and ((p_stop = 0 and l.type = 'return') or (p_stop > 0 and l.stop = p_stop and l.type in ('arrive', 'unload')))
$$;

create or replace function public.form_submit(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t public.plan; n int; rt boolean; v_note text; v_type text := coalesce(p->>'type', '');
  v_stop int := coalesce(nullif(p->>'stop', '')::int, 0); v_id bigint; v_fin boolean := false; v_now timestamptz := now();
  v_plate text; v_changed boolean; e text[]; ph text[]; pre text; v_last timestamptz; v_ref timestamptz;
begin
  t := public.task_check(p->>'taskCode', p->>'k');
  pre := t.task_code || '/';
  if (select count(*) from public.road_log where task_code = t.task_code) >= 300 or (select count(*) from public.pickup_log where task_code = t.task_code) >= 100 then
    raise exception 'ส่งข้อมูลของงานนี้ครบจำนวนสูงสุดแล้ว';
  end if;
  n := greatest(1, (t.stop1 <> '')::int + (t.stop2 <> '')::int + (t.stop3 <> '')::int);
  rt := t.round ~ 'กลับ';
  v_note := left(coalesce(p->>'note', ''), 2000);

  if p->>'form' = 'pickup' then
    -- รูปจากคลังสินค้า : ส่งได้เรื่อยๆ จนกว่าจะผ่าน 24 ชม. นับจากการอัปโหลดครั้งล่าสุด (ไม่บันทึกเวลารถออกอีกแล้ว)
    select max(time) into v_last from public.pickup_log where task_code = t.task_code and source <> 'GPS';
    if v_last is not null and v_now > v_last + interval '24 hours' then
      raise exception 'ปิดรับรูปจากคลังสินค้าแล้ว (เกิน 24 ชม. นับจากอัปโหลดครั้งล่าสุด)';
    end if;
    ph := public.photo_list(p->'photos', pre, 20, t.key);
    insert into public.pickup_log (time, task_code, note, photos) values (v_now, t.task_code, v_note, coalesce(ph[1:20], '{}')) returning id into v_id;

  elsif p->>'form' = 'driver' then
    e := array[public.hm(p->'eta'->>0), case when n >= 2 then public.hm(p->'eta'->>1) else '' end, case when n >= 3 then public.hm(p->'eta'->>2) else '' end];
    if v_type = 'checkin' then
      v_plate := public.norm_plate(p->>'plate');
      if v_plate = '' then raise exception 'รูปแบบทะเบียนรถไม่ถูกต้อง ตัวอย่าง: 3 ฒผ 2186'; end if;
      v_changed := v_plate <> t.plate;
      if v_changed then
        update public.plan set plate = v_plate, updated_at = v_now, updated_by = 'ผู้จัดส่ง' where task_code = t.task_code;
        insert into public.edit_log (time, task_code, source, field, old_value, new_value, by_user)
          values (v_now, t.task_code, 'ฟอร์มผู้จัดส่ง (เช็คอิน)', 'ทะเบียนรถ', t.plate, v_plate, 'ผู้จัดส่ง');
      end if;
      insert into public.road_log (time, task_code, type, plate, old_plate, note)
        values (v_now, t.task_code, 'checkin', v_plate, case when v_changed then coalesce(nullif(t.plate, ''), '(ว่าง)') else '' end, v_note) returning id into v_id;
    elsif v_type = 'depart' then
      select id into v_id from public.road_log where task_code = t.task_code and type = 'depart' order by id limit 1;
      if v_id is null then
        insert into public.road_log (time, task_code, type, note) values (v_now, t.task_code, 'depart', v_note) returning id into v_id;
      end if;
    elsif v_type = 'eta' then
      if e[1] || e[2] || e[3] = '' then raise exception 'กรุณาใส่เวลาที่คาดว่าจะถึงอย่างน้อย 1 จุด'; end if;
      insert into public.road_log (time, task_code, type, note, eta1, eta2, eta3)
        values (v_now, t.task_code, 'eta', v_note, e[1], e[2], e[3]) returning id into v_id;
    elsif v_type = 'road' then
      ph := public.photo_list(p->'road', pre, 5, t.key);
      if coalesce(array_length(ph, 1), 0) = 0 and v_note = '' and e[1] || e[2] || e[3] = '' and coalesce((p->>'pending')::boolean, false) = false then
        raise exception 'กรุณาแนบรูปหรือใส่หมายเหตุ';
      end if;
      insert into public.road_log (time, task_code, type, note, eta1, eta2, eta3, road)
        values (v_now, t.task_code, 'road', v_note, e[1], e[2], e[3], coalesce(ph[1:5], '{}')) returning id into v_id;
    elsif v_type in ('arrive', 'unload') then
      if v_stop < 1 or v_stop > n then raise exception 'จุดส่งไม่ถูกต้อง'; end if;
      ph := case when v_type = 'unload' then public.photo_list(p->'unload', pre, 20, t.key) else '{}' end;
      v_fin := v_type = 'unload' and v_stop = n and not rt;       -- ลงงานจุดสุดท้าย = จบงาน (งานไป-กลับจบเมื่อรถกลับถึงต้นทาง)
      insert into public.road_log (time, task_code, type, stop, note, unload, finish)
        values (v_now, t.task_code, v_type, v_stop, v_note, coalesce(ph[1:20], '{}'), v_fin) returning id into v_id;
    elsif v_type = 'return' then
      if not rt then raise exception 'งานนี้ไม่ใช่รอบไป-กลับ'; end if;
      v_fin := true;
      ph := public.photo_list(p->'unload', pre, 20, t.key);                  -- รูปลงงานที่ SCM (ถ้ามี)
      insert into public.road_log (time, task_code, type, note, unload, finish) values (v_now, t.task_code, 'return', v_note, coalesce(ph[1:20], '{}'), true) returning id into v_id;
    elsif v_type = 'photo' then
      -- แนบรูปลงงานย้อนหลัง (ฟอร์ม GPS) : จุดที่ v_stop (0 = รูปที่ SCM ตอนกลับถึง) ต้องมีบันทึกถึง/ลงงานแล้ว และยังไม่เกิน 24 ชม.
      v_ref := public.stop_photo_ref(t.task_code, v_stop);
      if v_ref is null then raise exception 'ยังไม่มีบันทึกว่ารถถึงจุดนี้ จึงยังแนบรูปไม่ได้'; end if;
      if v_now > v_ref + interval '24 hours' then raise exception 'ปิดรับรูปจุดนี้แล้ว (เกิน 24 ชม.)'; end if;
      select id into v_id from public.road_log
        where task_code = t.task_code and ((v_stop = 0 and type = 'return') or (v_stop > 0 and stop = v_stop and type in ('arrive', 'unload')))
        order by (type = 'unload') desc, id desc limit 1;
      if v_note <> '' then
        update public.road_log set note = left(case when note = '' then v_note else note || E'\n' || v_note end, 2000) where id = v_id;
      end if;
      ph := public.photo_list(p->'unload', pre, 20, t.key);
      if coalesce(array_length(ph, 1), 0) > 0 then
        update public.road_log set unload = coalesce((unload || ph)[1:20], '{}') where id = v_id;
      end if;
    else
      raise exception 'ไม่รู้จักประเภทรายการ';
    end if;
  else
    raise exception 'ไม่รู้จักฟอร์ม';
  end if;
  return jsonb_build_object('time', v_now, 'id', v_id, 'taskCode', t.task_code, 'finish', v_fin);
end $$;

-- แนบรูปเข้ารายการที่บันทึกไปแล้ว (เรียกซ้ำได้ รูปจะถูกเพิ่มต่อท้าย)
create or replace function public.form_attach(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.plan; v_id bigint := (p->>'id')::bigint; pre text; cur text[]; add text[]; v_type text; v_stop int; v_ref timestamptz; v_last timestamptz;
begin
  t := public.task_check(p->>'taskCode', p->>'k');
  pre := t.task_code || '/';
  if p->>'form' = 'pickup' then
    select photos into cur from public.pickup_log where id = v_id and task_code = t.task_code for update;
    if not found then raise exception 'ไม่พบรายการที่จะแนบรูป'; end if;
    add := public.photo_list(to_jsonb(cur) || coalesce(p->'photos', '[]'::jsonb), pre, 20, t.key);
    update public.pickup_log set photos = coalesce(add[1:20], '{}') where id = v_id;
  else
    select road, type, stop into cur, v_type, v_stop from public.road_log where id = v_id and task_code = t.task_code for update;
    if not found then raise exception 'ไม่พบรายการที่จะแนบรูป'; end if;
    if v_type in ('arrive', 'unload', 'return') then      -- รูปลงงาน : รับได้ถึง 24 ชม. หลังถึง/ลงงานจุดนั้น
      v_ref := public.stop_photo_ref(t.task_code, case when v_type = 'return' then 0 else v_stop end);
      if v_ref is null or now() > v_ref + interval '24 hours' then raise exception 'ปิดรับรูปจุดนี้แล้ว (เกิน 24 ชม.)'; end if;
    end if;
    add := public.photo_list(to_jsonb(cur) || coalesce(p->'road', '[]'::jsonb), pre, 5, t.key);
    update public.road_log set road = coalesce(add[1:5], '{}') where id = v_id;
    select unload into cur from public.road_log where id = v_id;
    add := public.photo_list(to_jsonb(cur) || coalesce(p->'unload', '[]'::jsonb), pre, 20, t.key);
    update public.road_log set unload = coalesce(add[1:20], '{}') where id = v_id;
  end if;
  return jsonb_build_object('id', v_id);
end $$;

-- ใช้ในกฎของที่เก็บรูป : อัปโหลดได้เฉพาะโฟลเดอร์ <Task Code>/p/ (หรือโฟลเดอร์รหัสลับรุ่นเก่า) ของงานที่ยังไม่ยกเลิกและอยู่ในช่วงวันที่ฟอร์มเปิด
create or replace function public.photo_path_ok(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.plan t
    where t.task_code = split_part(p_name, '/', 1) and split_part(p_name, '/', 2) in ('p', t.key)
      and public.form_window_ok(t.date)
      and split_part(p_name, '/', 3) ~ '^[A-Za-z0-9_.-]{1,80}\.jpg$' and split_part(p_name, '/', 4) = ''
      and not public.is_canceled(t.status))
$$;

-- ---------- 4. Dashboard (ต้องเข้าสู่ระบบ) ----------
-- สรุปรายวันของเดือน (YYYY-MM) สำหรับหน้าปฏิทิน
create or replace function public.month_summary(p_month text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d0 date := to_date(p_month || '-01', 'YYYY-MM-DD'); r jsonb;
begin
  if not public.is_member() then raise exception 'AUTH'; end if;
  select coalesce(jsonb_object_agg(d, jsonb_build_object('total', total, 'done', done, 'canceled', canceled)), '{}'::jsonb) into r
  from (
    select to_char(t.date, 'YYYY-MM-DD') as d,
           count(*) filter (where not public.is_canceled(t.status)) as total,
           count(*) filter (where not public.is_canceled(t.status) and exists (select 1 from public.road_log l where l.task_code = t.task_code and l.finish)) as done,
           count(*) filter (where public.is_canceled(t.status)) as canceled
    from public.plan t
    where t.date >= d0 and t.date < (d0 + interval '1 month')::date
    group by t.date) x;
  return r;
end $$;

-- แก้ไขข้อมูลแผนจาก Popup (เฉพาะผู้ใช้สิทธิ์ edit) บันทึกประวัติลง edit_log
create or replace function public.plan_edit(p_code text, p_changes jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; v text; m record; v_old text; v_who text; v_count int := 0; v_now timestamptz := now(); t public.plan;
begin
  if not public.can_edit() then raise exception 'FORBIDDEN'; end if;
  select coalesce(nullif(name, ''), email) into v_who from public.profiles where user_id = auth.uid();
  select * into t from public.plan where task_code = p_code for update;
  if not found then raise exception 'ไม่พบ Task Code: %', p_code; end if;
  if public.is_canceled(t.status) then raise exception 'CANCELED'; end if;
  for k, v in select * from jsonb_each_text(coalesce(p_changes, '{}'::jsonb)) loop
    select * into m from (values
      ('detail','detail','text','Detail'), ('client','client','text','Client Name'), ('transport','transport','text','Transport'),
      ('pickup','schedule','time','Schedule'), ('arr1','arr1','time','Arrival Time 1'), ('arr2','arr2','time','Arrival Time 2'), ('arr3','arr3','time','Arrival Time 3'),
      ('company','company','text','ชื่อบริษัทขนส่ง'), ('vehicleType','vehicle_type','text','ประเภทรถ'), ('plate','plate','plate','ทะเบียนรถ'),
      ('driver','driver','text','ชื่อผู้ขับ'), ('phone','phone','text','เบอร์โทรผู้ขับ'), ('round','round','text','รอบขนส่ง'),
      ('stop1','stop1','text','จุดที่ 1'), ('map1','map1','text','Map1'), ('rec1','rec1','text','ชื่อ-เบอร์โทรผู้รับ จุดที่ 1'),
      ('stop2','stop2','text','จุดที่ 2'), ('map2','map2','text','Map2'), ('rec2','rec2','text','ชื่อ-เบอร์โทรผู้รับ จุดที่ 2'),
      ('stop3','stop3','text','จุดที่ 3'), ('map3','map3','text','Map3'), ('rec3','rec3','text','ชื่อ-เบอร์โทรผู้รับ จุดที่ 3'),
      ('status','status','text','Task Status')) f(key, col, kind, label) where f.key = k;
    if not found then continue; end if;
    v := left(public.blank(v), 500);
    if m.kind = 'time' then
      if v <> '' and public.hm(v) = '' then raise exception '%: รูปแบบเวลาไม่ถูกต้อง (ชม.:นาที)', m.label; end if;
      v := public.hm(v);
    elsif m.kind = 'plate' and v <> '' then
      v := public.norm_plate(v);
      if v = '' then raise exception 'รูปแบบทะเบียนรถไม่ถูกต้อง ตัวอย่าง: 3 ฒผ 2186'; end if;
    end if;
    execute format('select %I from public.plan where task_code = $1', m.col) into v_old using p_code;
    if v_old is not distinct from v then continue; end if;
    execute format('update public.plan set %I = $1, updated_at = $2, updated_by = $3 where task_code = $4', m.col) using v, v_now, v_who, p_code;
    insert into public.edit_log (time, task_code, source, field, old_value, new_value, by_user)
      values (v_now, p_code, 'Dashboard (Popup)', m.label, coalesce(v_old, ''), v, v_who);
    v_count := v_count + 1;
  end loop;
  return jsonb_build_object('count', v_count);
end $$;

-- รับแผนจาก Excel / หน้านำเข้าแผน : เพิ่มงานใหม่ หรือแทนที่ข้อมูลของ Task Code เดิม (รหัสลับใน QR ไม่เปลี่ยน)
-- p_rows = [{ "task_code": "...", "date": "2026-10-06" หรือ "6/10/2026", "detail": "...", ... }]
create or replace function public.plan_sync(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; v_code text; v_date date; v_who text; v_ins int := 0; v_upd int := 0; v_now timestamptz := now(); v_new boolean;
begin
  if not public.can_edit() then raise exception 'FORBIDDEN'; end if;
  select coalesce(nullif(name, ''), email) into v_who from public.profiles where user_id = auth.uid();
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'ไม่มีข้อมูล'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_code := btrim(coalesce(r->>'task_code', ''));
    if v_code = '' then continue; end if;
    v_date := public.to_date_loose(r->>'date');
    if v_date is null then raise exception 'งาน %: วันที่ไม่ถูกต้อง (%)', v_code, coalesce(r->>'date', ''); end if;
    insert into public.plan as t (task_code, date, detail, client, transport, schedule, arr1, arr2, arr3, company, vehicle_type, plate, driver, phone, round,
        stop1, map1, rec1, stop2, map2, rec2, stop3, map3, rec3, status, updated_at, updated_by)
    values (v_code, v_date, public.blank(r->>'detail'), public.blank(r->>'client'), public.blank(r->>'transport'),
        public.hm(r->>'schedule'), public.hm(r->>'arr1'), public.hm(r->>'arr2'), public.hm(r->>'arr3'),
        public.blank(r->>'company'), public.blank(r->>'vehicle_type'), public.blank(r->>'plate'), public.blank(r->>'driver'), public.blank(r->>'phone'), public.blank(r->>'round'),
        public.blank(r->>'stop1'), public.blank(r->>'map1'), public.blank(r->>'rec1'), public.blank(r->>'stop2'), public.blank(r->>'map2'), public.blank(r->>'rec2'),
        public.blank(r->>'stop3'), public.blank(r->>'map3'), public.blank(r->>'rec3'), public.blank(r->>'status'), v_now, v_who)
    on conflict (task_code) do update set
        date = excluded.date, detail = excluded.detail, client = excluded.client, transport = excluded.transport, schedule = excluded.schedule,
        arr1 = excluded.arr1, arr2 = excluded.arr2, arr3 = excluded.arr3, company = excluded.company, vehicle_type = excluded.vehicle_type,
        plate = excluded.plate, driver = excluded.driver, phone = excluded.phone, round = excluded.round,
        stop1 = excluded.stop1, map1 = excluded.map1, rec1 = excluded.rec1, stop2 = excluded.stop2, map2 = excluded.map2, rec2 = excluded.rec2,
        stop3 = excluded.stop3, map3 = excluded.map3, rec3 = excluded.rec3, status = excluded.status, updated_at = excluded.updated_at, updated_by = excluded.updated_by
    returning (t.created_at = v_now) into v_new;
    if v_new then v_ins := v_ins + 1; else v_upd := v_upd + 1; end if;
  end loop;
  return jsonb_build_object('inserted', v_ins, 'updated', v_upd);
end $$;

-- แก้ไขงานเดิมจาก Excel : ส่งมาเป็นแถวเต็ม เปลี่ยนเฉพาะช่องที่ต่างจากเดิม และบันทึกลง edit_log (ช่องทาง "Excel (Macro)")
-- p_rows = [{ "task_code": "...", "date": "...", "plate": "...", ... }]  ช่องที่ไม่ส่งมาจะไม่ถูกแตะ  Task Code ที่ไม่มีบนระบบจะถูกข้าม
create or replace function public.plan_update(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; v_code text; v_who text; v_now timestamptz := now(); m record; v text; v_old text; d date;
        n_rows int := 0; n_cells int := 0; n_miss int := 0; n_lock int := 0; v_hit boolean; v_status text;
begin
  if not public.can_edit() then raise exception 'FORBIDDEN'; end if;
  select coalesce(nullif(name, ''), email) into v_who from public.profiles where user_id = auth.uid();
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'ไม่มีข้อมูล'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_code := btrim(coalesce(r->>'task_code', ''));
    if v_code = '' then continue; end if;
    select status into v_status from public.plan where task_code = v_code for update;
    if not found then n_miss := n_miss + 1; continue; end if;
    if public.is_canceled(v_status) then n_lock := n_lock + 1; continue; end if;   -- งานที่ยกเลิกแล้วแก้ไม่ได้
    v_hit := false;
    for m in select * from (values
      ('date','date','date','Date'), ('detail','detail','text','Detail'), ('client','client','text','Client Name'), ('transport','transport','text','Transport'),
      ('schedule','schedule','time','Schedule'), ('arr1','arr1','time','Arrival Time 1'), ('arr2','arr2','time','Arrival Time 2'), ('arr3','arr3','time','Arrival Time 3'),
      ('company','company','text','ชื่อบริษัทขนส่ง'), ('vehicle_type','vehicle_type','text','ประเภทรถ'), ('plate','plate','plate','ทะเบียนรถ'),
      ('driver','driver','text','ชื่อผู้ขับ'), ('phone','phone','text','เบอร์โทรผู้ขับ'), ('round','round','text','รอบขนส่ง'),
      ('stop1','stop1','text','จุดที่ 1'), ('map1','map1','text','Map1'), ('rec1','rec1','text','ชื่อ-เบอร์โทรผู้รับ จุดที่ 1'),
      ('stop2','stop2','text','จุดที่ 2'), ('map2','map2','text','Map2'), ('rec2','rec2','text','ชื่อ-เบอร์โทรผู้รับ จุดที่ 2'),
      ('stop3','stop3','text','จุดที่ 3'), ('map3','map3','text','Map3'), ('rec3','rec3','text','ชื่อ-เบอร์โทรผู้รับ จุดที่ 3'),
      ('status','status','text','Task Status')) f(key, col, kind, label)
    loop
      if not (r ? m.key) then continue; end if;
      v := left(public.blank(r->>m.key), 500);
      if m.kind = 'date' then
        d := public.to_date_loose(r->>m.key);
        if d is null then raise exception 'งาน %: วันที่ไม่ถูกต้อง (%)', v_code, coalesce(r->>m.key, ''); end if;
        v := to_char(d, 'YYYY-MM-DD');
      elsif m.kind = 'time' then
        if v <> '' and public.hm(v) = '' then raise exception 'งาน %: %: รูปแบบเวลาไม่ถูกต้อง (ชม.:นาที)', v_code, m.label; end if;
        v := public.hm(v);
      elsif m.kind = 'plate' and v <> '' then
        v := public.norm_plate(v);
        if v = '' then raise exception 'งาน %: รูปแบบทะเบียนรถไม่ถูกต้อง', v_code; end if;
      end if;
      execute format('select %I::text from public.plan where task_code = $1', m.col) into v_old using v_code;
      if v_old is not distinct from v then continue; end if;
      execute format('update public.plan set %I = $1::%s, updated_at = $2, updated_by = $3 where task_code = $4', m.col, case when m.kind = 'date' then 'date' else 'text' end)
        using v, v_now, v_who, v_code;
      insert into public.edit_log (time, task_code, source, field, old_value, new_value, by_user)
        values (v_now, v_code, 'Excel (Macro)', m.label, coalesce(v_old, ''), v, v_who);
      n_cells := n_cells + 1;
      v_hit := true;
    end loop;
    if v_hit then n_rows := n_rows + 1; end if;
  end loop;
  return jsonb_build_object('rows', n_rows, 'cells', n_cells, 'missing', n_miss, 'locked', n_lock);
end $$;

-- ลบงาน (เฉพาะ admin) : ลบแผนพร้อม Log ของงานนั้น คืนรายการรูปที่ต้องลบใน Storage (หน้าเว็บลบรูปต่อให้)
create or replace function public.plan_delete(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_who text; v_photos text[]; v_status text;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  select coalesce(nullif(name, ''), email) into v_who from public.profiles where user_id = auth.uid();
  select status into v_status from public.plan where task_code = p_code for update;
  if not found then raise exception 'ไม่พบ Task Code: %', p_code; end if;
  if public.is_canceled(v_status) then raise exception 'CANCELED'; end if;   -- งานที่ยกเลิกแล้วลบไม่ได้ (กู้คืนก่อน)
  select coalesce(array_agg(distinct x), '{}') into v_photos from (
    select unnest(photos) as x from public.pickup_log where task_code = p_code
    union all select unnest(road) from public.road_log where task_code = p_code
    union all select unnest(unload) from public.road_log where task_code = p_code) a;
  delete from public.pickup_log where task_code = p_code;
  delete from public.road_log where task_code = p_code;
  delete from public.plan where task_code = p_code;
  insert into public.edit_log (task_code, source, field, old_value, new_value, by_user)
    values (p_code, 'Dashboard (Popup)', 'ลบงาน', p_code, '', v_who);
  return jsonb_build_object('photos', to_jsonb(v_photos));
end $$;

-- ยกเลิกงาน / กู้คืนงาน (เฉพาะ admin) : ตั้ง Task Status = Canceled (งานที่ยกเลิกแล้วแก้ไขและลบไม่ได้)
-- p_cancel = true ยกเลิก, false กู้คืน (กลับเป็นค่า Task Status ก่อนยกเลิก ถ้าไม่พบประวัติใช้ Used)
create or replace function public.plan_cancel(p_code text, p_cancel boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_who text; v_old text; v_new text; v_now timestamptz := now(); v_prev text; v_found boolean;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  select coalesce(nullif(name, ''), email) into v_who from public.profiles where user_id = auth.uid();
  select status into v_old from public.plan where task_code = p_code for update;
  if not found then raise exception 'ไม่พบ Task Code: %', p_code; end if;
  if p_cancel then
    if public.is_canceled(v_old) then raise exception 'งานนี้ถูกยกเลิกอยู่แล้ว'; end if;
    v_new := 'Canceled';
  else
    if not public.is_canceled(v_old) then raise exception 'งานนี้ไม่ได้ถูกยกเลิก'; end if;
    select old_value, true into v_prev, v_found from public.edit_log
      where task_code = p_code and field = 'Task Status' and public.is_canceled(new_value) and not public.is_canceled(old_value)
      order by id desc limit 1;
    v_new := case when coalesce(v_found, false) then v_prev else 'Used' end;
  end if;
  update public.plan set status = v_new, updated_at = v_now, updated_by = v_who where task_code = p_code;
  insert into public.edit_log (time, task_code, source, field, old_value, new_value, by_user)
    values (v_now, p_code, 'Dashboard (Popup)', 'Task Status', coalesce(v_old, ''), v_new, v_who);
  return jsonb_build_object('status', v_new);
end $$;

-- ---------- 5. ผู้ใช้ใหม่ : สร้างแถวใน profiles อัตโนมัติ (คนแรก = edit, คนถัดไป = view แก้ได้ในตาราง profiles) ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id, email, name, role)
  values (new.id, coalesce(new.email, ''), split_part(coalesce(new.email, ''), '@', 1),
          case when exists (select 1 from public.profiles) then 'viewer' else 'admin' end)
  on conflict (user_id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

insert into public.profiles (user_id, email, name, role)
select u.id, coalesce(u.email, ''), split_part(coalesce(u.email, ''), '@', 1),
       case when row_number() over (order by u.created_at) = 1 and not exists (select 1 from public.profiles) then 'admin' else 'viewer' end
from auth.users u
on conflict (user_id) do nothing;

-- ---------- 6. กฎสิทธิ์ (RLS) : อ่านได้เฉพาะผู้ใช้ที่เข้าสู่ระบบและยังใช้งานอยู่ การเขียนทั้งหมดต้องผ่านฟังก์ชันด้านบน ----------
alter table public.plan       enable row level security;
alter table public.pickup_log enable row level security;
alter table public.road_log   enable row level security;
alter table public.edit_log   enable row level security;
alter table public.profiles   enable row level security;

drop policy if exists plan_read on public.plan;
create policy plan_read on public.plan for select to authenticated using (public.is_member());
drop policy if exists pickup_read on public.pickup_log;
create policy pickup_read on public.pickup_log for select to authenticated using (public.is_member());
drop policy if exists road_read on public.road_log;
create policy road_read on public.road_log for select to authenticated using (public.is_member());
drop policy if exists edit_read on public.edit_log;
create policy edit_read on public.edit_log for select to authenticated using (public.is_member());
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (user_id = auth.uid() or public.can_edit());

grant usage on schema public to anon, authenticated;
revoke all on public.plan, public.pickup_log, public.road_log, public.edit_log, public.profiles from anon, authenticated;
grant select on public.plan, public.pickup_log, public.road_log, public.edit_log, public.profiles to authenticated;

revoke all on function public.task_check(text, text), public.form_task(text, text), public.form_submit(jsonb), public.form_attach(jsonb),
  public.photo_path_ok(text), public.month_summary(text), public.plan_edit(text, jsonb), public.plan_sync(jsonb), public.plan_update(jsonb),
  public.is_member(), public.can_edit(), public.is_admin(), public.plan_delete(text), public.plan_cancel(text, boolean), public.handle_new_user() from public, anon, authenticated;
grant execute on function public.form_task(text, text), public.form_submit(jsonb), public.form_attach(jsonb), public.photo_path_ok(text) to anon, authenticated;
grant execute on function public.month_summary(text), public.plan_edit(text, jsonb), public.plan_sync(jsonb), public.plan_update(jsonb), public.plan_delete(text), public.plan_cancel(text, boolean), public.is_member(), public.can_edit(), public.is_admin() to authenticated;

-- ---------- 7. อัปเดต Dashboard ทันทีเมื่อข้อมูลเปลี่ยน (Realtime) ----------
do $$
declare t text;
begin
  foreach t in array array['plan', 'pickup_log', 'road_log'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null; when undefined_object then null;
    end;
  end loop;
end $$;

-- ---------- 8. ที่เก็บรูป : bucket "photos" (ไม่เปิดสาธารณะ รับเฉพาะ JPEG ไม่เกิน 3 MB ต่อรูป) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 3145728, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists photos_upload on storage.objects;
create policy photos_upload on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'photos' and public.photo_path_ok(name));
drop policy if exists photos_delete on storage.objects;
create policy photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and public.is_admin());
drop policy if exists photos_read on storage.objects;
create policy photos_read on storage.objects for select to authenticated
  using (bucket_id = 'photos' and public.is_member());

-- ---------- 9. มุมมองสำหรับดึงข้อมูลลง Excel (ปุ่มใน Excel) : เวลาเป็นเวลาไทย อ่านได้เฉพาะผู้ใช้ที่เข้าสู่ระบบ ----------
create or replace view public.v_plan with (security_invoker = true) as
select t.task_code, to_char(t.date, 'YYYY-MM-DD') as date, t.detail, t.client, t.transport, t.schedule, t.arr1, t.arr2, t.arr3,
       t.company, t.vehicle_type, t.plate, t.driver, t.phone, t.round,
       t.stop1, t.map1, t.rec1, t.stop2, t.map2, t.rec2, t.stop3, t.map3, t.rec3, t.status,
       to_char(t.updated_at at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI:SS.US') as synced, t.updated_by
from public.plan t;

create or replace view public.v_pickup_log with (security_invoker = true) as
select l.id, t.date as task_date, to_char(l.time at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI:SS') as ts, l.task_code, l.note,
       coalesce(array_length(l.photos, 1), 0) as photo_count, array_to_string(l.photos, ' | ') as photos, l.source
from public.pickup_log l join public.plan t on t.task_code = l.task_code;

create or replace view public.v_road_log with (security_invoker = true) as
select l.id, t.date as task_date, to_char(l.time at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI:SS') as ts, l.task_code,
       case l.type when 'checkin' then 'เช็คอิน' when 'depart' then 'รถออก' when 'eta' then 'เวลาคาดถึง' when 'road' then 'บนถนน' when 'arrive' then 'ถึงหน้างาน'
                   when 'unload' then 'ลงงานเสร็จ' when 'return' then 'กลับถึงต้นทาง' else l.type end as type_th,
       nullif(l.stop, 0) as stop, l.plate, l.old_plate, l.note, l.eta1, l.eta2, l.eta3,
       coalesce(array_length(l.road, 1), 0) as road_count, array_to_string(l.road, ' | ') as road,
       coalesce(array_length(l.unload, 1), 0) as unload_count, array_to_string(l.unload, ' | ') as unload, l.finish, l.source
from public.road_log l join public.plan t on t.task_code = l.task_code;

create or replace view public.v_edit_log with (security_invoker = true) as
select l.id, t.date as task_date, to_char(l.time at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI:SS') as ts, l.task_code,
       l.source, l.field, l.old_value, l.new_value, l.by_user
from public.edit_log l left join public.plan t on t.task_code = l.task_code;

revoke all on public.v_plan, public.v_pickup_log, public.v_road_log, public.v_edit_log from public, anon, authenticated;
grant select on public.v_plan, public.v_pickup_log, public.v_road_log, public.v_edit_log to authenticated;

-- ---------- 10. GPS + ETA : ตำแหน่งรถจากระบบ GPS, พิกัดจุดส่ง, คำนวณเวลาถึง ----------
create table if not exists public.places (
  name_key   text primary key,                       -- ชื่อจุดส่ง (ตัดช่องว่าง/ตัวพิมพ์เล็ก) ให้ตรงกับช่อง "จุดที่ 1-3" ใน Plan
  name       text not null,
  lat        double precision not null check (lat between -90 and 90),
  lng        double precision not null check (lng between -180 and 180),
  radius_m   int not null default 200 check (radius_m between 20 and 5000),
  updated_at timestamptz not null default now()
);

create table if not exists public.gps_last (
  plate_key   text primary key,                      -- ทะเบียนที่ตัดช่องว่างและขีดออก
  plate       text not null default '',
  lat         double precision not null,
  lng         double precision not null,
  speed       numeric not null default 0,
  status      text not null default '',
  box_time    timestamptz not null,                  -- เวลาที่กล่อง GPS ส่งตำแหน่ง
  received_at timestamptz not null default now()
);

create table if not exists public.gps_pos (            -- ประวัติตำแหน่งสั้นๆ (เก็บ 3 วัน) ใช้หาความเร็วเฉลี่ยและตรวจว่าเคยอยู่ที่ต้นทาง
  id        bigint generated always as identity primary key,
  plate_key text not null,
  time      timestamptz not null,
  lat       double precision not null,
  lng       double precision not null,
  speed     numeric not null default 0
);
create unique index if not exists gps_pos_uq on public.gps_pos (plate_key, time);

create table if not exists public.eta_config (
  key   text primary key,
  value text not null default '',
  note  text not null default ''
);
insert into public.eta_config (key, value, note) values
  ('buffer_ok_min',    '15',  'ทันเวลา : ETA ต้องถึงก่อนเวลานัดอย่างน้อยกี่นาที (ใส่ 0 = ถึงไม่เกินเวลานัดก็ถือว่าทัน)'),
  ('late_tol_min',     '15',  'เสี่ยงสาย : ETA เลยเวลานัดได้ไม่เกินกี่นาที   เกินกว่านี้ = คาดว่าจะสาย'),
  ('detour_factor',    '1.3', 'ตัวคูณระยะทางถนนจริงเทียบกับระยะเส้นตรง (1.2-1.5)'),
  ('default_speed_kmh','45',  'ความเร็วเฉลี่ยที่ใช้คำนวณเมื่อไม่มีข้อมูลความเร็วล่าสุด (กม./ชม.)'),
  ('use_recent_speed', '1',   '1 = ใช้ความเร็วเฉลี่ยจาก GPS ช่วงล่าสุดของคันนั้น, 0 = ใช้ค่าเริ่มต้นอย่างเดียว'),
  ('recent_window_min','45',  'ช่วงเวลาย้อนหลังที่ใช้หาความเร็วเฉลี่ย (นาที)'),
  ('stale_gps_min',    '30',  'ตำแหน่ง GPS เก่าเกินกี่นาทีถือว่าไม่น่าเชื่อถือ (ไม่แสดง ETA)'),
  ('stop_radius_m',    '200', 'รัศมี (เมตร) ที่ถือว่ารถถึงจุดส่ง เมื่อจุดนั้นไม่ได้ตั้งรัศมีเฉพาะ'),
  ('unload_min',       '20',  'เวลาลงของต่อจุด (นาที) ใช้บวกเพิ่มเมื่อคำนวณจุดถัดไป'),
  ('origin_lat',       '',    'ละติจูดต้นทาง (SCM) เว้นว่าง = ไม่ตรวจเช็คอิน/ออก/กลับด้วย GPS'),
  ('origin_lng',       '',    'ลองจิจูดต้นทาง (SCM)'),
  ('origin_radius_m',  '300', 'รัศมี (เมตร) ของต้นทาง'),
  ('auto_events',      '1',   '1 = ให้ GPS บันทึกเช็คอิน/ออก/ถึงจุด/ลงงาน/กลับต้นทางให้อัตโนมัติ, 0 = ใช้ GPS แสดง ETA อย่างเดียว'),
  ('arrive_max_speed', '15',  'ถึงจุดส่งต้องความเร็วไม่เกินกี่ กม./ชม. (กันรถแค่ขับผ่าน)'),
  ('gps_day_start_hour','6',  'เริ่มติดตาม GPS ของงานวันใหม่ตั้งแต่กี่โมง (ชั่วโมง 0-23) งานที่เริ่มวิ่งแล้วติดตามต่อจนจบแม้ข้ามคืน'),
  ('gps_alert_min',    '15',  'Dashboard เตือนเมื่อบอต/ข้อมูล GPS ไม่อัปเดตเกินกี่นาที ระหว่างที่มีงานต้องติดตาม (0 = ไม่เตือน, วันอาทิตย์ไม่เตือน)')
on conflict (key) do nothing;

alter table public.places enable row level security;
alter table public.gps_last enable row level security;
alter table public.gps_pos enable row level security;
alter table public.eta_config enable row level security;
drop policy if exists places_read on public.places;
create policy places_read on public.places for select to authenticated using (public.is_member());
drop policy if exists eta_config_read on public.eta_config;
create policy eta_config_read on public.eta_config for select to authenticated using (public.is_member());
revoke all on public.places, public.gps_last, public.gps_pos, public.eta_config from public, anon, authenticated;
grant select on public.places, public.eta_config to authenticated;

-- ตัวช่วย
create or replace function public.plate_key(v text) returns text
language sql immutable as $$ select lower(regexp_replace(coalesce(v, ''), '[\s-]+', '', 'g')) $$;

create or replace function public.place_key(v text) returns text
language sql immutable as $$ select lower(regexp_replace(coalesce(v, ''), '\s+', '', 'g')) $$;

create or replace function public.geo_km(a_lat double precision, a_lng double precision, b_lat double precision, b_lng double precision)
returns double precision language sql immutable as $$
  select 2 * 6371.0088 * asin(least(1, sqrt(
    power(sin(radians(b_lat - a_lat) / 2), 2) +
    cos(radians(a_lat)) * cos(radians(b_lat)) * power(sin(radians(b_lng - a_lng) / 2), 2))))
$$;

create or replace function public.cfgn(p_key text, p_def double precision) returns double precision
language sql stable security definer set search_path = public as $$
  select coalesce((select case when value ~ '^\s*-?\d+(\.\d+)?\s*$' then value::double precision end from public.eta_config where key = p_key), p_def)
$$;

-- พิกัดจากลิงก์/ข้อความแผนที่ (Google Maps ที่มี @lat,lng หรือ q=lat,lng หรือ !3d..!4d..) ลิงก์ย่อ (goo.gl) อ่านพิกัดไม่ได้ ต้องใส่ในตาราง places
create or replace function public.coord_from_map(v text) returns double precision[]
language plpgsql immutable as $$
declare m text[]; la double precision; lo double precision;
begin
  m := regexp_match(coalesce(v, ''), '!3d(-?\d{1,2}\.\d+)!4d(-?\d{1,3}\.\d+)');
  if m is null then m := regexp_match(coalesce(v, ''), '(-?\d{1,2}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})'); end if;
  if m is null then return null; end if;
  la := m[1]::double precision; lo := m[2]::double precision;
  if la not between -90 and 90 or lo not between -180 and 180 then return null; end if;
  return array[la, lo];
end $$;

-- [lat, lng, radius_m] ของจุดส่ง : ตาราง places ก่อน ไม่มีค่อยอ่านจากลิงก์แผนที่
create or replace function public.stop_geo(p_name text, p_map text) returns double precision[]
language plpgsql stable security definer set search_path = public as $$
declare pl public.places; c double precision[];
begin
  select * into pl from public.places where name_key = public.place_key(p_name);
  if found then return array[pl.lat, pl.lng, pl.radius_m::double precision]; end if;
  c := public.coord_from_map(p_map);
  if c is not null then return array[c[1], c[2], public.cfgn('stop_radius_m', 200)]; end if;
  return null;
end $$;

-- เวลานัด [ต้นทาง, จุด1, จุด2, จุด3] เป็นเวลาไทย  งานข้ามวัน: ถ้าเวลาถัดไป "น้อยกว่า" เวลาก่อนหน้า ถือว่าข้ามเที่ยงคืน (+1 วัน) สะสมต่อไป
create or replace function public.plan_times(p_date date, p_sched text, p_a1 text, p_a2 text, p_a3 text) returns timestamptz[]
language plpgsql immutable as $$
declare src text[] := array[p_sched, p_a1, p_a2, p_a3]; res timestamptz[] := array[null, null, null, null]::timestamptz[];
  prev timestamptz; cur timestamptz; h text; i int; off int := 0;
begin
  for i in 1..4 loop
    h := public.hm(src[i]);
    if h = '' then continue; end if;
    cur := ((p_date + off) + h::time)::timestamp at time zone 'Asia/Bangkok';
    if prev is not null and cur < prev then
      off := off + 1;
      cur := ((p_date + off) + h::time)::timestamp at time zone 'Asia/Bangkok';
    end if;
    res[i] := cur; prev := cur;
  end loop;
  return res;
end $$;

-- ---------- รับตำแหน่งรถ (ปุ่มใน Excel) แล้วให้ GPS บันทึกเหตุการณ์ตามพิกัด ----------
create or replace function public.gps_events(p_key text) returns int
language plpgsql security definer set search_path = public as $$
declare
  g public.gps_last; p public.plan; n int := 0;
  today date := (now() at time zone 'Asia/Bangkok')::date;
  o_lat double precision := public.cfgn('origin_lat', null); o_lng double precision := public.cfgn('origin_lng', null);
  o_r double precision := public.cfgn('origin_radius_m', 300); amax double precision := public.cfgn('arrive_max_speed', 15);
  eff text; pt timestamptz[]; names text[]; maps text[]; slots int[]; ns int; i int; k0 int; rt boolean; fin boolean;
  has_ci boolean; has_dp boolean; d_o double precision; geo double precision[]; d double precision; was boolean;
begin
  select * into g from public.gps_last where plate_key = p_key;
  if not found or g.box_time < now() - interval '30 minutes' then return 0; end if;
  if o_lat is not null and o_lng is not null then d_o := public.geo_km(g.lat, g.lng, o_lat, o_lng) * 1000; end if;

  for p in select * from public.plan t where t.date between today - 2 and today and not public.is_canceled(t.status) order by t.date, t.schedule, t.task_code loop
    eff := coalesce((select l.plate from public.road_log l where l.task_code = p.task_code and l.type = 'checkin' order by l.id limit 1), p.plate);
    if public.plate_key(eff) <> p_key then continue; end if;

    names := '{}'; maps := '{}'; slots := '{}';
    for i in 1..3 loop
      if public.blank(case i when 1 then p.stop1 when 2 then p.stop2 else p.stop3 end) <> '' then
        names := names || public.blank(case i when 1 then p.stop1 when 2 then p.stop2 else p.stop3 end);
        maps := maps || coalesce(case i when 1 then p.map1 when 2 then p.map2 else p.map3 end, '');
        slots := slots || i;
      end if;
    end loop;
    if coalesce(array_length(names, 1), 0) = 0 then names := array[public.blank(p.detail)]; maps := array['']; slots := array[1]; end if;
    ns := array_length(names, 1);
    rt := p.round like '%กลับ%';

    fin := case when rt then exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'return')
                else exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'unload' and l.stop = ns) end;
    if fin then continue; end if;

    pt := public.plan_times(p.date, p.schedule, p.arr1, p.arr2, p.arr3);
    if pt[1] is not null and now() < pt[1] - interval '90 minutes' then continue; end if;      -- ยังไม่ถึงเวลางานนี้

    has_ci := exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'checkin');
    has_dp := exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'depart');

    -- ต้นทาง : เช็คอิน / ออก
    if d_o is not null then
      if not has_ci and not has_dp and d_o <= o_r and (pt[1] is null or now() <= pt[1] + interval '6 hours') then
        insert into public.road_log (time, task_code, type, plate, note, source) values (g.box_time, p.task_code, 'checkin', eff, 'GPS อัตโนมัติ: รถเข้าต้นทาง', 'GPS');
        has_ci := true; n := n + 1;
      elsif not has_dp and d_o > o_r * 1.5 then
        was := has_ci or exists (select 1 from public.gps_pos q where q.plate_key = p_key
                 and q.time >= (p.date::timestamp at time zone 'Asia/Bangkok') - interval '12 hours'
                 and public.geo_km(q.lat, q.lng, o_lat, o_lng) * 1000 <= o_r);
        if was then
          insert into public.road_log (time, task_code, type, plate, note, source) values (g.box_time, p.task_code, 'depart', eff, 'GPS อัตโนมัติ: รถออกจากต้นทาง', 'GPS');
          has_dp := true; n := n + 1;
        end if;
      end if;
    end if;

    -- จุดส่ง : ถึง / ลงงานเสร็จ (ทำทีละจุดตามลำดับ)
    if has_dp or has_ci or d_o is null then
      k0 := null;
      for i in 1..ns loop
        if not exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'unload' and l.stop = i) then k0 := i; exit; end if;
      end loop;
      if k0 is not null then
        geo := public.stop_geo(names[k0], maps[k0]);
        if geo is not null then
          d := public.geo_km(g.lat, g.lng, geo[1], geo[2]) * 1000;
          if not exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'arrive' and l.stop = k0) then
            if d <= geo[3] and g.speed <= amax then
              insert into public.road_log (time, task_code, type, stop, plate, note, source) values (g.box_time, p.task_code, 'arrive', k0, eff, 'GPS อัตโนมัติ: รถถึงจุดส่ง', 'GPS');
              n := n + 1;
            end if;
          elsif d > geo[3] * 1.5 then
            insert into public.road_log (time, task_code, type, stop, plate, note, source) values (g.box_time, p.task_code, 'unload', k0, eff, 'GPS อัตโนมัติ: รถออกจากจุดส่ง', 'GPS');
            n := n + 1;
          end if;
        end if;
      elsif rt and d_o is not null and d_o <= o_r
            and not exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'return') then
        insert into public.road_log (time, task_code, type, plate, note, source) values (g.box_time, p.task_code, 'return', eff, 'GPS อัตโนมัติ: รถกลับถึงต้นทาง', 'GPS');
        n := n + 1;
      end if;
    end if;
  end loop;
  return n;
end $$;

-- ---------- บอตดึง GPS : ถามก่อนทุกรอบว่าต้องดึงไหม + เฝ้าระวังบอตหยุด ----------
create table if not exists public.gps_health (
  id         int primary key default 1 check (id = 1),
  last_check timestamptz,                    -- บอตเรียก gps_need ครั้งล่าสุด (บอตยังทำงานอยู่)
  go         boolean not null default false, -- ผลล่าสุด : ต้องดึง GPS หรือไม่
  go_since   timestamptz                     -- เริ่มต้องดึงตั้งแต่เมื่อไร
);
insert into public.gps_health (id) values (1) on conflict do nothing;
alter table public.gps_health enable row level security;
revoke all on public.gps_health from public, anon, authenticated;

-- ต้องดึง GPS ตอนนี้ไหม : มีงานช่วง วันนี้-2..วันนี้ ที่ยังไม่จบ และ
--   (ก) เริ่มวิ่งแล้ว (มี Log) และ Log ล่าสุดไม่เกิน 18 ชม. หรือ
--   (ข) ยังไม่เริ่ม แต่เป็นงานวันนี้ ถึงเวลาเริ่มติดตามของวัน (ค่าเริ่มต้น 06:00) และอยู่ในช่วง เวลานัด-90 นาที ถึง +6 ชม.
-- p_bot = true เมื่อบอตเรียก (บันทึกว่าบอตยังทำงานอยู่) ; Dashboard เรียกด้วยค่าเริ่มต้นเพื่อแสดงคำเตือนเมื่อบอตหยุด
create or replace function public.gps_need(p_bot boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p public.plan; nowt timestamptz := now(); today date := (now() at time zone 'Asia/Bangkok')::date;
  day0 timestamptz := ((now() at time zone 'Asia/Bangkok')::date::timestamp + make_interval(secs => public.cfgn('gps_day_start_hour', 6) * 3600)) at time zone 'Asia/Bangkok';
  amin double precision := public.cfgn('gps_alert_min', 15);
  eff text; ns int; rt boolean; fin boolean; pt timestamptz[]; last_log timestamptz;
  n_open int := 0; n_active int := 0; n_today int := 0; n_done int := 0; v_go boolean; why text;
  h public.gps_health; last_push timestamptz; alert boolean := false; areason text := ''; sunday boolean;
begin
  if not public.is_member() then raise exception 'FORBIDDEN'; end if;
  for p in select * from public.plan t where t.date between today - 2 and today and not public.is_canceled(t.status) loop
    if p.date = today then n_today := n_today + 1; end if;
    eff := coalesce(nullif((select l.plate from public.road_log l where l.task_code = p.task_code and l.type = 'checkin' order by l.id limit 1), ''), p.plate);
    ns := greatest(1, (public.blank(p.stop1) <> '')::int + (public.blank(p.stop2) <> '')::int + (public.blank(p.stop3) <> '')::int);
    rt := p.round like '%กลับ%';
    fin := case when rt then exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'return')
                else exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'unload' and l.stop = ns) end;
    if fin then
      if p.date = today then n_done := n_done + 1; end if;
      continue;
    end if;
    n_open := n_open + 1;
    if public.plate_key(eff) = '' then continue; end if;          -- ไม่มีทะเบียน ติดตามด้วย GPS ไม่ได้
    select max(x.time) into last_log from (
      select l.time from public.road_log l where l.task_code = p.task_code
      union all select l.time from public.pickup_log l where l.task_code = p.task_code) x;
    if last_log is not null then
      if nowt - last_log <= interval '18 hours' then n_active := n_active + 1; end if;
    else
      pt := public.plan_times(p.date, p.schedule, p.arr1, p.arr2, p.arr3);
      if p.date = today and nowt >= day0 and (pt[1] is null or (nowt >= pt[1] - interval '90 minutes' and nowt <= pt[1] + interval '6 hours')) then
        n_active := n_active + 1;
      end if;
    end if;
  end loop;

  v_go := n_active > 0;
  why := case when v_go then 'มีงานที่ต้องติดตาม ' || n_active || ' งาน'
              when n_open = 0 and n_today > 0 then 'งานวันนี้จบครบแล้ว'
              when n_open = 0 then 'ไม่มีงานที่ต้องติดตาม'
              else 'ยังไม่ถึงเวลาติดตามงาน' end;

  select * into h from public.gps_health where id = 1;
  if p_bot and public.can_edit() then
    update public.gps_health set last_check = nowt, go = v_go,
           go_since = case when not v_go then null when not h.go or h.go_since is null then nowt else h.go_since end
      where id = 1 returning * into h;
  end if;
  select max(received_at) into last_push from public.gps_last;

  sunday := extract(dow from (now() at time zone 'Asia/Bangkok')) = 0;
  if v_go and amin > 0 and not sunday then
    if h.last_check is null or nowt - h.last_check > make_interval(secs => amin * 60) then
      alert := true; areason := 'บอตดึง GPS ไม่ได้ทำงาน';
    elsif h.go_since is not null and nowt - h.go_since > make_interval(secs => amin * 60)
          and (last_push is null or nowt - last_push > make_interval(secs => amin * 60)) then
      alert := true; areason := 'บอตทำงานแต่ส่งข้อมูล GPS ไม่สำเร็จ';
    end if;
  end if;

  return jsonb_build_object('go', v_go, 'active', n_active, 'open', n_open, 'today', n_today, 'today_done', n_done, 'reason', why,
    'last_push', last_push, 'last_check', h.last_check,
    'push_age_min', case when last_push is null then null else round((extract(epoch from nowt - last_push) / 60)::numeric, 1) end,
    'alert', alert, 'alert_reason', areason, 'now', nowt);
end $$;

-- p_rows = [{plate, time:"YYYY-MM-DD HH:MM:SS" (เวลาไทย), lat, lng, speed, status}]
create or replace function public.gps_push(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; k text; ts timestamptz; la double precision; lo double precision; sp numeric;
  n int := 0; saved int := 0; skipped int := 0; ev int := 0; keys text[] := '{}';
begin
  if not public.can_edit() then raise exception 'FORBIDDEN'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'BAD_REQUEST'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception 'TOO_MANY'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    n := n + 1;
    begin
      k := public.plate_key(r->>'plate');
      ts := ((r->>'time')::timestamp) at time zone 'Asia/Bangkok';
      la := (r->>'lat')::double precision; lo := (r->>'lng')::double precision;
      sp := coalesce(nullif(r->>'speed', '')::numeric, 0);
    exception when others then skipped := skipped + 1; continue;
    end;
    if k = '' or la not between -90 and 90 or lo not between -180 and 180 or (la = 0 and lo = 0) or ts > now() + interval '10 minutes' then
      skipped := skipped + 1; continue;
    end if;
    insert into public.gps_pos (plate_key, time, lat, lng, speed) values (k, ts, la, lo, sp) on conflict (plate_key, time) do nothing;
    insert into public.gps_last (plate_key, plate, lat, lng, speed, status, box_time, received_at)
      values (k, left(coalesce(r->>'plate', ''), 30), la, lo, sp, left(coalesce(r->>'status', ''), 40), ts, now())
      on conflict (plate_key) do update set plate = excluded.plate, lat = excluded.lat, lng = excluded.lng, speed = excluded.speed,
        status = excluded.status, box_time = excluded.box_time, received_at = excluded.received_at
        where excluded.box_time > public.gps_last.box_time;
    saved := saved + 1;
    if not k = any (keys) then keys := keys || k; end if;
  end loop;
  delete from public.gps_pos where time < now() - interval '3 days';
  if public.cfgn('auto_events', 1) >= 1 then
    foreach k in array keys loop ev := ev + public.gps_events(k); end loop;
  end if;
  return jsonb_build_object('rows', n, 'saved', saved, 'skipped', skipped, 'events', ev);
end $$;

-- ---------- คำนวณ ETA ของงานในวันที่ระบุ ----------
create or replace function public.eta_for(p_date date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  p public.plan; g public.gps_last; res jsonb := '[]'; ent jsonb; arr jsonb;
  buf double precision := public.cfgn('buffer_ok_min', 15); tol double precision := public.cfgn('late_tol_min', 15);
  detour double precision := greatest(1, public.cfgn('detour_factor', 1.3)); dspeed double precision := greatest(5, public.cfgn('default_speed_kmh', 45));
  stale double precision := public.cfgn('stale_gps_min', 30); unl double precision := greatest(0, public.cfgn('unload_min', 20));
  win double precision := public.cfgn('recent_window_min', 45); use_rs boolean := public.cfgn('use_recent_speed', 1) >= 1;
  eff text; pt timestamptz[]; names text[]; maps text[]; slots int[]; ns int; i int; k0 int; dep boolean; reason text;
  spd double precision; cnt int; avg_s numeric; geo double precision[]; prev_geo double precision[]; mins double precision; first_km double precision;
  eta timestamptz; diff double precision; st text; worst int; rank int; age double precision; ptime timestamptz; pending_unload boolean;
begin
  if not public.is_member() then raise exception 'FORBIDDEN'; end if;
  for p in select * from public.plan t where t.date = p_date and not public.is_canceled(t.status) order by t.schedule, t.task_code loop
    dep := exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type in ('depart', 'road', 'arrive', 'unload'));
    if not dep then continue; end if;
    names := '{}'; maps := '{}'; slots := '{}';
    for i in 1..3 loop
      if public.blank(case i when 1 then p.stop1 when 2 then p.stop2 else p.stop3 end) <> '' then
        names := names || public.blank(case i when 1 then p.stop1 when 2 then p.stop2 else p.stop3 end);
        maps := maps || coalesce(case i when 1 then p.map1 when 2 then p.map2 else p.map3 end, '');
        slots := slots || i;
      end if;
    end loop;
    if coalesce(array_length(names, 1), 0) = 0 then names := array[public.blank(p.detail)]; maps := array['']; slots := array[1]; end if;
    ns := array_length(names, 1);
    k0 := null;
    for i in 1..ns loop
      if not exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type in ('arrive', 'unload') and l.stop = i) then k0 := i; exit; end if;
    end loop;
    if k0 is null then continue; end if;                 -- ถึงครบทุกจุดแล้ว ไม่ต้องมี ETA
    pending_unload := exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'arrive' and l.stop < k0
                              and not exists (select 1 from public.road_log u where u.task_code = p.task_code and u.type = 'unload' and u.stop = l.stop));

    eff := coalesce((select l.plate from public.road_log l where l.task_code = p.task_code and l.type = 'checkin' order by l.id limit 1), p.plate);
    ent := jsonb_build_object('task_code', p.task_code, 'status', null, 'reason', null, 'stops', '[]'::jsonb);
    select * into g from public.gps_last where plate_key = public.plate_key(eff);
    if not found then
      res := res || jsonb_build_array(ent || jsonb_build_object('reason', 'ไม่มีข้อมูล GPS ของรถคันนี้')); continue;
    end if;
    age := extract(epoch from (now() - g.box_time)) / 60;
    ent := ent || jsonb_build_object('age_min', round(age::numeric, 0), 'lat', g.lat, 'lng', g.lng);
    if age > stale then
      res := res || jsonb_build_array(ent || jsonb_build_object('reason', format('ตำแหน่ง GPS เก่า %s นาที', round(age::numeric, 0)))); continue;
    end if;

    spd := dspeed;
    if use_rs then
      select avg(q.speed), count(*) into avg_s, cnt from public.gps_pos q
       where q.plate_key = g.plate_key and q.time >= now() - make_interval(mins => win::int) and q.speed >= 5;
      if cnt >= 3 and avg_s is not null then spd := least(80, greatest(15, avg_s::double precision)); end if;
    end if;

    pt := public.plan_times(p.date, p.schedule, p.arr1, p.arr2, p.arr3);
    arr := '[]'; worst := 0; mins := case when pending_unload then unl else 0 end; prev_geo := null; reason := null; first_km := null;
    for i in k0..ns loop
      geo := public.stop_geo(names[i], maps[i]);
      if geo is null then reason := format('จุดที่ %s ยังไม่มีพิกัด (เพิ่มในหน้าตั้งค่า ETA)', i); exit; end if;
      if i = k0 then
        first_km := public.geo_km(g.lat, g.lng, geo[1], geo[2]);
        if first_km * 1000 > geo[3] then mins := mins + first_km * detour / spd * 60; end if;
      else
        mins := mins + unl + public.geo_km(prev_geo[1], prev_geo[2], geo[1], geo[2]) * detour / spd * 60;
      end if;
      prev_geo := geo;
      eta := now() + make_interval(secs => (mins * 60)::int);
      ptime := pt[slots[i] + 1];
      st := null; rank := 0;
      if ptime is not null then
        diff := extract(epoch from (eta - ptime)) / 60;
        if diff <= -buf then st := 'ok'; rank := 1;
        elsif diff <= tol then st := 'risk'; rank := 2;
        else st := 'late'; rank := 3; end if;
        worst := greatest(worst, rank);
      end if;
      arr := arr || jsonb_build_array(jsonb_build_object('stop', i,
        'eta', to_char(eta at time zone 'Asia/Bangkok', 'YYYY-MM-DD"T"HH24:MI:SS') || '+07:00',
        'plan', case when ptime is null then null else to_char(ptime at time zone 'Asia/Bangkok', 'YYYY-MM-DD"T"HH24:MI:SS') || '+07:00' end,
        'min_left', round(mins::numeric, 0), 'diff_min', case when ptime is null then null else round(diff::numeric, 0) end, 'status', st));
    end loop;
    ent := ent || jsonb_build_object('stops', arr, 'speed', round(spd::numeric, 0), 'dist_km', round(first_km::numeric, 1), 'reason', reason,
      'status', case worst when 3 then 'late' when 2 then 'risk' when 1 then 'ok' else null end);
    res := res || jsonb_build_array(ent);
  end loop;
  return res;
end $$;

-- ---------- จัดการพิกัดจุดส่งและค่าตั้ง ----------
create or replace function public.places_set(p_name text, p_lat double precision, p_lng double precision, p_radius int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nm text := public.blank(p_name);
begin
  if not public.can_edit() then raise exception 'FORBIDDEN'; end if;
  if nm = '' then raise exception 'BAD_REQUEST'; end if;
  insert into public.places (name_key, name, lat, lng, radius_m, updated_at)
    values (public.place_key(nm), nm, p_lat, p_lng, coalesce(p_radius, 200), now())
    on conflict (name_key) do update set name = excluded.name, lat = excluded.lat, lng = excluded.lng, radius_m = excluded.radius_m, updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

-- เติมพิกัดจุดส่งอัตโนมัติ (Excel อ่านลิงก์ย่อให้แล้วส่งมา) : เพิ่มเฉพาะชื่อที่ยังไม่มีในตาราง ไม่เขียนทับค่าที่ตั้งเอง
-- p_rows = [{name, lat, lng}] คืนจำนวนที่เพิ่มจริง
create or replace function public.places_auto(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; nm text; la double precision; lo double precision; n int := 0; c int;
begin
  if not public.can_edit() then raise exception 'FORBIDDEN'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'BAD_REQUEST'; end if;
  if jsonb_array_length(p_rows) > 300 then raise exception 'TOO_MANY'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    begin
      nm := public.blank(r->>'name'); la := (r->>'lat')::double precision; lo := (r->>'lng')::double precision;
    exception when others then continue;
    end;
    if nm = '' or la not between -90 and 90 or lo not between -180 and 180 then continue; end if;
    insert into public.places (name_key, name, lat, lng) values (public.place_key(nm), nm, la, lo) on conflict (name_key) do nothing;
    get diagnostics c = row_count; n := n + c;
  end loop;
  return jsonb_build_object('added', n);
end $$;

create or replace function public.places_delete(p_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.can_edit() then raise exception 'FORBIDDEN'; end if;
  delete from public.places where name_key = public.place_key(p_name);
  return jsonb_build_object('ok', true);
end $$;

-- ชื่อจุดส่งของงานช่วงนี้ ที่ยังไม่มีพิกัด (ทั้งในตาราง places และลิงก์แผนที่)
create or replace function public.places_missing() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb;
begin
  if not public.is_member() then raise exception 'FORBIDDEN'; end if;
  select coalesce(jsonb_agg(x.name order by x.name), '[]') into res from (
    select distinct s.name from (
      select public.blank(t.stop1) as name, t.map1 as map, t.date from public.plan t
      union all select public.blank(t.stop2), t.map2, t.date from public.plan t
      union all select public.blank(t.stop3), t.map3, t.date from public.plan t) s
    where s.name <> '' and s.date >= (now() at time zone 'Asia/Bangkok')::date - 7
      and not exists (select 1 from public.places pl where pl.name_key = public.place_key(s.name))
      and public.coord_from_map(s.map) is null) x;
  return res;
end $$;

create or replace function public.eta_config_set(p_key text, p_value text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if not exists (select 1 from public.eta_config where key = p_key) then raise exception 'BAD_REQUEST'; end if;
  update public.eta_config set value = left(btrim(coalesce(p_value, '')), 100) where key = p_key;
  return jsonb_build_object('ok', true);
end $$;

-- ตำแหน่งล่าสุดของรถทุกคัน (ดึงลง Excel / ดูในหน้าตั้งค่า)
create or replace function public.gps_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_member() then raise exception 'FORBIDDEN'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('plate', plate, 'lat', lat, 'lng', lng, 'speed', speed, 'status', status,
          'time', to_char(box_time at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI:SS')) order by plate) from public.gps_last), '[]');
end $$;

create or replace function public.eta_settings() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_member() then raise exception 'FORBIDDEN'; end if;
  return jsonb_build_object(
    'config', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'value', value, 'note', note) order by key), '[]') from public.eta_config),
    'places', (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'lat', lat, 'lng', lng, 'radius', radius_m) order by name), '[]') from public.places));
end $$;

revoke all on function public.gps_events(text), public.gps_push(jsonb), public.eta_for(date), public.places_set(text, double precision, double precision, int),
  public.places_delete(text), public.places_auto(jsonb), public.gps_need(boolean), public.places_missing(), public.eta_config_set(text, text), public.gps_list(), public.eta_settings(), public.stop_geo(text, text), public.cfgn(text, double precision)
  from public, anon, authenticated;
grant execute on function public.gps_push(jsonb), public.eta_for(date), public.places_set(text, double precision, double precision, int),
  public.places_delete(text), public.places_auto(jsonb), public.gps_need(boolean), public.places_missing(), public.eta_config_set(text, text), public.gps_list(), public.eta_settings() to authenticated;

-- ---------- 11. รุ่น s10 : รถออก (depart), Delay Trend, หน้า GPS, Backup ----------
create table if not exists public.app_flags (key text primary key, value text not null default '', at timestamptz not null default now());
alter table public.app_flags enable row level security;
revoke all on public.app_flags from public, anon, authenticated;

-- ย้ายข้อมูลเก่าครั้งเดียว : รถออก (เดิมเก็บใน pickup_log) -> road_log type 'depart'
do $$
begin
  if not exists (select 1 from public.app_flags where key = 'migr_depart_s10') then
    insert into public.road_log (time, task_code, type, note, source)
    select distinct on (l.task_code) l.time, l.task_code, 'depart', left(l.note, 500), l.source
    from public.pickup_log l
    where not exists (select 1 from public.road_log r where r.task_code = l.task_code and r.type = 'depart')
    order by l.task_code, l.time, l.id;
    insert into public.app_flags (key, value) values ('migr_depart_s10', '1');
  end if;
end $$;

insert into public.eta_config (key, value, note) values
  ('delay_grace_min',   '0',  'Delay Trend : ถึงช้ากว่าเวลานัดไม่เกินกี่นาทีถือว่า "ทันเวลา" (0 = ต้องไม่เกินเวลานัด)'),
  ('gps_interval_min',  '5',  'ช่วงเวลาที่บอตดึง GPS (นาที) ใช้แสดงเวลาดึงรอบถัดไปในหน้า GPS')
on conflict (key) do nothing;

-- ---------- Delay Trend : เวลาถึงจริง เทียบเวลานัดของแต่ละจุด (ไม่ต้องเก็บเพิ่ม คิดจาก plan + road_log) ----------
create or replace function public.delay_rows(p_from date, p_to date)
returns table (task_code text, task_date date, stop int, stop_name text, company text, plate text, plan_at timestamptz, arrive_at timestamptz, diff_min int, source text)
language sql stable security definer set search_path = public as $$
  select t.task_code, t.date, s.i::int, s.nm, t.company, coalesce(nullif((select c.plate from public.road_log c where c.task_code = t.task_code and c.type = 'checkin' order by c.id limit 1), ''), t.plate),
         x.pt[s.slot + 1], a.time, round(extract(epoch from (a.time - x.pt[s.slot + 1])) / 60)::int, a.source
  from public.plan t
  cross join lateral (select public.plan_times(t.date, t.schedule, t.arr1, t.arr2, t.arr3) as pt) x
  cross join lateral (
    select row_number() over (order by v.k) as i, v.k as slot, coalesce(nullif(v.nm, ''), public.blank(t.detail)) as nm
    from (values (1, public.blank(t.stop1)), (2, public.blank(t.stop2)), (3, public.blank(t.stop3))) v(k, nm)
    where v.nm <> '' or (v.k = 1 and public.blank(t.stop1) || public.blank(t.stop2) || public.blank(t.stop3) = '')) s
  cross join lateral (
    select l.time, l.source from public.road_log l
    where l.task_code = t.task_code and l.type in ('arrive', 'unload') and l.stop = s.i order by l.time, l.id limit 1) a
  where t.date between p_from and p_to and not public.is_canceled(t.status) and x.pt[s.slot + 1] is not null
$$;

create or replace function public.delay_detail(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare grace double precision := public.cfgn('delay_grace_min', 0);
begin
  if not public.is_member() then raise exception 'FORBIDDEN'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'BAD_RANGE'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'task_code', r.task_code, 'date', to_char(r.task_date, 'YYYY-MM-DD'), 'stop', r.stop, 'stop_name', r.stop_name, 'company', r.company, 'plate', r.plate,
      'plan', to_char(r.plan_at at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI'), 'arrive', to_char(r.arrive_at at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI'),
      'diff_min', r.diff_min, 'ontime', r.diff_min <= grace, 'source', r.source) order by r.task_date, r.task_code, r.stop)
    from public.delay_rows(p_from, p_to) r), '[]'::jsonb);
end $$;

-- สรุปรายวัน (p_group = 'day') หรือรายเดือน ('month')
create or replace function public.delay_trend(p_from date, p_to date, p_group text default 'day') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare grace double precision := public.cfgn('delay_grace_min', 0);
begin
  if not public.is_member() then raise exception 'FORBIDDEN'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 800 then raise exception 'BAD_RANGE'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'period', g.period, 'n', g.n, 'ontime', g.ontime, 'late', g.n - g.ontime,
      'ontime_pct', round(100.0 * g.ontime / g.n, 1), 'avg_diff', round(g.avg_diff::numeric, 1), 'avg_late', round(g.avg_late::numeric, 1), 'max_late', g.max_late,
      'gps', g.gps) order by g.period)
    from (select case when p_group = 'month' then to_char(r.task_date, 'YYYY-MM') else to_char(r.task_date, 'YYYY-MM-DD') end as period,
                 count(*) as n, count(*) filter (where r.diff_min <= grace) as ontime, avg(r.diff_min) as avg_diff,
                 avg(r.diff_min) filter (where r.diff_min > grace) as avg_late, max(r.diff_min) filter (where r.diff_min > grace) as max_late,
                 count(*) filter (where r.source = 'GPS') as gps
          from public.delay_rows(p_from, p_to) r group by 1) g), '[]'::jsonb);
end $$;

-- ---------- หน้า GPS (gps.html) : ข้อมูลรวมทั้งหน้าในครั้งเดียว ----------
create or replace function public.gps_board(p_date date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p public.plan; today date := (now() at time zone 'Asia/Bangkok')::date; nowt timestamptz := now();
  buf double precision := public.cfgn('buffer_ok_min', 15); tol double precision := public.cfgn('late_tol_min', 15);
  o_lat double precision := public.cfgn('origin_lat', null); o_lng double precision := public.cfgn('origin_lng', null);
  etas jsonb := '{}'; d date; er jsonb; veh jsonb := '[]'; gl jsonb; ent jsonb; stops jsonb; sj jsonb;
  names text[]; maps text[]; slots int[]; ns int; i int; rt boolean; fin boolean; eff text; pk text; pt timestamptz[];
  has_dp boolean; has_ci boolean; at_site boolean; stt text; g public.gps_last; geo double precision[]; worst int; rk int;
  ptime timestamptz; a_t timestamptz; u_t timestamptz; hs text; hts timestamptz; diff double precision; st text; hst text; ge jsonb; gs jsonb;
  trail jsonb; cnt int; step int; dep_t timestamptz;
  k_total int := 0; k_wait int := 0; k_move int := 0; k_site int := 0; k_done int := 0; k_ok int := 0; k_risk int := 0; k_late int := 0;
  last_sync timestamptz; bot jsonb;
begin
  if not public.is_member() then raise exception 'FORBIDDEN'; end if;
  p_date := coalesce(p_date, today);
  -- ETA จาก GPS ของวันที่เกี่ยวข้อง
  for d in select distinct t.date from public.plan t where t.date between p_date - 2 and p_date and not public.is_canceled(t.status) loop
    er := public.eta_for(d);
    select coalesce(etas, '{}'::jsonb) || coalesce(jsonb_object_agg(e->>'task_code', e), '{}'::jsonb) into etas from jsonb_array_elements(er) e;
  end loop;

  for p in select * from public.plan t where t.date between p_date - 2 and p_date and not public.is_canceled(t.status) order by t.date, t.schedule, t.task_code loop
    names := '{}'; maps := '{}'; slots := '{}';
    for i in 1..3 loop
      if public.blank(case i when 1 then p.stop1 when 2 then p.stop2 else p.stop3 end) <> '' then
        names := names || public.blank(case i when 1 then p.stop1 when 2 then p.stop2 else p.stop3 end);
        maps := maps || coalesce(case i when 1 then p.map1 when 2 then p.map2 else p.map3 end, '');
        slots := slots || i;
      end if;
    end loop;
    if coalesce(array_length(names, 1), 0) = 0 then names := array[public.blank(p.detail)]; maps := array['']; slots := array[1]; end if;
    ns := array_length(names, 1);
    rt := p.round like '%กลับ%';
    fin := case when rt then exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'return')
                else exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'unload' and l.stop = ns) end;
    if p.date < p_date and fin then continue; end if;         -- งานข้ามวันที่จบแล้วไม่ต้องแสดง

    eff := coalesce(nullif((select l.plate from public.road_log l where l.task_code = p.task_code and l.type = 'checkin' order by l.id limit 1), ''), p.plate);
    pk := public.plate_key(eff);
    has_ci := exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'checkin');
    has_dp := exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type in ('depart', 'road', 'arrive', 'unload'));
    at_site := exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type = 'arrive'
                       and not exists (select 1 from public.road_log u where u.task_code = p.task_code and u.type = 'unload' and u.stop = l.stop));
    stt := case when fin then 'done' when at_site then 'site' when has_dp then 'moving' when has_ci then 'checkin' else 'waiting' end;
    select min(l.time) into dep_t from public.road_log l where l.task_code = p.task_code and l.type = 'depart';

    pt := public.plan_times(p.date, p.schedule, p.arr1, p.arr2, p.arr3);
    ge := etas -> p.task_code;
    stops := '[]'; worst := 0;
    for i in 1..ns loop
      geo := public.stop_geo(names[i], maps[i]);
      ptime := pt[slots[i] + 1];
      select min(l.time) into a_t from public.road_log l where l.task_code = p.task_code and l.type in ('arrive', 'unload') and l.stop = i;
      select min(l.time) into u_t from public.road_log l where l.task_code = p.task_code and l.type = 'unload' and l.stop = i;
      -- ETA ที่คนกรอก (ล่าสุด) ของจุดนี้
      hs := (select case slots[i] when 1 then nullif(l.eta1, '') when 2 then nullif(l.eta2, '') else nullif(l.eta3, '') end
             from public.road_log l where l.task_code = p.task_code and l.type in ('eta', 'road')
               and (case slots[i] when 1 then l.eta1 when 2 then l.eta2 else l.eta3 end) <> '' order by l.id desc limit 1);
      hst := null; hts := null;
      if hs is not null and a_t is null then
        hts := ((to_char(coalesce(ptime, p.date::timestamptz) at time zone 'Asia/Bangkok', 'YYYY-MM-DD') || ' ' || hs)::timestamp) at time zone 'Asia/Bangkok';
        if ptime is not null and hts < ptime - interval '12 hours' then hts := hts + interval '1 day'; end if;
        if ptime is not null then
          diff := extract(epoch from (hts - ptime)) / 60;
          hst := case when diff <= -buf then 'ok' when diff <= tol then 'risk' else 'late' end;
        end if;
      end if;
      gs := null;
      if ge is not null then select e into gs from jsonb_array_elements(coalesce(ge -> 'stops', '[]')) e where (e->>'stop')::int = i limit 1; end if;
      st := case when a_t is not null then null else coalesce(gs->>'status', hst) end;
      rk := case st when 'late' then 3 when 'risk' then 2 when 'ok' then 1 else 0 end;
      worst := greatest(worst, rk);
      stops := stops || jsonb_build_array(jsonb_build_object('i', i, 'name', names[i],
        'plan', case when ptime is null then null else to_char(ptime at time zone 'Asia/Bangkok', 'YYYY-MM-DD"T"HH24:MI:SS') || '+07:00' end,
        'arrive', case when a_t is null then null else to_char(a_t at time zone 'Asia/Bangkok', 'YYYY-MM-DD"T"HH24:MI:SS') || '+07:00' end,
        'done', case when u_t is null then null else to_char(u_t at time zone 'Asia/Bangkok', 'YYYY-MM-DD"T"HH24:MI:SS') || '+07:00' end,
        'eta_gps', gs->>'eta', 'diff_gps', gs->'diff_min', 'status_gps', gs->>'status',
        'eta_human', hs, 'status_human', hst, 'status', st,
        'lat', geo[1], 'lng', geo[2], 'radius', geo[3]));
    end loop;

    -- ตำแหน่งรถ + เส้นทางที่วิ่งมา
    sj := null; trail := '[]';
    if pk <> '' then
      select * into g from public.gps_last where plate_key = pk;
      if found then
        sj := jsonb_build_object('lat', g.lat, 'lng', g.lng, 'speed', g.speed, 'status', g.status,
          'time', to_char(g.box_time at time zone 'Asia/Bangkok', 'YYYY-MM-DD"T"HH24:MI:SS') || '+07:00', 'age_min', round((extract(epoch from (nowt - g.box_time)) / 60)::numeric, 0));
        if stt in ('moving', 'site', 'checkin') then
          select count(*) into cnt from public.gps_pos q where q.plate_key = pk and q.time >= coalesce(dep_t, nowt - interval '12 hours') - interval '10 minutes';
          step := greatest(1, ceil(cnt / 150.0)::int);
          select coalesce(jsonb_agg(jsonb_build_array(z.lat, z.lng) order by z.time), '[]') into trail from (
            select q.lat, q.lng, q.time, row_number() over (order by q.time) as rn from public.gps_pos q
            where q.plate_key = pk and q.time >= coalesce(dep_t, nowt - interval '12 hours') - interval '10 minutes') z where z.rn % step = 0;
        end if;
      end if;
    end if;

    if p.date = p_date or stt <> 'done' then
      if p.date = p_date then
        k_total := k_total + 1;
        if stt = 'done' then k_done := k_done + 1;
        elsif stt = 'site' then k_site := k_site + 1;
        elsif stt = 'moving' then k_move := k_move + 1;
        else k_wait := k_wait + 1; end if;
        if stt <> 'done' then
          if worst = 3 then k_late := k_late + 1; elsif worst = 2 then k_risk := k_risk + 1; elsif worst = 1 then k_ok := k_ok + 1; end if;
        end if;
      end if;
    end if;
    veh := veh || jsonb_build_array(jsonb_build_object('task_code', p.task_code, 'date', to_char(p.date, 'YYYY-MM-DD'), 'plate', eff, 'driver', p.driver, 'company', p.company,
      'schedule', p.schedule, 'detail', p.detail, 'round_trip', rt, 'state', stt, 'worst', case worst when 3 then 'late' when 2 then 'risk' when 1 then 'ok' else null end,
      'stops', stops, 'pos', sj, 'trail', trail, 'reason', ge->>'reason', 'speed_used', ge->'speed', 'dist_km', ge->'dist_km',
      'depart', case when dep_t is null then null else to_char(dep_t at time zone 'Asia/Bangkok', 'YYYY-MM-DD"T"HH24:MI:SS') || '+07:00' end));
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('plate', x.plate, 'lat', x.lat, 'lng', x.lng, 'speed', x.speed, 'status', x.status,
        'time', to_char(x.box_time at time zone 'Asia/Bangkok', 'YYYY-MM-DD"T"HH24:MI:SS') || '+07:00', 'age_min', round((extract(epoch from (nowt - x.box_time)) / 60)::numeric, 0),
        'task_code', (select v->>'task_code' from jsonb_array_elements(veh) v where public.plate_key(v->>'plate') = x.plate_key limit 1)) order by x.plate), '[]')
    into gl from public.gps_last x where x.box_time >= nowt - interval '2 days';
  select max(received_at) into last_sync from public.gps_last;
  bot := public.gps_need(false);
  return jsonb_build_object('now', nowt, 'date', to_char(p_date, 'YYYY-MM-DD'), 'last_sync', last_sync,
    'sync_age_min', case when last_sync is null then null else round((extract(epoch from (nowt - last_sync)) / 60)::numeric, 1) end,
    'next_import', case when last_sync is null or not coalesce((bot->>'go')::boolean, false) then null else last_sync + make_interval(mins => public.cfgn('gps_interval_min', 5)::int) end,
    'bot', bot, 'origin', case when o_lat is null or o_lng is null then null else jsonb_build_object('lat', o_lat, 'lng', o_lng, 'radius', public.cfgn('origin_radius_m', 300)) end,
    'thresholds', jsonb_build_object('buffer_ok_min', buf, 'late_tol_min', tol),
    'kpi', jsonb_build_object('total', k_total, 'waiting', k_wait, 'moving', k_move, 'site', k_site, 'done', k_done, 'ontime', k_ok, 'risk', k_risk, 'late', k_late),
    'vehicles', veh, 'gps', gl);
end $$;

-- ---------- Backup ----------
create table if not exists public.backup_state (
  id       int primary key default 1 check (id = 1),
  last_run timestamptz,
  last_ok  timestamptz,
  info     jsonb not null default '{}'
);
insert into public.backup_state (id) values (1) on conflict do nothing;
alter table public.backup_state enable row level security;
revoke all on public.backup_state from public, anon, authenticated;

-- ข้อมูลทั้งหมดสำหรับ Backup / ดาวน์โหลด Excel (เวลาเป็นเวลาไทย, รายการรูปเป็นอาร์เรย์) : p_from = เอางานตั้งแต่วันที่นี้ (ว่าง = ทั้งหมด)
create or replace function public.backup_export(p_from date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_member() then raise exception 'FORBIDDEN'; end if;
  return jsonb_build_object(
    'now', now(),
    'plan', (select coalesce(jsonb_agg((to_jsonb(t) - 'key' - 'created_at' - 'updated_at' - 'date') || jsonb_build_object('date', to_char(t.date, 'YYYY-MM-DD'),
              'created', to_char(t.created_at at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI:SS'), 'synced', to_char(t.updated_at at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI:SS')) order by t.date, t.task_code), '[]')
             from public.plan t where p_from is null or t.date >= p_from),
    'pickup', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'ts', to_char(l.time at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI:SS'), 'task_code', l.task_code,
              'note', l.note, 'photos', to_jsonb(l.photos), 'source', l.source) order by l.id), '[]')
             from public.pickup_log l join public.plan t on t.task_code = l.task_code where p_from is null or t.date >= p_from),
    'road', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'ts', to_char(l.time at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI:SS'), 'task_code', l.task_code,
              'type', l.type, 'stop', l.stop, 'plate', l.plate, 'old_plate', l.old_plate, 'note', l.note, 'eta1', l.eta1, 'eta2', l.eta2, 'eta3', l.eta3,
              'road', to_jsonb(l.road), 'unload', to_jsonb(l.unload), 'finish', l.finish, 'source', l.source) order by l.id), '[]')
             from public.road_log l join public.plan t on t.task_code = l.task_code where p_from is null or t.date >= p_from),
    'edit', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'ts', to_char(l.time at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI:SS'), 'task_code', l.task_code,
              'source', l.source, 'field', l.field, 'old_value', l.old_value, 'new_value', l.new_value, 'by_user', l.by_user) order by l.id), '[]')
             from public.edit_log l where p_from is null or l.time >= p_from::timestamp at time zone 'Asia/Bangkok'));
end $$;

-- บอต Backup รายงานผลหลังทำเสร็จ / ล้มเหลว (Dashboard และหน้า Backup แสดงเวลาล่าสุด)
create or replace function public.backup_report(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.can_edit() then raise exception 'FORBIDDEN'; end if;
  update public.backup_state set last_run = now(),
    last_ok = case when coalesce((p->>'ok')::boolean, false) then now() else last_ok end,
    info = jsonb_build_object('ok', coalesce((p->>'ok')::boolean, false), 'message', left(coalesce(p->>'message', ''), 500),
             'tasks', p->'tasks', 'photos_new', p->'photos_new', 'photos_total', p->'photos_total', 'photos_missing', p->'photos_missing', 'file', left(coalesce(p->>'file', ''), 200))
    where id = 1;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.backup_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b public.backup_state;
begin
  if not public.is_member() then raise exception 'FORBIDDEN'; end if;
  select * into b from public.backup_state where id = 1;
  return jsonb_build_object('last_run', b.last_run, 'last_ok', b.last_ok, 'info', b.info, 'now', now(),
    'age_hours', case when b.last_ok is null then null else round((extract(epoch from (now() - b.last_ok)) / 3600)::numeric, 1) end);
end $$;

-- ที่เก็บไฟล์ Excel Backup : bucket "backups" (บอตอัปโหลดทุกคืน ผู้ใช้ที่ล็อกอินดาวน์โหลดได้จากหน้า Backup)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('backups', 'backups', false, 52428800, array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/octet-stream'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists backups_read on storage.objects;
create policy backups_read on storage.objects for select to authenticated using (bucket_id = 'backups' and public.is_member());
drop policy if exists backups_insert on storage.objects;
create policy backups_insert on storage.objects for insert to authenticated with check (bucket_id = 'backups' and public.can_edit());
drop policy if exists backups_update on storage.objects;
create policy backups_update on storage.objects for update to authenticated using (bucket_id = 'backups' and public.can_edit()) with check (bucket_id = 'backups' and public.can_edit());
drop policy if exists backups_delete on storage.objects;
create policy backups_delete on storage.objects for delete to authenticated using (bucket_id = 'backups' and public.can_edit());

revoke all on function public.stop_photo_ref(text, int), public.delay_rows(date, date), public.delay_detail(date, date), public.delay_trend(date, date, text),
  public.gps_board(date), public.backup_export(date), public.backup_report(jsonb), public.backup_status() from public, anon, authenticated;
grant execute on function public.delay_detail(date, date), public.delay_trend(date, date, text), public.gps_board(date), public.backup_export(date),
  public.backup_report(jsonb), public.backup_status() to authenticated;

-- ---------- 12. สร้างงานใหม่จากหน้าเว็บ (สิทธิ์ edit / admin) : Task Code = D<ปปปปดดวว>-<ลำดับถัดจากที่มีอยู่ของวันนั้น> ----------
create or replace function public.plan_next_code(p_date date) returns text
language sql stable security definer set search_path = public as $$
  select 'D' || to_char(p_date, 'YYYYMMDD') || '-' || lpad((coalesce(max(substring(task_code from '^D' || to_char(p_date, 'YYYYMMDD') || '-(\d{1,4})$')::int), 0) + 1)::text, 2, '0')
  from public.plan where task_code like 'D' || to_char(p_date, 'YYYYMMDD') || '-%'
$$;

create or replace function public.plan_create(p_date date, p_fields jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_code text; v_who text; v_now timestamptz := now();
begin
  if not public.can_edit() then raise exception 'FORBIDDEN'; end if;
  if p_date is null then raise exception 'กรุณาเลือกวันที่'; end if;
  if p_date < (now() at time zone 'Asia/Bangkok')::date - 60 or p_date > (now() at time zone 'Asia/Bangkok')::date + 366 then raise exception 'วันที่อยู่นอกช่วงที่สร้างงานได้'; end if;
  if public.blank(p_fields->>'stop1') || public.blank(p_fields->>'detail') = '' then raise exception 'กรุณากรอก Detail หรือจุดที่ 1 อย่างน้อยหนึ่งช่อง'; end if;
  perform pg_advisory_xact_lock(hashtext('plan_create:' || p_date::text));   -- กันสองคนกดสร้างพร้อมกันแล้วได้เลขซ้ำ
  v_code := public.plan_next_code(p_date);
  select coalesce(nullif(name, ''), email) into v_who from public.profiles where user_id = auth.uid();
  insert into public.plan (task_code, date, updated_at, updated_by) values (v_code, p_date, v_now, coalesce(v_who, ''));
  perform public.plan_edit(v_code, (coalesce(p_fields, '{}'::jsonb) - 'status'));      -- ตรวจรูปแบบเวลา/ทะเบียนแบบเดียวกับแก้ไข
  delete from public.edit_log where task_code = v_code and time = v_now;
  insert into public.edit_log (time, task_code, source, field, old_value, new_value, by_user)
    values (v_now, v_code, 'Dashboard (สร้างงาน)', 'สร้างงานใหม่', '', to_char(p_date, 'YYYY-MM-DD'), coalesce(v_who, ''));
  return jsonb_build_object('task_code', v_code);
end $$;
revoke all on function public.plan_next_code(date), public.plan_create(date, jsonb) from public, anon, authenticated;
grant execute on function public.plan_next_code(date), public.plan_create(date, jsonb) to authenticated;

-- ---------- เสร็จ ----------
select 'ตั้งค่าเสร็จแล้ว' as result,
       (select count(*) from public.plan) as plan_rows,
       (select count(*) from public.profiles) as users;
