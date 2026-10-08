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

