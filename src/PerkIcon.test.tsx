import { fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { PerkIcon } from "./PerkIcon";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_perk_icon_tests");

describe("perk icons", () => {
  afterEach(() => { window.dawnwalkerDesktop = undefined; });

  it("uses an explicit symbolic fallback for an unknown tree", () => {
    render(<PerkIcon id="Unknown_Record" name="Unknown Record" tree="Unknown" iconStatus="No icon reference resolved for this definition" />);
    expect(screen.getByRole("img", { name: "Unknown Record symbolic Unknown perk icon" })).toHaveTextContent("◇");
  });

  it("reports an original-icon load failure and allows a same-id retry", () => {
    window.dawnwalkerDesktop = {} as NonNullable<typeof window.dawnwalkerDesktop>;
    render(<PerkIcon id="Shared_Vitality" name="Vigour" tree="Shared" iconStatus="Original game icon" />);
    fireEvent.error(screen.getByRole("img", { name: "Vigour perk icon" }));
    const retry = screen.getByRole("button", { name: "Retry Vigour perk icon" });
    expect(retry).toHaveAttribute("title", expect.stringContaining("failed to load"));
    fireEvent.click(retry);
    expect(screen.getByRole("img", { name: "Vigour perk icon" })).toHaveAttribute("src", "dw-asset://icon/Shared_Vitality");
  });
});
