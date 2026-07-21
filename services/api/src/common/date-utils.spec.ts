import { differenceInYears } from "./date-utils";

describe("differenceInYears", () => {
  it("does not round up before the birthday", () => {
    expect(
      differenceInYears(
        new Date("2026-07-21T00:00:00Z"),
        new Date("2012-07-22T00:00:00Z"),
      ),
    ).toBe(13);
  });

  it("accepts the exact fourteenth birthday", () => {
    expect(
      differenceInYears(
        new Date("2026-07-21T00:00:00Z"),
        new Date("2012-07-21T00:00:00Z"),
      ),
    ).toBe(14);
  });
});
