"use server";

import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";

const apiBase = process.env.INTERNAL_API_URL ?? "http://api:3000/api/v1";

async function assertSameOrigin() {
  const requestHeaders = await headers();
  const origin = requestHeaders.get("origin");
  const host = requestHeaders.get("host");
  const configured = process.env.ADMIN_PUBLIC_ORIGIN;
  if (
    !origin ||
    (configured ? origin !== configured : new URL(origin).host !== host)
  ) {
    throw new Error("CSRF validation failed");
  }
}

export async function login(form: FormData) {
  await assertSameOrigin();
  const response = await fetch(`${apiBase}/admin/login`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      email: form.get("email"),
      password: form.get("password"),
    }),
    cache: "no-store",
  });
  if (!response.ok) redirect("/admin/login?error=credentials");
  const body = (await response.json()) as { token: string };
  (await cookies()).set("seychas_admin_session", body.token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "strict",
    maxAge: 1800,
    path: "/admin",
  });
  redirect("/admin");
}

export async function logout() {
  await assertSameOrigin();
  (await cookies()).delete("seychas_admin_session");
  redirect("/admin/login");
}

export async function moderateReport(form: FormData) {
  await assertSameOrigin();
  const token = (await cookies()).get("seychas_admin_session")?.value;
  if (!token) redirect("/admin/login");
  const id = String(form.get("id"));
  const response = await fetch(
    `${apiBase}/admin/reports/${encodeURIComponent(id)}/action`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        action: form.get("action"),
        reason: form.get("reason"),
      }),
      cache: "no-store",
    },
  );
  if (!response.ok) throw new Error("Moderation action failed");
  redirect("/admin");
}
