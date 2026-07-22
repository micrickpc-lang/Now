import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Max,
  MaxLength,
  Min,
} from "class-validator";

export const CONVERSATION_ROLES = ["OWNER", "ADMIN", "MEMBER"] as const;
export const MESSAGE_TYPES = [
  "TEXT",
  "IMAGE",
  "VIDEO",
  "VOICE",
  "FILE",
  "LOCATION",
  "SYSTEM",
  "SIGNAL",
  "CALL",
  "POLL",
  "STORY_REPLY",
] as const;

export class ConversationPageDto {
  @IsOptional()
  @IsString()
  @MaxLength(512)
  cursor?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 30;
}

export class CreateDirectConversationDto {
  @IsUUID()
  friendId!: string;
}

export class CreateGroupConversationDto {
  @IsString()
  @Length(1, 100)
  title!: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(99)
  @IsUUID("4", { each: true })
  memberIds!: string[];

  @IsOptional()
  @IsUUID()
  avatarMediaId?: string;
}

export class UpdateConversationDto {
  @IsOptional()
  @IsString()
  @Length(1, 100)
  title?: string;

  @IsOptional()
  @IsUUID()
  avatarMediaId?: string;
}

export class AddConversationMemberDto {
  @IsUUID()
  userId!: string;

  @IsOptional()
  @IsIn(CONVERSATION_ROLES)
  role: (typeof CONVERSATION_ROLES)[number] = "MEMBER";
}

export class TransferConversationOwnershipDto {
  @IsUUID()
  targetUserId!: string;
}

export class MuteConversationDto {
  @IsOptional()
  @IsDateString()
  mutedUntil?: string;
}

export class MessagePageDto extends ConversationPageDto {}

export class CreateMessageDto {
  @IsUUID()
  clientMessageId!: string;

  @IsOptional()
  @IsIn(MESSAGE_TYPES)
  type: (typeof MESSAGE_TYPES)[number] = "TEXT";

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  text?: string;

  @IsOptional()
  @IsUUID()
  replyToMessageId?: string;

  @IsOptional()
  @IsUUID()
  forwardedFromMessageId?: string;

  @IsOptional()
  @IsObject()
  metadata?: Record<string, string | number | boolean | null>;
}

export class EditMessageDto {
  @IsString()
  @Length(1, 4000)
  text!: string;
}

export class DeleteMessageDto {
  @IsIn(["SELF", "EVERYONE"])
  mode!: "SELF" | "EVERYONE";
}

export class MessageReactionDto {
  @IsString()
  @Length(1, 32)
  reaction!: string;
}

export class ConversationSearchDto {
  @IsString()
  @Length(1, 100)
  query!: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 30;
}

export class TypingDto {
  @IsBoolean()
  active!: boolean;
}

export class ConversationDraftDto {
  @IsString()
  @MaxLength(4000)
  text!: string;
}
