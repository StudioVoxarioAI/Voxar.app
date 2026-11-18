-- StudioVoxario Connect / obchod: soubor softwaru smí stáhnout i držitel licence (shop_licenses), ne jen předplatitel.
-- Dosavadní politika shop_files_buyer_read kontrolovala jen shop_entitlements, takže kupující trvalé licence
-- (Voxario Studio Engine) dostal při stahování chybu. Pravidlo je teď stejné jako shop_can_download().
drop policy if exists shop_files_buyer_read on storage.objects;
create policy shop_files_buyer_read on storage.objects for select to authenticated
  using (
    bucket_id = 'shop-files' and exists (
      select 1 from public.shop_items i
      where storage.objects.name = any (i.file_parts) and public.shop_can_download(i.id)
    )
  );
