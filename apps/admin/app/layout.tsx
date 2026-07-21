import type { Metadata } from "next";
import "./styles.css";

export const metadata: Metadata = {
  title: "Сейчас · Trust & Safety",
  robots: { index: false, follow: false },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ru">
      <body>{children}</body>
    </html>
  );
}
