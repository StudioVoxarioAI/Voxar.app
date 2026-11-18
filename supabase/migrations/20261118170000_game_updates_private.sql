-- Soukromé úložiště her: buildy Ashes of Eryon a Fantasy (bucket game-updates, složka unity/) smí stáhnout jen
-- přihlášený uživatel s přístupem ke konkrétní hře (game_can_play – správce, editor, nebo udělený přístup).
-- StudioVoxario Connect (od 0.5.0) stahuje přes /storage/v1/object/authenticated/… s tokenem uživatele.
--
--   unity/fantasy/…, unity/latest-fantasy.json  → Fantasy
--   ostatní unity/… (latest.json, latest-beta.json, <verze>/…)  → Ashes of Eryon
--   launcher/…  → dál čitelné všem (aktualizace starého launcheru; přes autorizovaný endpoint s anon klíčem)
--
-- Nahrávání z CI (klíč služby) RLS neomezuje. Starý launcher Ashes stahuje hry přes /object/public/ – po této změně
-- už hry nestáhne; hráči přecházejí na StudioVoxario Connect (převezme jejich instalace bez stahování).

update storage.buckets set public = false where id = 'game-updates';

drop policy if exists game_updates_launcher_read on storage.objects;
create policy game_updates_launcher_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'game-updates' and name like 'launcher/%');

drop policy if exists game_updates_fantasy_read on storage.objects;
create policy game_updates_fantasy_read on storage.objects for select to authenticated
  using (
    bucket_id = 'game-updates'
    and (name like 'unity/fantasy/%' or name = 'unity/latest-fantasy.json')
    and public.game_can_play('fantasy')
  );

drop policy if exists game_updates_ashes_read on storage.objects;
create policy game_updates_ashes_read on storage.objects for select to authenticated
  using (
    bucket_id = 'game-updates'
    and name like 'unity/%'
    and name not like 'unity/fantasy/%'
    and name <> 'unity/latest-fantasy.json'
    and public.game_can_play('ashes-of-eryon')
  );
