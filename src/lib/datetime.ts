/** O consultório opera em America/Sao_Paulo (UTC-3, sem horário de verão desde 2019). */
export const TZ = "America/Sao_Paulo";
const OFFSET = "-03:00";

/** Converte data (YYYY-MM-DD) + hora (HH:mm) locais em ISO UTC. */
export function localToIso(date: string, time: string): string {
  return new Date(`${date}T${time}:00${OFFSET}`).toISOString();
}

export function addMinutesIso(iso: string, minutes: number): string {
  return new Date(new Date(iso).getTime() + minutes * 60_000).toISOString();
}

export function formatLocal(iso: string, opts: Intl.DateTimeFormatOptions): string {
  return new Intl.DateTimeFormat("pt-BR", { timeZone: TZ, ...opts }).format(new Date(iso));
}
