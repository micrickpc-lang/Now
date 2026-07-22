import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import { CurrentAuth } from "../../common/http";
import {
  AddConversationMemberDto,
  ConversationDraftDto,
  ConversationPageDto,
  ConversationSearchDto,
  CreateDirectConversationDto,
  CreateGroupConversationDto,
  CreateMessageDto,
  DeleteMessageDto,
  EditMessageDto,
  MessagePageDto,
  MessageReactionDto,
  MuteConversationDto,
  TransferConversationOwnershipDto,
  TypingDto,
  UpdateConversationDto,
} from "./conversations.dto";
import { ConversationsService } from "./conversations.service";

@ApiTags("conversations")
@ApiBearerAuth()
@Controller()
export class ConversationsController {
  constructor(private readonly conversations: ConversationsService) {}

  @Get("conversations")
  @ApiOperation({ summary: "List the authenticated user's conversations" })
  list(
    @CurrentAuth() auth: { userId: string },
    @Query() query: ConversationPageDto,
  ) {
    return this.conversations.list(auth.userId, query);
  }

  @Post("conversations/direct")
  @ApiOperation({ summary: "Get or create the unique direct conversation" })
  createDirect(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: CreateDirectConversationDto,
  ) {
    return this.conversations.createDirect(auth.userId, dto.friendId);
  }

  @Post("conversations/group")
  @ApiOperation({ summary: "Create a private group conversation" })
  createGroup(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: CreateGroupConversationDto,
  ) {
    return this.conversations.createGroup(auth.userId, dto);
  }

  @Get("conversations/:id")
  get(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.conversations.get(auth.userId, id);
  }

  @Patch("conversations/:id")
  update(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateConversationDto,
  ) {
    return this.conversations.update(auth.userId, id, dto);
  }

  @Delete("conversations/:id")
  remove(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.conversations.remove(auth.userId, id);
  }

  @Post("conversations/:id/members")
  addMember(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: AddConversationMemberDto,
  ) {
    return this.conversations.addMember(auth.userId, id, dto);
  }

  @Delete("conversations/:id/members/:userId")
  removeMember(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Param("userId", ParseUUIDPipe) userId: string,
  ) {
    return this.conversations.removeMember(auth.userId, id, userId);
  }

  @Post("conversations/:id/leave")
  leave(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.conversations.leave(auth.userId, id);
  }

  @Post("conversations/:id/ownership")
  transferOwnership(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: TransferConversationOwnershipDto,
  ) {
    return this.conversations.transferOwnership(
      auth.userId,
      id,
      dto.targetUserId,
    );
  }

  @Post("conversations/:id/mute")
  mute(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: MuteConversationDto,
  ) {
    return this.conversations.mute(auth.userId, id, dto.mutedUntil);
  }

  @Delete("conversations/:id/mute")
  unmute(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.conversations.unmute(auth.userId, id);
  }

  @Get("conversations/:id/messages")
  messages(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: MessagePageDto,
  ) {
    return this.conversations.messages(auth.userId, id, query);
  }

  @Post("conversations/:id/messages")
  send(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CreateMessageDto,
  ) {
    return this.conversations.createMessage(auth.userId, id, dto);
  }

  @Patch("messages/:id")
  editMessage(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: EditMessageDto,
  ) {
    return this.conversations.editMessage(auth.userId, id, dto.text);
  }

  @Delete("messages/:id")
  deleteMessage(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: DeleteMessageDto,
  ) {
    return this.conversations.deleteMessage(auth.userId, id, dto.mode);
  }

  @Post("messages/:id/reactions")
  addReaction(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: MessageReactionDto,
  ) {
    return this.conversations.addReaction(auth.userId, id, dto.reaction);
  }

  @Delete("messages/:id/reactions/:reaction")
  removeReaction(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Param("reaction") reaction: string,
  ) {
    return this.conversations.removeReaction(auth.userId, id, reaction);
  }

  @Post("messages/:id/read")
  read(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.conversations.markRead(auth.userId, id);
  }

  @Post("messages/:id/pin")
  pin(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.conversations.pin(auth.userId, id);
  }

  @Delete("messages/:id/pin")
  unpin(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.conversations.unpin(auth.userId, id);
  }

  @Get("conversations/:id/search")
  search(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: ConversationSearchDto,
  ) {
    return this.conversations.search(auth.userId, id, query);
  }

  @Post("conversations/:id/typing")
  typing(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: TypingDto,
  ) {
    return this.conversations.typing(auth.userId, id, dto.active);
  }

  @Post("conversations/:id/drafts")
  saveDraft(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ConversationDraftDto,
  ) {
    return this.conversations.saveDraft(auth.userId, id, dto.text);
  }

  @Get("conversations/:id/drafts")
  draft(
    @CurrentAuth() auth: { userId: string },
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.conversations.draft(auth.userId, id);
  }
}
