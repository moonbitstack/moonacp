/* The playground: the settings on the left are handed to the library, built to JavaScript, and what
   comes back is what the library wrote — its own encoders, not a copy of them in this file. */

const engine = await import("./engine/browser.js").catch(() => null);

const form = document.querySelector("[data-bench]");
const requestOut = document.querySelector("[data-out=request]");
const updatesOut = document.querySelector("[data-out=updates]");
const resultOut = document.querySelector("[data-out=result]");
const framesOut = document.querySelector("[data-out=frames]");
const missing = document.querySelector("[data-missing]");

function render(text, into) {
  into.textContent = text;
}

function draw() {
  if (!engine) return;
  const settings = {
    text: form.elements.text.value,
    stop_reason: form.elements.stop_reason.value,
    tool_call: form.elements.tool_call.checked,
  };
  let answer;
  try {
    answer = JSON.parse(engine.preview(JSON.stringify(settings)));
  } catch (error) {
    missing.hidden = false;
    missing.textContent = "The library could not encode that: " + error.message;
    return;
  }
  render(answer.request, requestOut);
  updatesOut.replaceChildren(
    ...answer.updates.map((update) => {
      const block = document.createElement("pre");
      block.className = "wire";
      block.textContent = update;
      return block;
    }),
  );
  render(answer.result, resultOut);
  framesOut.replaceChildren(
    ...answer.frames.map((frame) => {
      const block = document.createElement("pre");
      block.className = "frame";
      const [head, ...rest] = frame.split("\r\n");
      const label = document.createElement("span");
      label.className = "frame-head";
      label.textContent = head;
      block.append(label, document.createTextNode("\r\n" + rest.join("\r\n")));
      return block;
    }),
  );
}

if (engine) {
  for (const field of form.elements) {
    field.addEventListener("input", draw);
    field.addEventListener("change", draw);
  }
  draw();
} else {
  missing.hidden = false;
  missing.textContent =
    "The engine did not load. It is built from this library by the documentation workflow, so this page has to be opened from the published site rather than from a file.";
}
