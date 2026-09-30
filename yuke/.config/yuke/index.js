import { plugins } from "yuke";
import { composerVim, transcriptVim, agents, mcp } from "yuke:plugins";
import "./tools/web.js";
import { herdr } from "./plugins/herdr.js";

plugins.use(composerVim);
plugins.use(transcriptVim);
plugins.use(mcp());
plugins.use(herdr());

// One general child with every tool, on Codex Luna whatever the parent runs.
plugins.use(agents({
  catalog: {
    general: { description: "A capable general agent. Give it one self-contained task.", model: "openai-codex/gpt-5.6-luna" },
  },
}));

const MANTIS_DARK = /** @type {const} */ ({
  palette: {
    fg: "reset",
    bg: "reset",
    surfaceFg: "#E6EDF3",
    strongFg: "#F6F8FA",
    green: "#A8CFA0",
    greenMuted: "#355C4A",
    gray: "#343A46",
    yellow: "#E3B341",
    red: "#FF7B72",
    pendingBg: "#3B3520",
    errorBg: "#4A2323",
    diffAddBg: "#20372A",
    diffDelBg: "#3A2426",
  },
  groups: {
    YukeBrand: { fg: "green", bold: true },
    UIPrompt: { fg: "green", bold: true },
    UIComposer: { fg: "fg", bg: "bg" },
    UIComposerPrompt: { fg: "green", bold: true },
    UIComposerPromptInactive: { fg: "green", dim: true },
    UIItemSel: { fg: "surfaceFg", bg: "greenMuted", reverse: false },
    UIDimSel: { fg: "surfaceFg", bg: "greenMuted", reverse: false },
    TxSelect: { fg: "surfaceFg", bg: "greenMuted", reverse: false },
    TxUser: { fg: "surfaceFg", bg: "gray", reverse: false },
    TxToolTitle: { fg: "fg", bold: true },
    TxToolArg: { fg: "green" },
    TxToolOutput: { fg: "surfaceFg", dim: true },
    TxToolHint: { fg: "surfaceFg", dim: true },
    TxToolError: { fg: "red" },
    TxError: { fg: "red", bold: true },
    TxToolPendingBg: { bg: "pendingBg" },
    TxToolErrorBg: { bg: "errorBg" },
    TxDiffAdd: { fg: "strongFg", bg: "diffAddBg", bold: false },
    TxDiffDel: { fg: "red", bg: "diffDelBg", dim: false },
    TxDiffContext: { fg: "surfaceFg", dim: true },
    NotifyWarn: { fg: "yellow", bold: true },
    NotifyError: { fg: "red", bold: true },
  },
});

const MANTIS_LIGHT = /** @type {const} */ ({
  ...MANTIS_DARK,
  palette: {
    fg: "reset",
    bg: "reset",
    surfaceFg: "#1F2328",
    strongFg: "#0D1117",
    green: "#2D6A4F",
    greenMuted: "#B7D7B0",
    gray: "#E8EAED",
    yellow: "#9A6700",
    red: "#CF222E",
    pendingBg: "#FFF8C5",
    errorBg: "#FFEBE9",
    diffAddBg: "#E6F4EA",
    diffDelBg: "#FFEBE9",
  },
});

plugins.use({
  name: "mantis-theme",
  apply(ctx) {
    ctx.inject(["tui"], (c) => {
      const apply = () => c.tui.style.theme(c.tui.background === "light" ? MANTIS_LIGHT : MANTIS_DARK);
      apply();
      c.on("background.changed", apply);
    });
  },
});
