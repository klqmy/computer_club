begin;

drop policy resource_write on public.zones;

create policy write_insert on public.zones for insert to authenticated with check ((select private.current_role())='admin');

create policy write_update on public.zones for update to authenticated using ((select private.current_role())='admin') with check ((select private.current_role())='admin');

create policy write_delete on public.zones for delete to authenticated using ((select private.current_role())='admin');

drop policy resource_write on public.stations;

create policy write_insert on public.stations for insert to authenticated with check ((select private.current_role())='admin');

create policy write_update on public.stations for update to authenticated using ((select private.current_role())='admin') with check ((select private.current_role())='admin');

create policy write_delete on public.stations for delete to authenticated using ((select private.current_role())='admin');

drop policy resource_write on public.games;

create policy write_insert on public.games for insert to authenticated with check ((select private.current_role())='admin');

create policy write_update on public.games for update to authenticated using ((select private.current_role())='admin') with check ((select private.current_role())='admin');

create policy write_delete on public.games for delete to authenticated using ((select private.current_role())='admin');

drop policy resource_write on public.station_games;

create policy write_insert on public.station_games for insert to authenticated with check ((select private.current_role())='admin');

create policy write_update on public.station_games for update to authenticated using ((select private.current_role())='admin') with check ((select private.current_role())='admin');

create policy write_delete on public.station_games for delete to authenticated using ((select private.current_role())='admin');

drop policy resource_write on public.tariffs;

create policy write_insert on public.tariffs for insert to authenticated with check ((select private.current_role())='admin');

create policy write_update on public.tariffs for update to authenticated using ((select private.current_role())='admin') with check ((select private.current_role())='admin');

create policy write_delete on public.tariffs for delete to authenticated using ((select private.current_role())='admin');

drop policy memberships_write on public.memberships;

create policy write_insert on public.memberships for insert to authenticated with check ((select private.current_role())='admin');

create policy write_update on public.memberships for update to authenticated using ((select private.current_role())='admin') with check ((select private.current_role())='admin');

create policy write_delete on public.memberships for delete to authenticated using ((select private.current_role())='admin');

drop policy operations_write on public.sessions;

create policy write_insert on public.sessions for insert to authenticated with check ((select private.current_role())='operator');

create policy write_update on public.sessions for update to authenticated using ((select private.current_role())='operator') with check ((select private.current_role())='operator');

create policy write_delete on public.sessions for delete to authenticated using ((select private.current_role())='operator');

drop policy operations_write on public.payments;

create policy write_insert on public.payments for insert to authenticated with check ((select private.current_role())='operator');

create policy write_update on public.payments for update to authenticated using ((select private.current_role())='operator') with check ((select private.current_role())='operator');

create policy write_delete on public.payments for delete to authenticated using ((select private.current_role())='operator');


create function private.customer_rules() returns trigger language plpgsql set search_path='' as $$
begin
 if new.profile_id is distinct from old.profile_id then raise insufficient_privilege using message='Связь клиента с учётной записью неизменна'; end if;
 return new;
end $$;
revoke all on function private.customer_rules() from public,anon;
create trigger b_customer_rules before update on public.customers for each row execute function private.customer_rules();
alter table public.bookings add column price_per_hour numeric(9,2) not null default 0,
 add column min_minutes int not null default 15,add column step_minutes int not null default 1;
alter table public.bookings disable trigger b_booking_rules;
update public.bookings b set price_per_hour=t.price_per_hour,min_minutes=t.min_minutes,step_minutes=t.step_minutes from public.tariffs t where t.id=b.tariff_id;
alter table public.bookings enable trigger b_booking_rules;


create or replace function public.quote_booking(p_customer_id bigint,p_station_id bigint,p_tariff_id bigint,p_starts_at timestamptz,p_ends_at timestamptz)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare t public.tariffs; s public.stations; minutes int; billable int; discount int:=0; night_discount int:=0;
 a timestamp; b timestamp; night_start timestamp; total numeric; role_name text:=private.current_role();
