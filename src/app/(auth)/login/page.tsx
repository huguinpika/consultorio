import { AuthForm } from "@/components/auth-form";

export default function LoginPage() {
  return (
    <>
      <h1 className="mb-1 text-2xl font-semibold tracking-tight text-stone-900">Reserva de salas</h1>
      <p className="mb-8 text-stone-500">Entre para consultar e reservar horários.</p>
      <AuthForm mode="login" />
    </>
  );
}
