"use client";

import Link from "next/link";
import { useActionState } from "react";
import { signIn, signUp, type FormState } from "@/app/(auth)/actions";

const input =
  "w-full rounded-xl border border-stone-200 bg-white px-4 py-3 text-base outline-none transition focus:border-stone-400 focus:ring-4 focus:ring-stone-100";

export function AuthForm({ mode }: { mode: "login" | "cadastro" }) {
  const [state, action, pending] = useActionState<FormState, FormData>(
    mode === "login" ? signIn : signUp,
    {},
  );
  const isLogin = mode === "login";

  return (
    <form action={action} className="space-y-4">
      {!isLogin && (
        <>
          <input name="fullName" placeholder="Nome completo" autoComplete="name" required className={input} />
          <input name="phone" placeholder="Telefone (opcional)" autoComplete="tel" inputMode="tel" className={input} />
        </>
      )}
      <input name="email" type="email" placeholder="E-mail" autoComplete="email" required className={input} />
      <input
        name="password"
        type="password"
        placeholder={isLogin ? "Senha" : "Senha (mínimo 10 caracteres)"}
        autoComplete={isLogin ? "current-password" : "new-password"}
        required
        className={input}
      />

      {state.error && <p role="alert" className="text-sm text-red-700">{state.error}</p>}
      {state.message && <p role="status" className="text-sm text-emerald-800">{state.message}</p>}

      <button
        disabled={pending}
        className="w-full rounded-xl bg-stone-900 py-3 text-base font-medium text-white transition hover:bg-stone-800 disabled:opacity-60"
      >
        {pending ? "Aguarde…" : isLogin ? "Entrar" : "Criar conta"}
      </button>

      <p className="text-center text-sm text-stone-500">
        {isLogin ? (
          <>Ainda não tem conta? <Link href="/cadastro" className="text-stone-900 underline">Cadastre-se</Link></>
        ) : (
          <>Já tem conta? <Link href="/login" className="text-stone-900 underline">Entrar</Link></>
        )}
      </p>
    </form>
  );
}
