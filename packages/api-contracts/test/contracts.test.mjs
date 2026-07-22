import assert from "node:assert/strict";
import test from "node:test";

import {
  ConversationRole,
  ConversationType,
  MessageDeleteMode,
  MessageType,
  RealtimeEventName,
} from "../dist/index.js";

test("wire enums keep the backend values", () => {
  assert.deepEqual(Object.values(ConversationType), ["DIRECT", "GROUP"]);
  assert.deepEqual(Object.values(ConversationRole), [
    "OWNER",
    "ADMIN",
    "MEMBER",
  ]);
  assert.equal(MessageType.STORY_REPLY, "STORY_REPLY");
  assert.equal(MessageDeleteMode.EVERYONE, "EVERYONE");
});

test("messenger realtime event names are unique and use dotted wire names", () => {
  const names = Object.values(RealtimeEventName);

  assert.equal(new Set(names).size, names.length);
  assert.ok(names.includes("conversation.created"));
  assert.ok(names.includes("message.created"));
  assert.ok(names.includes("message.read"));
  assert.ok(names.includes("typing.started"));
  assert.ok(names.every((name) => name.includes(".")));
});
