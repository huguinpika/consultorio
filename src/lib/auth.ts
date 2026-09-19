import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Profile } from "@/lib/types";

/** Perfil do usuário logado (ou null). Cacheado por requisição. */
export const getProfile = cache(async (): Promise<Profile | null> => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data } = await supabase
    .from("profiles")
    .select("id,email,full_name,phone,role,is_active")
    .eq("id", user.id)
    .single<Profile>();
  return data ?? null;
});

/** Exige usuário logado E aprovado (ativo). */
export async function requireActiveUser(): Promise<Profile> {
  const profile = await getProfile();
  if (!profile) redirect("/login");
  if (!profile.is_active) redirect("/aguardando-aprovacao");
  return profile;
}

/** Exige administradora. Profissionais são redirecionados para a agenda. */
export async function requireAdmin(): Promise<Profile> {
  const profile = await requireActiveUser();
  if (profile.role !== "ADMIN") redirect("/agenda");
  return profile;
}
