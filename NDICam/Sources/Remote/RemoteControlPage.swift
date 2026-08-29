import Foundation

extension RemoteControlServer {

    /// Self-contained control page. Fluid layout that works from a ~220px-wide
    /// OBS dock up to a full window — no external assets.
    static let page = #"""
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>NDICam</title>
    <style>
      *, *::before, *::after { box-sizing: border-box; }
      :root { color-scheme: dark; }
      html, body { margin:0; }
      body {
        font:13px/1.3 -apple-system,system-ui,"Segoe UI",sans-serif;
        background:#141414; color:#e8e8e8; padding:10px;
        max-width:640px; margin:0 auto;
      }
      h1 { font-size:12px; letter-spacing:1px; color:#9a9a9a; margin:0 0 10px; }

      .bar { display:flex; flex-wrap:wrap; gap:6px; margin-bottom:10px; }
      button {
        flex:1 1 auto; min-width:0; background:#262626; color:#e8e8e8;
        border:1px solid #3c3c3c; border-radius:7px; padding:8px 10px;
        font-size:13px; cursor:pointer; white-space:nowrap;
      }
      button.go { background:#2bbd6e; color:#04220f; border-color:#2bbd6e; font-weight:600; }
      button:active { filter:brightness(.85); }

      fieldset { border:1px solid #2e2e2e; border-radius:9px; margin:0 0 10px; padding:9px 10px 11px; }
      legend { color:#8a8a8a; padding:0 5px; font-size:11px; letter-spacing:.5px; }

      .seg { display:flex; gap:5px; margin-bottom:8px; }
      .seg button.on { background:#2bbd6e; color:#04220f; border-color:#2bbd6e; }

      .ctl { margin:8px 0 4px; }
      .ctl .top { display:flex; justify-content:space-between; margin-bottom:3px; }
      .ctl .top span:last-child { color:#a8a8a8; font-variant-numeric:tabular-nums; }
      input[type=range] { width:100%; margin:0; accent-color:#2bbd6e; }

      .off { opacity:.35; pointer-events:none; }
    </style></head><body>
    <h1>NDICAM REMOTE</h1>

    <div class="bar">
      <button class="go" onclick="post('/broadcast')">Start / Stop NDI</button>
      <button onclick="post('/camera')">Flip</button>
    </div>

    <fieldset>
      <legend>EXPOSURE</legend>
      <div class="seg">
        <button id="ae1" onclick="setAE(true)">Auto</button>
        <button id="ae0" onclick="setAE(false)">Manual</button>
      </div>
      <div id="expM">
        <div class="ctl"><div class="top"><span>ISO</span><span id="isoV"></span></div>
          <input type="range" id="iso" oninput="push()"></div>
        <div class="ctl"><div class="top"><span>Shutter</span><span id="shV"></span></div>
          <input type="range" id="sh" oninput="push()"></div>
      </div>
    </fieldset>

    <fieldset>
      <legend>WHITE BALANCE</legend>
      <div class="seg">
        <button id="wb1" onclick="setWB(true)">Auto</button>
        <button id="wb0" onclick="setWB(false)">Manual</button>
      </div>
      <div id="wbM">
        <div class="ctl"><div class="top"><span>Temp</span><span id="tempV"></span></div>
          <input type="range" id="temp" min="2500" max="9000" step="50" oninput="push()"></div>
        <div class="ctl"><div class="top"><span>Tint</span><span id="tintV"></span></div>
          <input type="range" id="tint" min="-150" max="150" step="1" oninput="push()"></div>
      </div>
    </fieldset>

    <script>
    let S = null, R = null, timer = null, editing = 0;

    async function load() {
      if (editing) return;
      try {
        const j = await (await fetch('/state')).json();
        S = j.state; R = j.ranges;
        iso.min = R.minISO; iso.max = R.maxISO;
        sh.min = R.minShutterDenominator; sh.max = R.maxShutterDenominator;
        render();
      } catch (e) {}
    }
    function render() {
      if (!S) return;
      iso.value = S.iso; sh.value = S.shutterDenominator;
      temp.value = S.temperature; tint.value = S.tint;
      isoV.textContent = Math.round(S.iso);
      shV.textContent = '1/' + Math.round(S.shutterDenominator);
      tempV.textContent = Math.round(S.temperature) + 'K';
      tintV.textContent = Math.round(S.tint);
      ae1.className = S.autoExposure ? 'on' : '';
      ae0.className = S.autoExposure ? '' : 'on';
      wb1.className = S.autoWhiteBalance ? 'on' : '';
      wb0.className = S.autoWhiteBalance ? '' : 'on';
      expM.className = S.autoExposure ? 'off' : '';
      wbM.className = S.autoWhiteBalance ? 'off' : '';
    }
    function collect() {
      S.iso = +iso.value; S.shutterDenominator = Math.round(+sh.value);
      S.temperature = +temp.value; S.tint = +tint.value;
    }
    function push() {
      if (!S) return;
      editing = Date.now();
      collect(); render();
      clearTimeout(timer);
      timer = setTimeout(() => { send(); editing = 0; }, 150);
    }
    async function send() {
      if (!S) return;
      await fetch('/control', {method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify(S)});
    }
    function setAE(a) { if (S) { S.autoExposure = a; render(); send(); } }
    function setWB(a) { if (S) { S.autoWhiteBalance = a; render(); send(); } }
    async function post(p) { try { await fetch(p, {method:'POST'}); } catch (e) {} }

    load();
    setInterval(load, 4000);
    </script>
    </body></html>
    """#
}
