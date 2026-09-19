import { z } from "zod";
import { addMinutesIso, localToIso } from "@/lib/datetime";

export const loginSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email("Informe um e-mail válido.")),
  password: z.string().min(1, "Informe a senha."),
});

export const signUpSchema = z.object({
  fullName: z.string().trim().min(2, "Informe seu nome completo.").max(120),
  email: z.string().trim().toLowerCase().pipe(z.email("Informe um e-mail válido.")),
  phone: z
    .string()
    .trim()
    .max(30)
    .regex(/^[0-9()+\-\s]*$/, "Telefone inválido.")
    .optional()
    .or(z.literal("")),
  password: z.string().min(10, "A senha deve ter pelo menos 10 caracteres.").max(72),
});

/** Entrada do formulário "Nova reserva". As regras finais (funcionamento, conflito etc.) são do banco. */
export const reservationInputSchema = z
  .object({
    roomId: z.uuid("Sala inválida."),
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Data inválida."),
    startTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Horário inválido."),
    durationMinutes: z.coerce.number().int().min(15).max(720),
    notes: z.string().trim().max(200, "Máximo de 200 caracteres.").optional(),
  })
  .transform((v) => {
    const start_at = localToIso(v.date, v.startTime);
    return {
      room_id: v.roomId,
      start_at,
      end_at: addMinutesIso(start_at, v.durationMinutes),
      notes: v.notes || null,
    };
  });
