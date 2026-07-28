import type { ConfigService } from "@nestjs/config";
import {
  FakeSmsProvider,
  HttpSmsProvider,
  LocalTestSmsProvider,
} from "./otp.provider";

function config(values: Record<string, string>) {
  return {
    get: jest.fn((key: string) => values[key]),
    getOrThrow: jest.fn((key: string) => {
      const value = values[key];
      if (value === undefined) throw new Error(`Missing ${key}`);
      return value;
    }),
  } as unknown as ConfigService;
}

describe("HTTP SMS provider", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("submits the generic JSON contract without placing credentials in the URL", async () => {
    const fetchMock = jest.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      json: () =>
        Promise.resolve({ success: true, messageId: "provider-message-1" }),
    } as Response);
    const provider = new HttpSmsProvider(
      config({
        SMS_API_BASE_URL: "https://sms.example.invalid/v1/messages",
        SMS_API_KEY: "unit-test-provider-credential",
        SMS_SENDER: "Seichas",
        SMS_TEMPLATE: "Your code is {code}",
        SMS_TIMEOUT_MS: "1000",
      }),
    );

    await provider.sendOtp({
      phoneE164: "+15555550123",
      code: "654321",
      requestId: "otp-request-1",
    });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, options] = fetchMock.mock.calls[0] ?? [];
    expect(url).toBe("https://sms.example.invalid/v1/messages");
    expect(options?.method).toBe("POST");
    expect(options?.headers).toMatchObject({
      authorization: "Bearer unit-test-provider-credential",
      "content-type": "application/json",
      "idempotency-key": "otp-request-1",
    });
    const body = typeof options?.body === "string" ? options.body : "";
    expect(JSON.parse(body) as unknown).toEqual({
      to: "+15555550123",
      from: "Seichas",
      message: "Your code is 654321",
      requestId: "otp-request-1",
    });
  });

  it("fails closed when the provider reports a delivery error", async () => {
    jest.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ success: false, error: "blocked" }),
    } as Response);
    const provider = new HttpSmsProvider(
      config({
        SMS_API_BASE_URL: "https://sms.example.invalid/v1/messages",
        SMS_API_KEY: "unit-test-provider-credential",
        SMS_SENDER: "Seichas",
        SMS_TEMPLATE: "Your code is {code}",
      }),
    );

    await expect(
      provider.sendOtp({
        phoneE164: "+15555550123",
        code: "654321",
        requestId: "otp-request-2",
      }),
    ).rejects.toThrow("SMS provider rejected");
  });
});

describe("LocalTestSmsProvider", () => {
  it("only allows the explicit development configuration", async () => {
    const provider = new LocalTestSmsProvider(
      config({
        NODE_ENV: "development",
        APP_ENV: "development",
        AUTH_MODE: "local_test",
        ALLOW_LOCAL_TEST_OTP: "true",
      }),
    );
    await expect(
      provider.sendOtp({
        phoneE164: "+447911123456",
        code: "123456",
        requestId: "otp-request-3",
      }),
    ).resolves.toBeUndefined();
  });

  it("rejects production even when the local flags are present", async () => {
    const provider = new LocalTestSmsProvider(
      config({
        NODE_ENV: "production",
        APP_ENV: "development",
        AUTH_MODE: "local_test",
        ALLOW_LOCAL_TEST_OTP: "true",
      }),
    );
    await expect(
      provider.sendOtp({
        phoneE164: "+447911123456",
        code: "123456",
        requestId: "otp-request-4",
      }),
    ).rejects.toThrow("Local test SMS provider is disabled");
  });
});

describe("FakeSmsProvider", () => {
  it("is an in-memory provider intended for automated tests", async () => {
    const provider = new FakeSmsProvider();
    await provider.sendOtp({
      phoneE164: "+12025550123",
      code: "123456",
      requestId: "test-request",
    });
    expect(provider.sent).toEqual([
      {
        phoneE164: "+12025550123",
        code: "123456",
        requestId: "test-request",
      },
    ]);
  });
});
