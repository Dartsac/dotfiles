import net from "node:net";

// One newline-delimited API response; cap it, check server errors, and always
// close the socket. A successful write alone is not evidence of acceptance.
export function request(socketPath, method, params, timeoutMs = 1500) {
  return new Promise((resolve, reject) => {
    let body = "";
    let done = false;
    const socket = net.createConnection(socketPath);
    socket.setEncoding("utf8");
    const timer = setTimeout(() => finish(new Error(`Herdr ${method}: timeout`)), timeoutMs);
    timer.unref?.();
    const finish = (error, result) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      socket.removeAllListeners();
      socket.destroy();
      error ? reject(error) : resolve(result);
    };
    socket.on("error", error => finish(error));
    socket.on("end", () => finish(new Error(`Herdr ${method}: closed without response`)));
    socket.on("connect", () => socket.write(JSON.stringify({ id: "dotfiles:pi", method, params }) + "\n"));
    socket.on("data", data => {
      body += data.toString();
      if (body.length > 2_000_000) return finish(new Error("Herdr response too large"));
      if (!body.includes("\n")) return;
      try {
        const response = JSON.parse(body.slice(0, body.indexOf("\n")));
        if (response.error) finish(new Error(JSON.stringify(response.error)));
        else finish(undefined, response.result);
      } catch (error) { finish(error); }
    });
  });
}
