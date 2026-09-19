export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <main className="flex min-h-dvh items-center justify-center bg-stone-50 px-5 py-10">
      <div className="w-full max-w-sm">{children}</div>
    </main>
  );
}
