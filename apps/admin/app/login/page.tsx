import { login } from "../actions";

export default async function Login({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const error = (await searchParams).error;
  return (
    <main className="login-shell">
      <section className="login-card">
        <div className="brand-mark">С</div>
        <p className="eyebrow">TRUST &amp; SAFETY</p>
        <h1>Панель «Сейчас»</h1>
        <p className="muted">
          Доступ только для уполномоченной команды модерации.
        </p>
        {error && (
          <p className="error" role="alert">
            Неверная почта или пароль.
          </p>
        )}
        <form action={login} className="form-stack">
          <label>
            Рабочая почта
            <input name="email" type="email" autoComplete="username" required />
          </label>
          <label>
            Пароль
            <input
              name="password"
              type="password"
              autoComplete="current-password"
              minLength={12}
              required
            />
          </label>
          <button type="submit">Войти безопасно</button>
        </form>
      </section>
    </main>
  );
}
