import { createBrowserClient } from "@supabase/ssr";

/** Cliente para componentes de navegador. Usa apenas a chave pública (anon); a segurança real vem da RLS. */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
