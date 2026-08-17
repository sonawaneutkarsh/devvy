const http = require("http");

const server = http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    console.log(req.method, req.url, body.slice(0, 500));
    res.writeHead(200, { "content-type": "application/json" });
    res.end('{"ok":true}');
  });
});

server.listen(17377, "127.0.0.1", () => {
  console.log("fake daemon listening on 17377");
});
