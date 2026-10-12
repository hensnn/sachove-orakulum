# ♞ Šachové Orákulum

Absurdně barevné počítadlo šachových sázek mezi kamarády, stavěné hlavně pro mobil.

- 💰 **Sázky:** kdo prohraje, zaplatí vítězi sázku (nastavitelná, výchozí 100). Při remíze se nic nepřesouvá.
- 🏆 **Žebříček:** bilance každého hráče v plusu či mínusu, výhry, remízy, prohry a úspěšnost.
- ⚔️ **Duely:** vzájemné skóre a kdo komu kolik dluží.
- 📜 **Kronika:** historie všech partií s datem a časem.
- 🦄 **Hráči:** vlastní jméno, ikona a barva.
- 👥 **Sdílené pro všechny:** data leží na serveru, každý vidí totéž a stránka se sama obnovuje.
- 🔒 **Heslo pro zápis:** prohlížet může kdokoli, zapisovat jen ten, kdo zná heslo.

---

## 🚀 Instalace

Stačí jakýkoli webový server s **PHP 7.4+** (Caddy, nginx, Apache, sdílený webhosting…).

### Ručně

1. Nahraj `index.html` a `api.php` do jedné složky na webu.
2. Vedle nich vytvoř složku `data/` a dej webovému serveru (PHP) právo do ní zapisovat.
3. V `api.php` nastav heslo pro zápis:
   ```php
   const PIN  = 'tvoje-heslo';
   ```
4. Doporučeno: zakaž přímý přístup ke složce `data/` (data se čtou jen přes `api.php`).

Hotovo. Data se ukládají do `data/sachy.json`.

### Automaticky (Debian / Ubuntu + Caddy)

Pro server s Debianem nebo Ubuntu, na kterém běží Caddy, je připravený skript. Spusť ho jako `root`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hensnn/sachove-orakulum/main/install-caddy.sh)
```

Skript nainstaluje PHP, stáhne aplikaci do `/var/www/html`, zeptá se na heslo a nastaví Caddy na port 80 (původní `Caddyfile` předtím zazálohuje).

HTTPS a doménu si vyřeš podle sebe: Caddy to umí sám, nebo ho schovej za reverzní proxy.

**Aktualizace:** spusť stejný příkaz znovu. Heslo, data i `Caddyfile` zůstanou.

### Bez vlastního serveru (Supabase)

Aplikace umí ukládat i do [Supabase](https://supabase.com), takže pak stačí statický hosting (např. GitHub Pages):

1. V Supabase spusť obsah `supabase.sql` v SQL Editoru. Předtím v něm přepiš `ZMEN-ME` na své heslo.
2. V `index.html` vyplň `SUPABASE_URL` a `SUPABASE_KEY` (veřejný *anon / publishable* klíč).

---

## 💾 Záloha

Zkopíruj si `data/sachy.json`, nebo ve stránce použij **Nastavení → Exportovat**. Obnovit jde přes **Importovat**.

---

## 📁 Soubory

| Soubor | K čemu je |
|---|---|
| `index.html` | celá aplikace (vzhled a logika) |
| `api.php` | ukládání dat na serveru, kontrola hesla |
| `install-caddy.sh` | automatická instalace a aktualizace pro Debian + Caddy |
| `supabase.sql` | databáze pro variantu se Supabase |
