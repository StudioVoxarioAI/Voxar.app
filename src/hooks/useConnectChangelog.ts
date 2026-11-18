import { useQuery } from "@tanstack/react-query";
import type { ChangelogEntry, ChangelogType } from "@/data/changelog";

/**
 * Changelog platformy StudioVoxario Connect – živě z GitHub Releases (veřejné API, CORS).
 * Každé vydání Connectu nese strukturované poznámky v komentáři `<!-- connect-changelog {...} -->`
 * (generuje je workflow vydání z CHANGELOG.json v repozitáři Connect), takže se nová verze objeví na webu
 * hned po vydání – bez nasazení webu. Vydání bez poznámek (např. nevydařené) se nezobrazí.
 */
const RELEASES_API = "https://api.github.com/repos/StudioVoxarioAI/StudioVoxario-Connect/releases?per_page=30";
const TYPES: ChangelogType[] = ["feature", "fix", "improvement", "security"];

type Release = { tag_name: string; published_at: string | null; draft: boolean; body: string | null };

export function parseConnectRelease(r: Release): ChangelogEntry | null {
  if (r.draft || !r.body) return null;
  const m = /<!--\s*connect-changelog\s+([\s\S]*?)\s*-->/.exec(r.body);
  if (!m) return null;
  try {
    const e = JSON.parse(m[1]) as Partial<ChangelogEntry>;
    const changes = (e.changes ?? []).filter((c) => c && TYPES.includes(c.type) && typeof c.text === "string");
    if (!e.version || !changes.length) return null;
    return {
      version: String(e.version),
      date: e.date ?? (r.published_at ?? "").slice(0, 10),
      title: e.title ?? `StudioVoxario Connect ${e.version}`,
      titleEn: e.titleEn,
      changes,
    };
  } catch {
    return null;
  }
}

export function useConnectChangelog() {
  return useQuery({
    queryKey: ["connect-changelog"],
    staleTime: 10 * 60_000,
    retry: 1,
    queryFn: async (): Promise<ChangelogEntry[]> => {
      const res = await fetch(RELEASES_API, { headers: { accept: "application/vnd.github+json" } });
      if (!res.ok) throw new Error(`GitHub ${res.status}`);
      const list = (await res.json()) as Release[];
      return list.map(parseConnectRelease).filter((x): x is ChangelogEntry => !!x);
    },
  });
}
