let input = "";
for await (const chunk of process.stdin) input += chunk;

const response = JSON.parse(input.trim());
if (response.result?.isError) {
  throw new Error(`MCP returned an error: ${response.result.content?.[0]?.text}`);
}
if (response.result?.content?.length !== 2) {
  throw new Error(
    `MCP did not return text plus image (count: ${response.result?.content?.length}; response: ${JSON.stringify(response).slice(0, 1000)})`,
  );
}
if (response.result.content[0].type !== "text") {
  throw new Error("MCP semantic text content is missing");
}
if (response.result.content[1].type !== "image") {
  throw new Error("MCP image content is missing");
}
if (response.result.content[1].mimeType !== "image/png") {
  throw new Error("MCP image MIME type is not image/png");
}