begin
 if role_name is null or (role_name='client' and p_customer_id is distinct from private.customer_id()) then raise insufficient_privilege using message='Доступ запрещён'; end if;
 if p_starts_at is null or p_ends_at is null or p_ends_at<=p_starts_at or extract(epoch from p_ends_at-p_starts_at)/60 not between 15 and 720 then
  raise sqlstate 'PT422' using message='Недопустимый интервал',detail='{"ends_at":"Продолжительность от 15 минут до 12 часов"}'; end if;
 select * into s from public.stations where id=p_station_id and deleted_at is null;
 select * into t from public.tariffs where id=p_tariff_id and deleted_at is null and active;
 if s.id is null or s.state<>'ready' then raise sqlstate 'PT422' using message='Компьютер недоступен',detail='{"station_id":"Выберите доступный компьютер"}'; end if;
 if t.id is null or t.zone_id<>s.zone_id or not exists(select 1 from public.zones where id=s.zone_id and active and deleted_at is null) then
  raise sqlstate 'PT422' using message='Тариф недоступен',detail='{"tariff_id":"Тариф должен соответствовать активной зоне компьютера"}'; end if;
 if not exists(select 1 from public.customers where id=p_customer_id and deleted_at is null) then
  raise sqlstate 'PT422' using message='Клиент недоступен',detail='{"customer_id":"Выберите действующего клиента"}'; end if;
 minutes:=ceil(extract(epoch from p_ends_at-p_starts_at)/60);
 billable:=ceil(greatest(minutes,t.min_minutes)::numeric/t.step_minutes)*t.step_minutes;
 select m.discount_percent into discount from public.memberships m where m.customer_id=p_customer_id and m.deleted_at is null
  and (p_starts_at at time zone 'Europe/Moscow')::date>=m.issued_at
  and (p_ends_at at time zone 'Europe/Moscow')::date<=m.valid_until;
 discount:=coalesce(discount,0);
 a:=p_starts_at at time zone 'Europe/Moscow'; b:=p_ends_at at time zone 'Europe/Moscow';
 night_start:=date_trunc('day',a)+interval '22 hours';
 if a::time<time '08:00' then night_start:=night_start-interval '1 day'; end if;
 if a>=night_start and b<=night_start+interval '10 hours' then night_discount:=t.night_discount_percent; end if;
 total:=round(t.price_per_hour*billable/60*(100-discount)/100*(100-night_discount)/100,2);
 return jsonb_build_object('billable_minutes',billable,'discount_percent',discount,'night_discount_percent',night_discount,'quoted_total',total,'price_per_hour',t.price_per_hour,'min_minutes',t.min_minutes,'step_minutes',t.step_minutes);
end $$;

create or replace function private.booking_rules() returns trigger language plpgsql set search_path='' as $$
declare q jsonb; recalculate boolean:=tg_op='INSERT'; role_name text:=private.current_role();
begin
 if tg_op='UPDATE' then recalculate:=(new.customer_id,new.station_id,new.tariff_id,new.starts_at,new.ends_at) is distinct from (old.customer_id,old.station_id,old.tariff_id,old.starts_at,old.ends_at); end if;
 if role_name='client' then
  if new.customer_id is distinct from private.customer_id() or new.status not in ('reserved','cancelled') or new.starts_at<=now() then
   raise sqlstate 'PT422' using message='Бронь недоступна для изменения',detail='{"starts_at":"Клиент изменяет только свои будущие бронирования"}'; end if;
  if tg_op='UPDATE' and (old.status not in ('reserved','cancelled') or old.starts_at<=now()) then raise insufficient_privilege using message='Сеанс уже начался'; end if;
 end if;
 if new.status='checked_in' and not exists(select 1 from public.sessions where booking_id=new.id and deleted_at is null and finished_at is null) then
  raise sqlstate 'PT422' using message='Нет активного сеанса',detail='{"status":"Начните сеанс в разделе оператора"}'; end if;
 if new.status='completed' and not exists(select 1 from public.sessions where booking_id=new.id and deleted_at is null and finished_at is not null) then
  raise sqlstate 'PT422' using message='Нет завершённого сеанса',detail='{"status":"Сначала завершите сеанс"}'; end if;
 if recalculate then
  if tg_op='UPDATE' and exists(select 1 from public.sessions where booking_id=old.id and deleted_at is null) then raise sqlstate 'PT409' using message='У бронирования уже есть сеанс'; end if;
  q:=public.quote_booking(new.customer_id,new.station_id,new.tariff_id,new.starts_at,new.ends_at);
  new.quoted_total:=(q->>'quoted_total')::numeric; new.billable_minutes:=(q->>'billable_minutes')::int;
  new.price_per_hour:=(q->>'price_per_hour')::numeric;new.min_minutes:=(q->>'min_minutes')::int;new.step_minutes:=(q->>'step_minutes')::int;
  new.discount_percent:=(q->>'discount_percent')::int; new.night_discount_percent:=(q->>'night_discount_percent')::int;
 else
  new.price_per_hour:=old.price_per_hour;new.min_minutes:=old.min_minutes;new.step_minutes:=old.step_minutes;
  new.quoted_total:=old.quoted_total; new.billable_minutes:=old.billable_minutes;
  new.discount_percent:=old.discount_percent; new.night_discount_percent:=old.night_discount_percent;
 end if;
 return new;
