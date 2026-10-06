import { createServer } from 'node:http'
import { randomUUID } from 'node:crypto'

export function startServer() {
  const token = randomUUID()
  const secret = randomUUID()
  const server = createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1')
    if (url.pathname === '/login') {
      res.setHeader('Set-Cookie', `sid=${token}; Path=/; SameSite=Lax; Max-Age=3600`)
      res.setHeader('Content-Type', 'text/html')
      res.end('<html><body><h1>Logged in</h1></body></html>')
      return
    }
    if (url.pathname === '/app') {
      res.setHeader('Content-Type', 'text/html')
      res.end(
        '<html><body><h1>Demo App</h1><button id="go">Load items</button><ul id="list"></ul>' +
          '<script>document.getElementById("go").onclick=function(){setTimeout(function(){' +
          'var items=["alpha","bravo","charlie","delta","echo","foxtrot"];' +
          'document.getElementById("list").innerHTML=items.map(function(t){return \'<li class="item">\'+t+\'</li>\'}).join("")},600)}</script>' +
          '</body></html>',
      )
      return
    }
    if (url.pathname === '/secret') {
      const cookie = req.headers.cookie || ''
      if (cookie.includes(`sid=${token}`)) {
        res.setHeader('Content-Type', 'application/json')
        res.end(JSON.stringify({ secret }))
      } else {
        res.statusCode = 401
        res.end('unauthorized')
      }
      return
    }
    res.statusCode = 404
    res.end('not found')
  })
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address()
      resolve({
        port,
        secret,
        base: `http://127.0.0.1:${port}`,
        close: () => new Promise((r) => server.close(r)),
      })
    })
  })
}
