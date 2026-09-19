import { AuthForm } from "@/components/auth-form";

export default function CadastroPage() {
  return (
    <>
      <h1 className="mb-1 text-2xl font-semibold tracking-tight text-stone-900">Criar conta</h1>
      <p className="mb-8 text-stone-500">Seu acesso será liberado após a aprovação da administradora.</p>
      <AuthForm mode="cadastro" />
    </>
  );
}
