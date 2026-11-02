begin;
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
