import { IsIn, IsObject } from "class-validator";

export const analyticsEvents = [
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

export class AnalyticsEventDto {
  @IsIn(analyticsEvents)
  name!: string;

  @IsObject()
  properties!: Record<string, string | number | boolean | null>;
}
