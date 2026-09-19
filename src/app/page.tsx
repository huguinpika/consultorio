import { redirect } from "next/navigation";
import { getProfile } from "@/lib/auth";

/** Porta de entrada: direciona cada pessoa para o lugar certo. */
export default async function Home() {
  const profile = await getProfile();
  if (!profile) redirect("/login");
  if (!profile.is_active) redirect("/aguardando-aprovacao");
  redirect(profile.role === "ADMIN" ? "/admin" : "/agenda");
}
