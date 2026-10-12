<?php
/*
 * Šachové Orákulum – sdílené úložiště pro všechny hráče
 * ------------------------------------------------------
 * Data se ukládají do souboru data/sachy.json vedle tohoto skriptu.
 * PIN = heslo pro zápis. Doporučuju ho nastavit, protože stránka je veřejná
 * (bez něj může kdokoli z internetu zapisovat nebo mazat).
 * Prohlížení funguje vždy bez hesla.
 */
const PIN  = '';                                  // <<< SEM NAPIŠ HESLO, např. 'kun123'
const DATA = __DIR__ . '/data/sachy.json';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function fresh() { return ['settings' => ['stake' => 100], 'players' => [], 'games' => []]; }
function out($d, $code = 200) { http_response_code($code); echo json_encode($d, JSON_UNESCAPED_UNICODE); exit; }
function txt($v, $max) { $v = trim((string)$v); preg_match('/^.{0,' . $max . '}/us', $v, $m); return $m[0] ?? ''; }
function newid() { return base_convert((string)time(), 10, 36) . bin2hex(random_bytes(3)); }
function hasPlayer($S, $id) { foreach ($S['players'] as $p) if ($p['id'] === $id) return true; return false; }

function cleanPlayer($p, $id = null) {
    $name = txt($p['name'] ?? '', 24);
    if ($name === '') return null;
    $color = preg_match('/^#[0-9a-fA-F]{6}$/', $p['color'] ?? '') ? $p['color'] : '#ffffff';
    return ['id' => $id ?: newid(), 'name' => $name, 'icon' => txt($p['icon'] ?? '♟', 8) ?: '♟', 'color' => $color];
}
function cleanGame($S, $g, $id = null) {
    $w = (string)($g['white'] ?? ''); $b = (string)($g['black'] ?? '');
    $r = (string)($g['result'] ?? ''); $at = (string)($g['at'] ?? '');
    if ($w === $b || !hasPlayer($S, $w) || !hasPlayer($S, $b)) return null;
    if (!in_array($r, ['w', 'd', 'b'], true)) return null;
    if (!preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/', $at)) return null;
    return ['id' => $id ?: newid(), 'white' => $w, 'black' => $b, 'result' => $r, 'at' => $at];
}

// --- otevření souboru se zámkem (aby se dva zápisy nepřepsaly) ---
if (!is_dir(dirname(DATA))) @mkdir(dirname(DATA), 0775, true);
$fp = @fopen(DATA, 'c+');
if (!$fp) out(['error' => 'Nelze otevřít data/sachy.json – zkontroluj práva ke složce data/'], 500);
$method = $_SERVER['REQUEST_METHOD'];
flock($fp, $method === 'POST' ? LOCK_EX : LOCK_SH);
$raw = stream_get_contents($fp);
$S = $raw ? json_decode($raw, true) : null;
if (!is_array($S)) $S = fresh();
$S += fresh();

if ($method === 'GET') out($S);
if ($method !== 'POST') out(['error' => 'Nepovolená metoda'], 405);

$in = json_decode(file_get_contents('php://input'), true);
if (!is_array($in)) out(['error' => 'Špatný požadavek'], 400);
if (PIN !== '' && !hash_equals(PIN, (string)($in['pin'] ?? ''))) out(['error' => 'pin'], 403);

switch ($in['action'] ?? '') {
    case 'addGame':
        $g = cleanGame($S, $in);
        if (!$g) out(['error' => 'Neplatná partie'], 400);
        $S['games'][] = $g;
        break;

    case 'delGame':
        $S['games'] = array_values(array_filter($S['games'], fn($g) => $g['id'] !== ($in['id'] ?? '')));
        break;

    case 'savePlayer':
        $id = (string)($in['id'] ?? '');
        $p = cleanPlayer($in, $id ?: null);
        if (!$p) out(['error' => 'Hráč potřebuje jméno'], 400);
        $found = false;
        foreach ($S['players'] as &$x) if ($x['id'] === $id) { $x = $p; $found = true; }
        unset($x);
        if (!$found) $S['players'][] = $p;
        break;

    case 'delPlayer':
        $id = (string)($in['id'] ?? '');
        $S['players'] = array_values(array_filter($S['players'], fn($p) => $p['id'] !== $id));
        $S['games']   = array_values(array_filter($S['games'], fn($g) => $g['white'] !== $id && $g['black'] !== $id));
        break;

    case 'setStake':
        $S['settings']['stake'] = (int)($in['stake'] ?? 0);
        break;

    case 'import':
        $d = $in['data'] ?? null;
        if (!is_array($d) || !is_array($d['players'] ?? null) || !is_array($d['games'] ?? null)) out(['error' => 'Neplatný soubor'], 400);
        $N = fresh();
        $N['settings']['stake'] = (int)($d['settings']['stake'] ?? $d['settings']['win'] ?? 100);
        foreach ($d['players'] as $p) { $c = cleanPlayer($p, isset($p['id']) ? txt($p['id'], 40) : null); if ($c) $N['players'][] = $c; }
        foreach ($d['games'] as $g) { $c = cleanGame($N, $g, isset($g['id']) ? txt($g['id'], 40) : null); if ($c) $N['games'][] = $c; }
        $S = $N;
        break;

    case 'wipe':
        $S = fresh();
        break;

    default:
        out(['error' => 'Neznámá akce'], 400);
}

ftruncate($fp, 0); rewind($fp);
fwrite($fp, json_encode($S, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
fflush($fp); flock($fp, LOCK_UN); fclose($fp);
out($S);
