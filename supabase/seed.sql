begin;
-- Create the three demo users in Supabase Auth before running this seed.
update public.profiles set role='admin' where id=(select id from auth.users where email='admin@pulse-club.example');
update public.profiles set role='operator' where id=(select id from auth.users where email='operator@pulse-club.example');
update public.customers set phone='+79001234567',birth_year=2004,category='student'
 where profile_id=(select id from auth.users where email='client@pulse-club.example');

insert into public.zones(name,kind,description,seat_limit) values
 ('Арена','standard','Сетевые игры и командные встречи. Мониторы 240 Гц.',12),
 ('Лаунж VIP','vip','Тихая зона с мощными видеокартами и мониторами 360 Гц.',6),
 ('Консольная','console','Большой экран, геймпады и уютные диваны.',4);
insert into public.stations(zone_id,name,cpu,gpu,ram_gb,state)
 select (select id from public.zones where name='Арена'),'PC-'||lpad(n::text,2,'0'),'Intel Core i5-14400F','GeForce RTX 4060',32,
 case when n=12 then 'maintenance' else 'ready' end from generate_series(1,12) n;
insert into public.stations(zone_id,name,cpu,gpu,ram_gb,state)
 select (select id from public.zones where name='Лаунж VIP'),'VIP-'||lpad(n::text,2,'0'),'AMD Ryzen 7 7800X3D','GeForce RTX 4080',64,'ready' from generate_series(1,4) n;
insert into public.stations(zone_id,name,cpu,gpu,ram_gb,state) values
 ((select id from public.zones where name='Консольная'),'PS-01','AMD Zen 2','RDNA 2',16,'ready');
insert into public.games(title,genre,age_rating,mode,size_gb) values
 ('Counter-Strike 2','Шутер','18','multi',45),('Dota 2','MOBA','16','multi',60),
 ('Valorant','Шутер','16','multi',48),('Rocket League','Спорт','6','multi',30),
 ('Forza Horizon 5','Гонки','6','both',120),('Minecraft','Песочница','6','both',4),
 ('Cyberpunk 2077','RPG','18','single',86),('EA Sports FC 26','Спорт','0','both',75);
insert into public.station_games(station_id,game_id,version,installed_at)
 select s.id,g.id,'Актуальная',current_date from public.stations s cross join public.games g
 where (s.name like 'PC-%' and g.title in ('Counter-Strike 2','Dota 2','Valorant','Minecraft'))
 or (s.name like 'VIP-%') or (s.name='PS-01' and g.title in ('EA Sports FC 26','Rocket League'));
insert into public.tariffs(zone_id,name,price_per_hour,min_minutes,step_minutes,night_discount_percent) values
 ((select id from public.zones where name='Арена'),'Стандарт · почасовой',150,60,15,20),
 ((select id from public.zones where name='Лаунж VIP'),'VIP · почасовой',300,60,15,15),
 ((select id from public.zones where name='Консольная'),'Консоль · почасовой',250,60,30,10);
insert into public.customers(full_name,email,phone,birth_year,category)
 select name,'player'||n||'@example.com','+7900000'||lpad(n::text,4,'0'),1997+(n%10),
 case when n%3=0 then 'student' when n%3=1 then 'regular' else 'guest' end
 from unnest(array['Алексей Морозов','Мария Лебедева','Никита Орлов','София Белова','Максим Петров','Артём Фролов','Екатерина Зайцева','Даниил Котов','Михаил Павлов','Алина Смирнова','Роман Егоров','Дарья Новикова']) with ordinality as t(name,n);
insert into public.memberships(customer_id,card_number,level,discount_percent,issued_at,valid_until)
 select id,'PC-'||lpad(id::text,6,'0'),case when id%2=0 then 'gold' else 'silver' end,
 case when id%2=0 then 15 else 10 end,current_date-30,current_date+365 from public.customers where id%3=0 or id%5=0;

select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from auth.users where email='operator@pulse-club.example'),'role','authenticated')::text,true);
insert into public.bookings(customer_id,station_id,tariff_id,starts_at,ends_at,status,comment)
 select c.id,s.id,t.id,
 (current_date+1+time '15:00') at time zone 'Europe/Moscow',
 (current_date+1+time '17:00') at time zone 'Europe/Moscow','reserved','Встреча команды'
 from public.stations s join public.tariffs t on t.zone_id=s.zone_id
 join public.customers c on c.id=3+((s.id-1)%10)
 where s.state='ready' and s.name in ('PC-02','PC-04','PC-06','VIP-01');
insert into public.bookings(customer_id,station_id,tariff_id,starts_at,ends_at,status,comment)
 select c.id,s.id,t.id,(current_date-1+time '15:00') at time zone 'Europe/Moscow',
 (current_date-1+time '17:00') at time zone 'Europe/Moscow','reserved','Завершённая игровая встреча'
 from public.customers c cross join public.stations s join public.tariffs t on t.zone_id=s.zone_id
 where c.email='client@pulse-club.example' and s.name='PC-01';
insert into public.sessions(booking_id,started_at,finished_at,operator_id,notes)
 select id,starts_at,ends_at,(select id from auth.users where email='operator@pulse-club.example'),'Сеанс завершён, оборудование проверено' from public.bookings where starts_at<now();
insert into public.payments(booking_id,operator_id,amount,method,state,paid_at)
 select b.id,(select id from auth.users where email='operator@pulse-club.example'),s.charge,'card','received',s.finished_at
 from public.bookings b join public.sessions s on s.booking_id=b.id;
commit;
