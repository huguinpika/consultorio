import { redirect } from "next/navigation";
import { getProfile } from "@/lib/auth";
import { signOut } from "@/app/(auth)/actions";

export default async function PendingPage() {
  const profile = await getProfile();
  if (!profile) redirect("/login");
  if (profile.is_active) redirect("/");

  return (
    <main className="flex min-h-dvh items-center justify-center bg-stone-50 px-5">
      <div className="w-full max-w-sm text-center">
        <h1 className="mb-2 text-2xl font-semibold tracking-tight text-stone-900">Cadastro em análise</h1>
        <p className="mb-8 text-stone-500">
          Olá, {profile.full_name.split(" ")[0]}. Assim que a administradora aprovar seu acesso, você poderá reservar salas.
        </p>
        <form action={signOut}>
          <button className="text-sm text-stone-600 underline">Sair</button>
        </form>
      </div>
    </main>
  );
}
