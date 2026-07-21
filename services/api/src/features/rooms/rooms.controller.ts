import { Body, Controller, Delete, Get, Param, Post } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { CurrentAuth } from "../../common/http";
import {
  CreateMessageDto,
  CreatePollDto,
  ReactionDto,
  ShareLocationDto,
  VoteDto,
} from "./rooms.dto";
import { RoomsService } from "./rooms.service";

@ApiTags("rooms")
@ApiBearerAuth()
@Controller("rooms")
export class RoomsController {
  constructor(private readonly rooms: RoomsService) {}

  @Get(":id")
  get(@CurrentAuth() auth: { userId: string }, @Param("id") id: string) {
    return this.rooms.get(auth.userId, id);
  }

  @Get(":id/messages")
  messages(@CurrentAuth() auth: { userId: string }, @Param("id") id: string) {
    return this.rooms.messages(auth.userId, id);
  }

  @Post(":id/messages")
  send(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
    @Body() dto: CreateMessageDto,
  ) {
    return this.rooms.createMessage(auth.userId, id, dto.body);
  }

  @Post(":id/leave")
  leave(@CurrentAuth() auth: { userId: string }, @Param("id") id: string) {
    return this.rooms.leave(auth.userId, id);
  }

  @Post(":id/messages/:messageId/reactions")
  react(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
    @Param("messageId") messageId: string,
    @Body() dto: ReactionDto,
  ) {
    return this.rooms.toggleReaction(auth.userId, id, messageId, dto.emoji);
  }

  @Post(":id/polls")
  poll(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
    @Body() dto: CreatePollDto,
  ) {
    return this.rooms.createPoll(auth.userId, id, dto);
  }

  @Post(":id/polls/:pollId/vote")
  vote(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
    @Param("pollId") pollId: string,
    @Body() dto: VoteDto,
  ) {
    return this.rooms.vote(auth.userId, id, pollId, dto.optionId);
  }

  @Post(":id/location-share")
  share(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
    @Body() dto: ShareLocationDto,
  ) {
    return this.rooms.shareLocation(auth.userId, id, dto);
  }

  @Delete(":id/location-share")
  revoke(@CurrentAuth() auth: { userId: string }, @Param("id") id: string) {
    return this.rooms.revokeLocation(auth.userId, id);
  }
}
