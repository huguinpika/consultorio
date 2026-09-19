"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { loginSchema, signUpSchema } from "@/lib/validation";

export type FormState = { error?: string; message?: string };

export async function signIn(_: FormState, formData: FormData): Promise<FormState> {
  const parsed = loginSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  // Mensagem genérica de propósito: não revela se o e-mail existe.
  if (error) return { error: "E-mail ou senha incorretos." };

  redirect("/");
}

export async function signUp(_: FormState, formData: FormData): Promise<FormState> {
  const parsed = signUpSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const { fullName, email, phone, password } = parsed.data;
  const supabase = await createClient();
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { full_name: fullName, phone: phone || null } },
  });
  if (error) return { error: "Não foi possível criar a conta. Verifique os dados e tente novamente." };

  // Com confirmação de e-mail ativa (recomendado) ainda não há sessão.
  if (!data.session) {
    return { message: "Conta criada! Confirme seu e-mail pelo link que enviamos. Depois, aguarde a aprovação da administradora." };
  }
  redirect("/aguardando-aprovacao");
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}
