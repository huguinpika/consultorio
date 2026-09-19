export type UserRole = "ADMIN" | "PROFESSIONAL";
export type ReservationStatus = "confirmed" | "cancelled" | "completed";

export type Profile = {
  id: string;
  email: string;
  full_name: string;
  phone: string | null;
  role: UserRole;
  is_active: boolean;
};

export type Room = { id: string; name: string; is_active: boolean };

export type Reservation = {
  id: string;
  professional_id: string;
  room_id: string;
  start_at: string; // ISO (UTC)
  end_at: string;
  status: ReservationStatus;
  notes: string | null;
  created_at: string;
};
// Dica: depois rode `npx supabase gen types typescript` para gerar tipos completos do banco.
