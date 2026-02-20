import { describe, it, expect, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { EpicFilter } from "./EpicFilter";
import type { EpicStatus } from "../../types";

const EPICS: EpicStatus[] = [
  { id: "E-1", title: "Payments", total: 3, open: 2, in_progress: 1, blocked: 0, closed: 0 },
  { id: "E-2", title: "Reports", total: 2, open: 0, in_progress: 1, blocked: 0, closed: 1 },
];

describe("EpicFilter", () => {
  it("renders epic options", () => {
    render(
      <EpicFilter
        epics={EPICS}
        selectedEpics={[]}
        showClosed={false}
        onEpicSelect={vi.fn()}
        onShowClosedChange={vi.fn()}
      />,
    );

    expect(screen.getByTestId("epic-option-E-1")).toBeInTheDocument();
    expect(screen.getByTestId("epic-option-E-2")).toBeInTheDocument();
  });

  it("calls onEpicSelect when option is toggled", () => {
    const onEpicSelect = vi.fn();
    render(
      <EpicFilter
        epics={EPICS}
        selectedEpics={[]}
        showClosed={false}
        onEpicSelect={onEpicSelect}
        onShowClosedChange={vi.fn()}
      />,
    );

    fireEvent.click(screen.getByTestId("epic-option-E-1"));
    expect(onEpicSelect).toHaveBeenCalledWith("E-1");
  });

  it("filters options by search", () => {
    render(
      <EpicFilter
        epics={EPICS}
        selectedEpics={[]}
        showClosed={false}
        onEpicSelect={vi.fn()}
        onShowClosedChange={vi.fn()}
      />,
    );

    fireEvent.change(screen.getByTestId("epic-filter-search"), {
      target: { value: "pay" },
    });

    expect(screen.getByTestId("epic-option-E-1")).toBeInTheDocument();
    expect(screen.queryByTestId("epic-option-E-2")).not.toBeInTheDocument();
  });
});