end $$;

create or replace function private.session_rules() returns trigger language plpgsql set search_path='' as $$
declare b public.bookings; t public.tariffs; mins int;
begin
 select * into b from public.bookings where id=new.booking_id and deleted_at is null for update;
 if b.id is null or b.status='cancelled' then raise sqlstate 'PT422' using message='Бронь недоступна',detail='{"booking_id":"Выберите действующее бронирование"}'; end if;
 if tg_op='UPDATE' and new.booking_id<>old.booking_id then raise sqlstate 'PT422' using message='Бронь сеанса неизменна',detail='{"booking_id":"Создайте другой сеанс"}'; end if;
 if new.finished_at is not null and (new.finished_at<=new.started_at or new.finished_at>new.started_at+interval '24 hours') then
  raise sqlstate 'PT422' using message='Неверная длительность',detail='{"finished_at":"Окончание позже начала, длительность до 24 часов"}'; end if;
 if new.started_at>b.ends_at or new.started_at<b.starts_at-interval '15 minutes' then
  raise sqlstate 'PT422' using message='Неверное начало',detail='{"started_at":"Начало в интервале брони, допустимо на 15 минут раньше"}'; end if;
 if exists(select 1 from public.sessions x join public.bookings y on y.id=x.booking_id where y.station_id=b.station_id and x.id<>coalesce(new.id,0)
  and x.finished_at is null and x.deleted_at is null and new.deleted_at is null and new.finished_at is null) then raise sqlstate 'PT409' using message='На компьютере уже идёт другой сеанс'; end if;
 if tg_op='INSERT' then new.operator_id:=auth.uid(); else new.operator_id:=old.operator_id; end if;
 
 new.actual_minutes:=case when new.finished_at is null then 0 else ceil(extract(epoch from new.finished_at-new.started_at)/60) end;
 mins:=ceil(greatest(new.actual_minutes,b.min_minutes)::numeric/b.step_minutes)*b.step_minutes;
 new.charge:=case when new.finished_at is null then 0 else round(b.price_per_hour*mins/60*(100-b.discount_percent)/100*(100-b.night_discount_percent)/100,2) end;
 return new;
end $$;


create function public.club_summary() returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if private.current_role() not in ('admin','operator') or private.current_role() is null then raise insufficient_privilege; end if;
 return jsonb_build_object(
 'stations',(select count(*) from public.stations where deleted_at is null),
 'customers',(select count(*) from public.customers where deleted_at is null),
 'active_sessions',(select count(*) from public.sessions where deleted_at is null and finished_at is null),
 'revenue',(select coalesce(sum(case state when 'received' then amount else -amount end),0) from public.payments where deleted_at is null));
end $$;
revoke all on function public.club_summary() from public,anon;
grant execute on function public.club_summary() to authenticated;
notify pgrst,'reload schema';
commit;
