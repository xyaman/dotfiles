import { connect } from "yuke:net";
import type { Cleanup, PluginContext, SessionState, InteractionId } from "yuke:plugins";
import { env } from "yuke:process";

const timeoutMs = 250;
const frameLimit = 4096;
const maxAttempts = 3;

type State = "idle" | "working" | "blocked";

export function apply(ctx: PluginContext): Cleanup | undefined {
  if (env.get("HERDR_ENV") !== "1" || env.get("AI_AGENT") || env.get("CLAUDECODE")) return undefined;
  if (!ctx.get("tui")) return undefined;
  const path = env.get("HERDR_SOCKET_PATH");
  const pane = env.get("HERDR_PANE_ID");
  if (!path || !pane) return undefined;
  return report(ctx, path, pane);
}

export function report(ctx: PluginContext, path: string, pane: string): Cleanup {
  const sessions = new Map<string, { state: SessionState; questions: Set<InteractionId> }>();
  let id = 0;
  let seq = 0;
  let attempts = 0;
  let retry: number | undefined;
  let desired: State = "idle";
  let acknowledged = "";
  let active: Promise<void> | undefined;

  async function request(method: string, params: Record<string, string>, cleanup = false): Promise<void> {
    const requestId = String(++id);
    // Herdr keeps seq across reporter restarts.
    seq = Math.max(seq + 1, Date.now());
    const signal = AbortSignal.any([
      AbortSignal.timeout(timeoutMs),
      ...(cleanup ? [] : [ctx.signal]),
    ]);
    using socket = await connect({ transport: "unix", path, signal });
    await socket.write(new TextEncoder().encode(JSON.stringify({
      id: requestId, method, params: { pane_id: pane, source: "custom:yuke", agent: "yuke", seq, ...params },
    }) + "\n"));
    const reader = socket.readable.getReader();
    const frame = new Uint8Array(frameLimit);
    let used = 0;
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) throw new Error("Incomplete Herdr response");
        for (const byte of value) {
          if (byte === 10) {
            const response = JSON.parse(new TextDecoder().decode(frame.subarray(0, used)));
            if (!response || response.id !== requestId || "error" in response || response.result?.type !== "ok") {
              throw new Error("Invalid Herdr response");
            }
            return;
          }
          if (used === frameLimit) throw new Error("Herdr response exceeds the byte limit");
          frame[used++] = byte;
        }
      }
    } finally {
      reader.releaseLock();
    }
  }

  function schedule(): void {
    if (ctx.signal.aborted || active || retry !== undefined || desired === acknowledged || attempts >= maxAttempts) return;
    const state = desired;
    let failure: unknown;
    attempts++;
    active = request("pane.report_agent", { state })
      .then(() => { acknowledged = state; }, error => { acknowledged = ""; failure = error; })
      .then(() => {
        active = undefined;
        if (ctx.signal.aborted || desired === acknowledged) return;
        if (desired !== state) schedule();
        else if (attempts < maxAttempts) retry = setTimeout(() => { retry = undefined; schedule(); }, timeoutMs);
        else ctx.notify("warn", `Herdr report failed: ${String(failure)}`);
      });
  }

  function refresh(): void {
    const values = [...sessions.values()];
    const state: State = values.some(s => s.questions.size > 0) ? "blocked"
      : values.some(s => s.state === "running") ? "working" : "idle";
    if (state !== desired) {
      desired = state;
      attempts = 0;
      clearTimeout(retry);
      retry = undefined;
    }
    schedule();
  }

  ctx.on("session.opened", ({ sessionId, state, questions }) => {
    sessions.set(sessionId, { state, questions: new Set(questions) });
    refresh();
  });
  ctx.on("session.closed", ({ sessionId }) => { sessions.delete(sessionId); refresh(); });
  ctx.on("session.update", ({ sessionId, update }) => {
    const session = sessions.get(sessionId);
    if (!session) return;
    switch (update.sessionUpdate) {
      case "state": session.state = update.state; break;
      case "interaction_requested": session.questions.add(update.interactionId); break;
      case "interaction_closed": session.questions.delete(update.interactionId); break;
      default: return;
    }
    refresh();
  });
  refresh();

  return async () => {
    clearTimeout(retry);
    await active;
    // The plugin signal is already aborted during cleanup.
    try { await request("pane.release_agent", {}, true); } catch {}
  };
}
