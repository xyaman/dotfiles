import { plugins } from "yuke:ext";
import { composerVim } from "yuke:composer-vim";
import { transcriptVim } from "yuke:transcript-vim";
import { webSearchPlugin } from "./tools/web_search.js";

plugins.use(composerVim);
plugins.use(webSearchPlugin);
plugins.use(transcriptVim);
