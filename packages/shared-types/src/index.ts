export const reportCategories = [
  "spam",
  "fraud",
  "threats",
  "harassment",
  "doxxing",
  "unsafe_meeting",
  "content",
  "impersonation",
  "other",
] as const;
export type ReportCategory = (typeof reportCategories)[number];

export const safeAnalyticsEvents = [
  "onboarding_started",
  "onboarding_completed",
  "friend_invite_created",
  "friend_invite_accepted",
  "circle_created",
  "signal_created",
  "signal_viewed",
  "join_requested",
  "join_approved",
  "activity_completed",
  "memory_created",
  "day_1_return",
  "day_7_return",
  "day_30_return",
] as const;
