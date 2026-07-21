export function differenceInYears(now: Date, date: Date): number {
  let years = now.getUTCFullYear() - date.getUTCFullYear();
  const beforeBirthday =
    now.getUTCMonth() < date.getUTCMonth() ||
    (now.getUTCMonth() === date.getUTCMonth() &&
      now.getUTCDate() < date.getUTCDate());
  if (beforeBirthday) years -= 1;
  return years;
}

export function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60_000);
}
