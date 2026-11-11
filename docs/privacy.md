# Privacy

deskforge has no accounts, no keys, no telemetry and no server of its own.

| Feature | Host | What is sent |
|---|---|---|
| Panel weather | api.open-meteo.com | your latitude and longitude, every 10 minutes |
| Panel prices | api.coingecko.com | the coin ids, every `refreshSeconds` |
| Panel status | status.claude.com | nothing but the request, every 5 minutes |
| Startup check | api.open-meteo.com | one request at latitude 0, longitude 0, to see if you are online |
| Tape, Depth (addons) | api.binance.com, data-api.binance.vision | the BTCUSDT symbol |
| Mood (addon) | data-api.binance.vision | the BTCUSDT symbol, once a minute |

Each host sees your IP address, as with any web request. Nothing else leaves the machine. The now-playing and
dock helpers read window titles on your PC only and never send them anywhere. There is no camera, microphone
recording or keyboard hook.

The repo itself was built from an allowlist with names, paths, coordinates and image metadata removed, and
`tests\privacy-scan.ps1` checks every file, archive and commit message before anything is published.