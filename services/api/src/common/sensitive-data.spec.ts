import { redactSensitive } from "./sensitive-data";

describe("redactSensitive", () => {
  it("deeply removes credentials, private content and exact location", () => {
    const input = {
      request: {
        authorization: "Bearer header.payload.signature",
        phone: "+79990000000",
        nested: {
          latitude: 55.7,
          longitude: 37.6,
          accuracyMeters: 4.2,
          body: "private message",
          refreshToken: "refresh-secret",
        },
      },
      url: "/api/v1/maps/reverse?lat=55.7&lon=37.6&q=full%20address",
      safe: { errorCode: "LOCATION_PERMISSION_REQUIRED", statusCode: 400 },
    };

    const redacted = redactSensitive(input);
    const serialized = JSON.stringify(redacted);
    expect(serialized).not.toContain("55.7");
    expect(serialized).not.toContain("37.6");
    expect(serialized).not.toContain("79990000000");
    expect(serialized).not.toContain("refresh-secret");
    expect(serialized).not.toContain("private message");
    expect(serialized).not.toContain("full%20address");
    expect(serialized).toContain("LOCATION_PERMISSION_REQUIRED");
    expect(serialized).toContain("[REDACTED]");
  });

  it("handles cycles and errors without exposing embedded secrets", () => {
    const cyclic: Record<string, unknown> = {
      error: new Error("Bearer top.secret.value for +79990000000"),
    };
    cyclic.self = cyclic;

    const serialized = JSON.stringify(redactSensitive(cyclic));
    expect(serialized).toContain("[CIRCULAR]");
    expect(serialized).toContain("Bearer [REDACTED]");
    expect(serialized).toContain("[PHONE_REDACTED]");
  });
});
