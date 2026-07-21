import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { CurrentAuth } from "../../common/http";
import {
  AcceptInviteDto,
  AddCircleMemberDto,
  CreateCircleDto,
  UpdateCircleDto,
} from "./social.dto";
import { SocialService } from "./social.service";

@ApiBearerAuth()
@ApiTags("friends")
@Controller()
export class SocialController {
  constructor(private readonly social: SocialService) {}

  @Post("friends/invites")
  createInvite(@CurrentAuth() auth: { userId: string }) {
    return this.social.createInvite(auth.userId);
  }

  @Post("friends/invites/:token/accept")
  acceptInvite(
    @CurrentAuth() auth: { userId: string },
    @Param("token") token: string,
  ) {
    return this.social.acceptInvite(auth.userId, token);
  }

  @Post("friends/invites/accept")
  acceptCode(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: AcceptInviteDto,
  ) {
    return this.social.acceptInvite(auth.userId, dto.token);
  }

  @Get("friends")
  friends(@CurrentAuth() auth: { userId: string }) {
    return this.social.listFriends(auth.userId);
  }

  @Delete("friends/:userId")
  removeFriend(
    @CurrentAuth() auth: { userId: string },
    @Param("userId") userId: string,
  ) {
    return this.social.removeFriend(auth.userId, userId);
  }

  @Post("users/:userId/block")
  block(
    @CurrentAuth() auth: { userId: string },
    @Param("userId") userId: string,
  ) {
    return this.social.block(auth.userId, userId);
  }

  @Delete("users/:userId/block")
  unblock(
    @CurrentAuth() auth: { userId: string },
    @Param("userId") userId: string,
  ) {
    return this.social.unblock(auth.userId, userId);
  }

  @Get("users/me/blocks")
  blocks(@CurrentAuth() auth: { userId: string }) {
    return this.social.listBlocks(auth.userId);
  }

  @Post("circles")
  createCircle(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: CreateCircleDto,
  ) {
    return this.social.createCircle(auth.userId, dto);
  }

  @Get("circles")
  circles(@CurrentAuth() auth: { userId: string }) {
    return this.social.listCircles(auth.userId);
  }

  @Get("circles/:id")
  circle(@CurrentAuth() auth: { userId: string }, @Param("id") id: string) {
    return this.social.getCircle(auth.userId, id);
  }

  @Patch("circles/:id")
  updateCircle(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
    @Body() dto: UpdateCircleDto,
  ) {
    return this.social.updateCircle(auth.userId, id, dto);
  }

  @Delete("circles/:id")
  deleteCircle(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
  ) {
    return this.social.deleteCircle(auth.userId, id);
  }

  @Post("circles/:id/members")
  addMember(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
    @Body() dto: AddCircleMemberDto,
  ) {
    return this.social.addMember(auth.userId, id, dto.userId);
  }

  @Delete("circles/:id/members/:userId")
  removeMember(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
    @Param("userId") userId: string,
  ) {
    return this.social.removeMember(auth.userId, id, userId);
  }
}
