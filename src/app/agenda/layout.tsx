import { requireActiveUser } from "@/lib/auth";

export default async function AgendaLayout({ children }: { children: React.ReactNode }) {
  await requireActiveUser(); // 2ª camada de proteção (servidor); a 3ª é a RLS do banco
  return <>{children}</>;
}
