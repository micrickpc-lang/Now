import { forwardRef, Module } from "@nestjs/common";
import { AuthModule } from "../features/auth/auth.module";
import { ConversationsModule } from "../features/conversations/conversations.module";
import { RoomsModule } from "../features/rooms/rooms.module";
import { RealtimeGateway } from "./realtime.gateway";

@Module({
  imports: [
    AuthModule,
    forwardRef(() => ConversationsModule),
    forwardRef(() => RoomsModule),
  ],
  providers: [RealtimeGateway],
  exports: [RealtimeGateway],
})
export class RealtimeModule {}
