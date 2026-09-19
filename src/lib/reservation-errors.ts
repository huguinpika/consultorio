/** Traduz erros do banco (PostgREST) em mensagens amigáveis. Os códigos vêm do DETAIL das funções SQL. */
type DbError = { code?: string; details?: string | null; message?: string };

const KNOWN_DETAILS = new Set([
  "ROOM_INACTIVE", "PROFESSIONAL_INACTIVE", "INVALID_START", "INVALID_DURATION", "PAST", "TOO_FAR",
  "DURATION_LIMIT", "CLOSED_DAY", "OUTSIDE_HOURS", "BLOCKED", "TOO_LATE", "RESERVATION_LOCKED",
]);

export function friendlyReservationError(err: DbError): string {
  if (err.code === "23P01") {
    return "Este horário acabou de ser reservado por outra pessoa. Escolha outro horário.";
  }
  if (err.details && KNOWN_DETAILS.has(err.details) && err.message) {
    return err.message; // já vem em português a partir do banco
  }
  if (err.code === "42501") return "Você não tem permissão para esta ação.";
  return "Não foi possível concluir a operação. Tente novamente.";
}
