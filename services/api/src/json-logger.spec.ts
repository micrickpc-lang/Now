import { redactForLogs } from "./json-logger";

describe("redactForLogs", () => {
  it("removes credentials, identities, content and coordinates from structured logs", () => {
    const value = redactForLogs({
      email: "person@example.test",
      code: "654321",
      accessToken: "secret-access-token",
      message: "private message",
      location: { latitude: 55.7558, longitude: 37.6173 },
      nested: { phone: "+79991234567" },
    });
    const serialized = JSON.stringify(value);

    expect(serialized).not.toContain("person@example.test");
    expect(serialized).not.toContain("654321");
    expect(serialized).not.toContain("secret-access-token");
    expect(serialized).not.toContain("private message");
    expect(serialized).not.toContain("55.7558");
    expect(serialized).not.toContain("37.6173");
    expect(serialized).not.toContain("+79991234567");
  });

  it("redacts sensitive values embedded in exception text", () => {
    const value = redactForLogs(
      "email=person@example.test latitude=55.7558 Bearer abc.def.ghi",
    );

    expect(value).not.toContain("person@example.test");
    expect(value).not.toContain("55.7558");
    expect(value).not.toContain("abc.def.ghi");
  });
});
