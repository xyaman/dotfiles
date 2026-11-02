import { assert, createHost, equal, listen, reply, test } from "yuke:test";
import type { QuestionAnswer } from "yuke:plugins";
import { report } from "./index.ts";

test("reports idle, working, blocked, and releases its label on exit", async () => {
  using server = listen();
  const requests: { id: string; method: string; params: { state?: string; seq: number; pane_id: string; source: string; agent: string } }[] = [];
  let stopped = false;
  const serve = async () => {
    while (!stopped) {
      try {
        using socket = await server.accept();
        const reader = socket.readable.getReader();
        let text = "";
        while (!text.includes("\n")) {
          const chunk = await reader.read();
          assert(!chunk.done);
          text += new TextDecoder().decode(chunk.value);
        }
        reader.releaseLock();
        const request = JSON.parse(text);
        requests.push(request);
        // Exercise partial-frame reads.
        const response = JSON.stringify({ id: request.id, result: { type: "ok" } }) + "\n";
        await socket.write(new TextEncoder().encode(response.slice(0, 5)));
        await socket.write(new TextEncoder().encode(response.slice(5)));
      } catch (error) { if (!stopped) throw error; }
    }
  };
  const serving = serve();
  const waitFor = async (predicate: () => boolean) => {
    for (let i = 0; i < 300 && !predicate(); i++) await new Promise(resolve => setTimeout(resolve, 5));
    assert(predicate(), "report did not arrive");
  };
  let answer: ((value: QuestionAnswer[]) => void) | undefined;
  try {
    const host = await createHost({
      plugins: [{
        name: "herdr-test",
        apply: ctx => report(ctx, server.path, "test-pane"),
        session(s) {
          s.tools.define({
            name: "ask_test", description: "Ask", concurrency: "serial",
            parameters: { type: "object", properties: {} },
            async execute(_, { signal }) {
              await s.ask({ questions: [{ id: "continue", header: "Confirm", question: "Continue?", options: [], other: true }] }, { signal });
              return "done";
            },
          });
        },
      }],
      replies: [reply.toolCall("ask_test", {}), reply.text("done")],
      answer: () => new Promise(resolve => { answer = resolve; }),
    });
    try {
      await waitFor(() => requests.some(r => r.params.state === "idle"));
      const session = await host.openSession();
      const sending = session.send("work");
      await waitFor(() => requests.some(r => r.params.state === "blocked") && answer !== undefined);
      assert(requests.some(r => r.params.state === "working"));
      answer!([{ id: "continue", values: [], other: "yes" }]);
      await sending;
      await waitFor(() => requests.at(-1)?.params.state === "idle");
    } finally { await host.close(); }
    equal(requests.at(-1)?.method, "pane.release_agent");
    for (let i = 0; i < requests.length; i++) {
      const params = requests[i]!.params;
      equal(params.pane_id, "test-pane");
      equal(params.source, "custom:yuke");
      equal(params.agent, "yuke");
      if (i) assert(params.seq > requests[i - 1]!.params.seq);
    }
  } finally {
    stopped = true;
    server.close();
    await serving;
  }
});

test("unavailable Herdr never blocks startup or shutdown", async () => {
  const host = await createHost({ plugins: [{
    name: "herdr-test", apply: ctx => report(ctx, "/tmp/yuke-herdr-missing-test.sock", "test-pane"),
  }] });
  await host.openSession();
  await host.close();
});
