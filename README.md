# discourse-quick-reply-box

XenForo-stílusú azonnali válasz doboz minden téma alján. A "Válasz" gombok
a felugró szerkesztő helyett ebbe a dobozba visznek.

## Telepítés
`containers/app.yml`:

    hooks:
      after_code:
        - exec:
            cd: $home/plugins
            cmd:
              - git clone https://github.com/your-name/discourse-quick-reply-box.git

Majd: `cd /var/discourse && ./launcher rebuild app`

## Beállítások (Admin -> Plugins / Site settings)
- `quick_reply_box_enabled` - ki/be kapcsolás
- `quick_reply_intercept_post_replies` - a posztonkénti Válasz gombok is a dobozt használják
- `quick_reply_disable_on_mobile` - mobilon kikapcsolja a dobozt, a normál szerkesztő marad

## Működés
- Outlet: `topic-above-footer-buttons` (csak bejelentkezett felhasználóknak jelenik meg).
- A `controller:topic#replyToPost` felülírva: ha a doboz nincs a képernyőn, a téma végére ugrik, és a dobozra fókuszál.
- Küldés: `POST /posts.json`; Ctrl/Cmd+Enter; moderációs sor (enqueued) kezelve.
- Fájlfeltöltés: gomb, beillesztés (Ctrl+V) és ráhúzás; `POST /uploads.json`, a markdown a kurzor helyére kerül.
- A szerkesztő a Discourse saját DEditor komponense (teljes eszköztár, emoji), a felhasználó nyelvén. Piszkozat sessionStorage-ban; "Teljes szerkesztő" gomb átviszi a szöveget a normál composerbe.

Minimum Discourse: 3.3 (gjs connectorok).
