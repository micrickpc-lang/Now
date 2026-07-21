import {
  ArrayMaxSize,
  IsArray,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  MaxLength,
} from "class-validator";

export class AcceptInviteDto {
  @IsString()
  @Length(6, 256)
  token!: string;
}

export class CreateCircleDto {
  @IsString()
  @Length(1, 60)
  name!: string;

  @IsOptional()
  @IsString()
  @MaxLength(16)
  emoji?: string;

  @IsArray()
  @ArrayMaxSize(50)
  @IsUUID("4", { each: true })
  memberIds!: string[];
}

export class UpdateCircleDto {
  @IsOptional()
  @IsString()
  @Length(1, 60)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(16)
  emoji?: string;
}

export class AddCircleMemberDto {
  @IsUUID()
  userId!: string;
}
