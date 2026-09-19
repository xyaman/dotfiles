import { plugins } from "yuke:ext";
import { composerVim } from "yuke:composer-vim";
import { transcriptVim } from "yuke:transcript-vim";
import "./tools/web.js";

plugins.use(composerVim);
plugins.use(transcriptVim);
