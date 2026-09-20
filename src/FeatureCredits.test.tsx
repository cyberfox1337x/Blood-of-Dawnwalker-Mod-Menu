import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { FeatureCredits } from "./FeatureCredits";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("feature_credits_tests");
afterEach(() => { cleanup(); delete window.dawnwalkerDesktop; });

it("shows supplied attribution and opens only its registered reference IDs", () => {
  const openFeatureReference = vi.fn().mockResolvedValue(undefined);
  window.dawnwalkerDesktop = { openFeatureReference } as unknown as NonNullable<typeof window.dawnwalkerDesktop>;
  render(<FeatureCredits contributors={[{ id: "fixture", displayName: "Verified contributor", avatar: "./credits/fixture.png",
    profileReferenceId: 2000, modReferenceId: 2001, contribution: "Identified the activity journal assets." }]} />);
  expect(screen.getByText("Verified contributor")).toBeVisible();
  expect(screen.getByText("Identified the activity journal assets.")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Nexus profile" }));
  expect(openFeatureReference).toHaveBeenLastCalledWith(2000);
  fireEvent.click(screen.getByRole("button", { name: "Reference mod" }));
  expect(openFeatureReference).toHaveBeenLastCalledWith(2001);
  const avatar = document.querySelector('img[src="./credits/fixture.png"]')!;
  fireEvent.error(avatar);
  expect(document.querySelector('img[src="./credits/fixture.png"]')).toBeNull();
  expect(screen.getByText("Verified contributor")).toBeVisible();
});
