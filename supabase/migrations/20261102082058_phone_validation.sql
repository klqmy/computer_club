begin;
create or replace function private.field_rules(table_name text) returns jsonb language sql immutable set search_path='' as $$
select case table_name
when 'profiles' then '{"full_name":{"required":true,"length":100},"role":{"enum":["admin","operator","client"]}}'
when 'customers' then '{"full_name":{"required":true,"length":100},"email":{"required":true,"length":120,"pattern":"^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$"},"phone":{"required":true,"min_digits":10,"max_digits":15,"pattern":"^[+]?[0-9 ()-]{10,20}$"},"birth_year":{"required":true,"min":1920,"max":2026},"category":{"enum":["regular","student","guest"]}}'
when 'zones' then '{"name":{"required":true,"length":60},"kind":{"enum":["standard","vip","console"]},"description":{"length":400},"seat_limit":{"required":true,"min":1,"max":100},"active":{"required":true}}'
when 'stations' then '{"name":{"required":true,"length":40},"zone_id":{"required":true,"ref":"zones"},"cpu":{"required":true,"length":100},"gpu":{"required":true,"length":100},"ram_gb":{"required":true,"min":4,"max":256},"state":{"enum":["ready","maintenance","offline"]},"notes":{"length":400}}'
when 'games' then '{"title":{"required":true,"length":100},"genre":{"required":true,"length":50},"age_rating":{"enum":["0","6","12","16","18"]},"mode":{"enum":["single","multi","both"]},"size_gb":{"required":true,"min":0.1,"max":1000}}'
when 'station_games' then '{"station_id":{"required":true,"ref":"stations"},"game_id":{"required":true,"ref":"games"},"version":{"required":true,"length":30},"installed_at":{"required":true},"enabled":{"required":true}}'
when 'tariffs' then '{"name":{"required":true,"length":60},"zone_id":{"required":true,"ref":"zones"},"price_per_hour":{"required":true,"min":1,"max":10000},"min_minutes":{"required":true,"min":15,"max":720},"step_minutes":{"required":true,"min":1,"max":60},"night_discount_percent":{"required":true,"min":0,"max":50},"active":{"required":true}}'
when 'memberships' then '{"customer_id":{"required":true,"ref":"customers"},"card_number":{"required":true,"pattern":"^PC-[0-9]{6}$"},"level":{"enum":["base","silver","gold"]},"discount_percent":{"required":true,"min":0,"max":30},"issued_at":{"required":true},"valid_until":{"required":true}}'
when 'bookings' then '{"customer_id":{"required":true,"ref":"customers"},"station_id":{"required":true,"ref":"stations"},"tariff_id":{"required":true,"ref":"tariffs"},"starts_at":{"required":true},"ends_at":{"required":true},"status":{"enum":["reserved","checked_in","completed","cancelled"]},"comment":{"length":400}}'
when 'sessions' then '{"booking_id":{"required":true,"ref":"bookings"},"started_at":{"required":true},"notes":{"length":400}}'
when 'payments' then '{"booking_id":{"required":true,"ref":"bookings"},"amount":{"required":true,"min":0.01,"max":100000},"method":{"enum":["cash","card"]},"state":{"enum":["received","refunded"]},"paid_at":{"required":true}}'
else '{}' end::jsonb
$$;
create or replace function private.validate_row() returns trigger language plpgsql set search_path='' as $$
declare r jsonb:=to_jsonb(new); errors jsonb:='{}'; f text; rule jsonb; v text; exists_ref boolean;
begin

 if current_user='authenticated' then
  if private.current_role() is null then raise insufficient_privilege; end if;
  if tg_table_name in ('profiles','zones','stations','games','station_games','tariffs','memberships') and private.current_role()<>'admin' then raise insufficient_privilege; end if;
  if tg_table_name in ('customers','sessions','payments') and private.current_role()<>'operator' then raise insufficient_privilege; end if;
  if tg_table_name='bookings' and private.current_role() not in ('operator','client') then raise insufficient_privilege; end if;
 end if;
 for f,rule in select * from jsonb_each(private.field_rules(tg_table_name)) loop
  v:=r->>f;
  if (rule->>'required')::boolean and (v is null or btrim(v)='') then
   errors:=errors||jsonb_build_object(f,'Заполните поле');
  elsif v is not null and btrim(v)<>'' then
   if rule ? 'length' and char_length(v)>(rule->>'length')::int then errors:=errors||jsonb_build_object(f,'Слишком длинное значение'); end if;
   if rule ? 'pattern' and v !~ (rule->>'pattern') then errors:=errors||jsonb_build_object(f,'Неверный формат'); end if;
   if rule ? 'min_digits' and (char_length(regexp_replace(v,'[^0-9]','','g'))<(rule->>'min_digits')::int or char_length(regexp_replace(v,'[^0-9]','','g'))>(rule->>'max_digits')::int) then errors:=errors||jsonb_build_object(f,'Телефон должен содержать 10–15 цифр'); end if;
   if rule ? 'min' and v::numeric<(rule->>'min')::numeric then errors:=errors||jsonb_build_object(f,'Значение меньше допустимого'); end if;
   if rule ? 'max' and v::numeric>(rule->>'max')::numeric then errors:=errors||jsonb_build_object(f,'Значение больше допустимого'); end if;
   if rule ? 'ref' then
    execute format('select exists(select 1 from public.%I where id=$1 and deleted_at is null)',rule->>'ref') into exists_ref using v::bigint;
    if not exists_ref then errors:=errors||jsonb_build_object(f,'Связанная запись недоступна или удалена'); end if;
   end if;
  end if;
  if rule ? 'enum' and (v is null or not (rule->'enum' ? v)) then errors:=errors||jsonb_build_object(f,'Выберите допустимое значение'); end if;
 end loop;
 if tg_table_name='memberships' then
  if new.valid_until<new.issued_at then errors:=errors||'{"valid_until":"Дата окончания раньше даты выдачи"}'; end if;
 end if;
 if errors<>'{}'::jsonb then raise sqlstate 'PT422' using message='Проверьте поля формы', detail=errors::text; end if;
 new.updated_at:=now();
 return new;
end $$;
notify pgrst,'reload schema';
commit;
