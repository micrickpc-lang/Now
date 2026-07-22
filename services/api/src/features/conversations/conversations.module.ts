import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { ContentPolicyService } from "../../common/content-policy.service";
import { RealtimeModule } from "../../realtime/realtime.module";
import { ConversationsController } from "./conversations.controller";
import { ConversationsService } from "./conversations.service";
import {
  InMemoryTypingStore,
  RedisTypingStore,
  TYPING_STORE,
  TypingStateService,
} from "./typing.store";

@Module({
  imports: [RealtimeModule],
  controllers: [ConversationsController],
  providers: [
    ConversationsService,
    ContentPolicyService,
    RedisTypingStore,
    InMemoryTypingStore,
    TypingStateService,
    {
      provide: TYPING_STORE,
      inject: [ConfigService, RedisTypingStore, InMemoryTypingStore],
      useFactory: (
        config: ConfigService,
        redis: RedisTypingStore,
        memory: InMemoryTypingStore,
      ) => (config.get("NODE_ENV") === "test" ? memory : redis),
    },
  ],
})
export class ConversationsModule {}
