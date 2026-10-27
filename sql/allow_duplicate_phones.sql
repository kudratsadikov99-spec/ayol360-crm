-- Takroriy telefon raqamlarini ham lid sifatida qo'shishga ruxsat berish.
-- Supabase -> SQL Editor ga to'liq nusxalab, "Run" bosing.

-- 1) leads.phone ustidagi UNIQUE cheklov va indekslarni olib tashlash
do $$
declare r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
    where c.conrelid = 'public.leads'::regclass and c.contype = 'u' and a.attname = 'phone'
  loop
    execute format('alter table public.leads drop constraint %I', r.conname);
  end loop;

  for r in
    select i.indexrelid::regclass::text as idx
    from pg_index i
    where i.indrelid = 'public.leads'::regclass and i.indisunique and not i.indisprimary
      and pg_get_indexdef(i.indexrelid) ilike '%phone%'
  loop
    execute format('drop index %s', r.idx);
  end loop;
end $$;

-- qidiruv tez ishlashi uchun oddiy (unique bo'lmagan) indeks
create index if not exists leads_phone_idx on public.leads (phone);

-- 2) Importda faqat noto'g'ri (bo'sh / juda qisqa) raqamlar o'tkazib yuboriladi,
--    takroriylar o'chirilmaydi.
do $$
declare r record;
begin
  for r in select oid::regprocedure as f from pg_proc
           where proname = 'import_leads' and pronamespace = 'public'::regnamespace
  loop
    execute format('drop function %s', r.f);
  end loop;
end $$;

create function public.import_leads(p_office bigint, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me public.profiles;
  v_row jsonb;
  v_phone text;
  v_added int := 0;
  v_skipped int := 0;
begin
  select * into v_me from public.profiles where id = auth.uid() and active;
  if v_me.id is null or v_me.role not in ('admin', 'super') then
    raise exception 'Ruxsat yo''q';
  end if;
  if v_me.role = 'admin' then
    p_office := v_me.office_id;
  end if;

  for v_row in select * from jsonb_array_elements(p_rows) loop
    v_phone := regexp_replace(coalesce(v_row->>'phone', ''), '\D', '', 'g');
    if length(v_phone) = 9 then
      v_phone := '998' || v_phone;
    end if;
    if length(v_phone) < 9 then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    insert into public.leads (office_id, name, phone, source, stage)
    values (p_office, nullif(trim(coalesce(v_row->>'name', '')), ''), v_phone,
            coalesce(nullif(v_row->>'source', ''), 'Import'), 'new');
    v_added := v_added + 1;
  end loop;

  return jsonb_build_object('added', v_added, 'skipped', v_skipped);
end $$;

grant execute on function public.import_leads(bigint, jsonb) to authenticated;
