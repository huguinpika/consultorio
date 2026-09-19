import { requireActiveUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "@/app/(auth)/actions";
import type { Room } from "@/lib/types";

// Placeholder da Etapa 1: só comprova login + RLS. O calendário real vem na Etapa 2.
export default async function AgendaPage() {
  const profile = await requireActiveUser();
  const supabase = await createClient();
  const { data: rooms } = await supabase.from("rooms").select("id,name,is_active").order("name").returns<Room[]>();

  return (
    <main className="mx-auto max-w-2xl px-5 py-10">
      <h1 className="text-2xl font-semibold tracking-tight">Olá, {profile.full_name.split(" ")[0]}</h1>
      <p className="mt-1 text-stone-500">Salas disponíveis: {rooms?.map((r) => r.name).join(" · ")}</p>
      <form action={signOut} className="mt-8"><button className="text-sm underline">Sair</button></form>
    </main>
  );
}
