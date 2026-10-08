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
    has_dp := exists (select 1 from public.pickup_log l where l.task_code = p.task_code);

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
          insert into public.pickup_log (time, task_code, note, source) values (g.box_time, p.task_code, 'GPS อัตโนมัติ: รถออกจากต้นทาง', 'GPS');
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
    dep := exists (select 1 from public.pickup_log l where l.task_code = p.task_code)
        or exists (select 1 from public.road_log l where l.task_code = p.task_code and l.type in ('road', 'arrive', 'unload'));
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

revoke all on function public.gps_events(text), public.gps_push(jsonb), public.eta_for(date), public.places_set(text, double precision, double precision, int),
  public.places_delete(text), public.places_auto(jsonb), public.gps_need(boolean), public.places_missing(), public.eta_config_set(text, text), public.gps_list(), public.stop_geo(text, text), public.cfgn(text, double precision)
  from public, anon, authenticated;
grant execute on function public.gps_push(jsonb), public.eta_for(date), public.places_set(text, double precision, double precision, int),
  public.places_delete(text), public.places_auto(jsonb), public.gps_need(boolean), public.places_missing(), public.eta_config_set(text, text), public.gps_list() to authenticated;

