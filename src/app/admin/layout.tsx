import { requireAdmin } from "@/lib/auth";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  await requireAdmin(); // profissionais são redirecionados para /agenda
  return <>{children}</>;
}
