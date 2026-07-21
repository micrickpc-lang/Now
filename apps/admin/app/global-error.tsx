"use client";

export default function GlobalError({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html lang="ru">
      <body>
        <main>
          <h1>Произошла ошибка</h1>
          <button type="button" onClick={() => reset()}>
            Попробовать снова
          </button>
        </main>
      </body>
    </html>
  );
}
