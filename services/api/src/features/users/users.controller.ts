import { Body, Controller, Delete, Get, Patch } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { CurrentAuth } from "../../common/http";
import { DeleteAccountDto, UpdatePrivacyDto, UpdateUserDto } from "./users.dto";
import { UsersService } from "./users.service";

@ApiTags("users")
@ApiBearerAuth()
@Controller("users")
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get("me")
  me(@CurrentAuth() auth: { userId: string }) {
    return this.users.me(auth.userId);
  }

  @Patch("me")
  update(@CurrentAuth() auth: { userId: string }, @Body() dto: UpdateUserDto) {
    return this.users.update(auth.userId, dto);
  }

  @Patch("me/privacy")
  privacy(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: UpdatePrivacyDto,
  ) {
    return this.users.updatePrivacy(auth.userId, dto);
  }

  @Delete("me")
  remove(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: DeleteAccountDto,
  ) {
    return this.users.deleteAccount(auth.userId, dto.confirmation);
  }
}
