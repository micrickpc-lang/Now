import { IsIn, IsString, IsUUID, Length } from "class-validator";

export class CreateMemoryDto {
  @IsUUID()
  roomId!: string;

  @IsString()
  @Length(1, 80)
  title!: string;

  @IsIn(["aurora", "sunset", "midnight", "mint"])
  theme!: string;
}
