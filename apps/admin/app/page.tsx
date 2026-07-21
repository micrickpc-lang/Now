import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { logout, moderateReport } from "./actions";

interface Report {
  id: string;
  category: string;
  details?: string;
  state: string;
  reportedUserId?: string;
  signalId?: string;
  messageId?: string;
  createdAt: string;
}

const labels: Record<string, string> = {
  spam: "Спам",
  fraud: "Мошенничество",
  threats: "Угрозы",
  harassment: "Домогательства",
  doxxing: "Личные данные",
  unsafe_meeting: "Опасная встреча",
  content: "Контент",
  impersonation: "Подмена личности",
  other: "Другое",
};

async function loadReports(token: string): Promise<Report[]> {
  const base = process.env.INTERNAL_API_URL ?? "http://api:3000/api/v1";
  const response = await fetch(`${base}/admin/reports`, {
    headers: { authorization: `Bearer ${token}` },
    cache: "no-store",
  });
  if (response.status === 401) redirect("/admin/login");
  if (!response.ok) throw new Error("Could not load reports");
  return response.json() as Promise<Report[]>;
}

export default async function Dashboard() {
  const token = (await cookies()).get("seychas_admin_session")?.value;
  if (!token) redirect("/admin/login");
  const reports = await loadReports(token);
  return (
    <main className="dashboard">
      <header>
        <div>
          <p className="eyebrow">СЕЙЧАС · TRUST &amp; SAFETY</p>
          <h1>Очередь расследований</h1>
        </div>
        <form action={logout}>
          <button className="ghost">Выйти</button>
        </form>
      </header>
      <section className="metrics" aria-label="Сводка">
        <article>
          <span>Открыто</span>
          <strong>{reports.filter((r) => r.state === "OPEN").length}</strong>
        </article>
        <article>
          <span>В работе</span>
          <strong>
            {reports.filter((r) => r.state === "INVESTIGATING").length}
          </strong>
        </article>
        <article>
          <span>Апелляции</span>
          <strong>
            {reports.filter((r) => r.state === "APPEALED").length}
          </strong>
        </article>
      </section>
      <section className="queue">
        {reports.length === 0 && (
          <div className="empty">
            <span>✓</span>
            <h2>Очередь пуста</h2>
            <p>Новых жалоб сейчас нет.</p>
          </div>
        )}
        {reports.map((report) => (
          <article className="report" key={report.id}>
            <div className="report-head">
              <span className={`severity severity-${report.category}`}>
                {labels[report.category] ?? report.category}
              </span>
              <time>
                {new Intl.DateTimeFormat("ru-RU", {
                  dateStyle: "medium",
                  timeStyle: "short",
                }).format(new Date(report.createdAt))}
              </time>
            </div>
            <p>{report.details || "Комментарий не добавлен."}</p>
            <dl>
              <div>
                <dt>Статус</dt>
                <dd>{report.state}</dd>
              </div>
              <div>
                <dt>Объект</dt>
                <dd>
                  {report.reportedUserId
                    ? "Пользователь"
                    : report.signalId
                      ? "Сигнал"
                      : "Сообщение"}
                </dd>
              </div>
              <div>
                <dt>ID</dt>
                <dd className="mono">
                  {report.reportedUserId ?? report.signalId ?? report.messageId}
                </dd>
              </div>
            </dl>
            <form action={moderateReport} className="moderation-form">
              <input type="hidden" name="id" value={report.id} />
              <select
                name="action"
                aria-label="Решение"
                defaultValue="investigate"
              >
                <option value="investigate">Взять в работу</option>
                <option value="warn">Предупредить</option>
                <option value="suspend">Заблокировать</option>
                <option value="dismiss">Отклонить</option>
                <option value="restore">Восстановить</option>
              </select>
              <input
                name="reason"
                minLength={5}
                maxLength={500}
                placeholder="Обоснование решения"
                required
              />
              <button type="submit">Применить</button>
            </form>
          </article>
        ))}
      </section>
    </main>
  );
}
