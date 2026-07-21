import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  IsArray,
  IsDateString,
  IsIn,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from "class-validator";

export const signalCategories = [
  "walk",
  "game",
  "talk",
  "movie",
  "study",
  "food",
  "trip",
  "music",
  "company",
  "other",
] as const;

export class CreateSignalDto {
  @IsIn(signalCategories)
  category!: string;

  @IsOptional()
  @IsString()
  @MaxLength(180)
  text?: string;

  @IsOptional()
  @IsString()
  @MaxLength(16)
  emoji?: string;

  @IsDateString()
  startsAt!: string;

  @IsInt()
  @Min(15)
  @Max(360)
  durationMinutes!: number;

  @IsIn(["ONLINE", "OFFLINE"])
  format!: "ONLINE" | "OFFLINE";

  @IsIn(["NONE", "CITY", "DISTRICT", "APPROXIMATE"])
  locationMode!: "NONE" | "CITY" | "DISTRICT" | "APPROXIMATE";

  @IsOptional()
  @IsString()
  @MaxLength(100)
  cityLabel?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  districtLabel?: string;

  @IsOptional()
  @IsLatitude()
  latitude?: number;

  @IsOptional()
  @IsLongitude()
  longitude?: number;

  @Type(() => Number)
  @IsInt()
  @Min(2)
  @Max(20)
  maxParticipants!: number;

  @IsArray()
  @ArrayMaxSize(20)
  @IsUUID("4", { each: true })
  circleIds!: string[];

  @IsArray()
  @ArrayMaxSize(50)
  @IsUUID("4", { each: true })
  userIds!: string[];
}

export class UpdateSignalDto {
  @IsOptional()
  @IsString()
  @MaxLength(180)
  text?: string;

  @IsOptional()
  @IsDateString()
  startsAt?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(2)
  @Max(20)
  maxParticipants?: number;
}

export class SignalIdDto {
  @IsUUID()
  id!: string;
}
