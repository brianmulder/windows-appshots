#!/usr/bin/env node
import { createInterface } from "node:readline";
import { handleRequest } from "./server-lib.mjs";

const lines = createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
  terminal: false,
});

lines.on("line", (line) => {
  line = line.replace(/^\uFEFF/u, "");
  if (!line.trim()) return;
  let message;
  try {
    message = JSON.parse(line);
  } catch (error) {
    process.stdout.write(
      `${JSON.stringify({
        jsonrpc: "2.0",
        id: null,
        error: { code: -32700, message: error.message },
      })}\n`,
    );
    return;
  }

  const response = handleRequest(message);
  if (response) process.stdout.write(`${JSON.stringify(response)}\n`);
});
