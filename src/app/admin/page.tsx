import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "@/app/(auth)/actions";

// Placeholder da Etapa 1: só comprova a proteção por função. O dashboard vem na Etapa 3.
export default async function AdminPage() {
  const profile = await requireAdmin();
  const supabase = await createClient();
  const { count } = await supabase.from("profiles").select("id", { count: "exact", head: true }).eq("is_active", false);

  return (
    <main className="mx-auto max-w-2xl px-5 py-10">
      <h1 className="text-2xl font-semibold tracking-tight">Painel · {profile.full_name.split(" ")[0]}</h1>
      <p className="mt-1 text-stone-500">Cadastros aguardando aprovação: {count ?? 0}</p>
      <form action={signOut} className="mt-8"><button className="text-sm underline">Sair</button></form>
    </main>
  );
}
