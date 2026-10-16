
const http = require("http");

const COLOR = process.env.COLOR || "unknown";
const VERSION = process.env.APP_VERSION || "dev";
const PORT = 3000;
let requestCount = 0;

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ status: "ok" }));
  }

  if (req.url === "/metrics") {
    res.writeHead(200, { "Content-Type": "text/plain; version=0.0.4" });
    return res.end(
      [
        "# HELP app_http_requests_total Requests served (excluding health and metrics)",
        "# TYPE app_http_requests_total counter",
        `app_http_requests_total{color="${COLOR}",version="${VERSION}"} ${requestCount}`,
        "# HELP app_info Which color and version this container runs",
        "# TYPE app_info gauge",
        `app_info{color="${COLOR}",version="${VERSION}"} 1`,
        "",
      ].join("\n")
    );
  }

  requestCount++;

  if (req.url === "/version") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ color: COLOR, version: VERSION }));
  }

  res.writeHead(200, { "Content-Type": "text/html" });
  res.end(`<!doctype html>
<html>
  <head><title>Blue-Green Demo</title></head>
  <body style="font-family:sans-serif;text-align:center;padding-top:15vh;background:${COLOR};color:white">
    <h1>Hello from the ${COLOR.toUpperCase()} environment</h1>
    <h2>Version: ${VERSION}</h2>
<p>Shiny new feature!</p>
  </body>
</html>`);
});

server.listen(PORT, "0.0.0.0", () => console.log(`${COLOR} ${VERSION} listening on ${PORT}`));

// Lets `docker stop` shut the app down cleanly instead of waiting 10s and killing it
process.on("SIGTERM", () => server.close(() => process.exit(0)));