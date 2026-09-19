import { plugins } from "yuke";
import { composerVim } from "yuke:composer-vim";
import { transcriptVim } from "yuke:transcript-vim";
import "./tools/web.js";
import { herdr } from "./plugins/herdr.js";

plugins.use(composerVim);
plugins.use(transcriptVim);

plugins.use(herdr());
