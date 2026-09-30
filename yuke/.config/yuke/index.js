import { plugins } from "yuke";
import { composerVim, transcriptVim, agents } from "yuke:plugins";
import "./tools/web.js";
import { herdr } from "./plugins/herdr.js";

plugins.use(composerVim);
plugins.use(transcriptVim);
plugins.use(herdr());

// One general child with every tool, on Codex Luna whatever the parent runs.
plugins.use(agents({
  catalog: {
    general: { description: "A capable general agent. Give it one self-contained task.", model: "openai-codex/gpt-5.6-luna" },
  },
}));

plugins.use({
  name: "tool-background-probe",
  apply(ctx) {
    ctx.inject(["tui"], (c) => {
      c.tui.style.theme({
        groups: {
          TxToolPendingBg: { bg: "#302f20" },
          TxToolSuccessBg: { bg: "#203020" },
          TxToolErrorBg: { bg: "#402020" },
        },
      });
    });
  },
});
