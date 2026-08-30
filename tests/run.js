#!/usr/bin/env node
// Runs spec.lua inside a real Lua VM (fengari), against the addon sources.
// Usage: node run.js [chemin/vers/Cleansive]

const path = require("node:path");
const fs = require("node:fs");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const here = __dirname;
const addon = path.resolve(here, process.argv[2] || "../work/Cleansive-1.4.0/Cleansive");

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// Let `require` and `loadfile` resolve relative to this folder.
lua.lua_getglobal(L, to_luastring("package"));
lua.lua_pushstring(L, to_luastring(here + "/?.lua"));
lua.lua_setfield(L, -2, to_luastring("path"));
lua.lua_pop(L, 1);

lua.lua_pushstring(L, to_luastring(addon));
lua.lua_setglobal(L, to_luastring("ADDON_PATH"));

// The .toc is the single source of truth for the version. Hand it to the VM
// so a test can assert the code advertises the packaged number.
const tocFile = fs.readdirSync(addon).find(f => f.toLowerCase().endsWith(".toc"));
const tocVersion = tocFile
  ? (fs.readFileSync(path.join(addon, tocFile), "utf8").match(/^##\s*Version:\s*(.+)$/m) || [])[1]
  : undefined;
lua.lua_pushstring(L, to_luastring((tocVersion || "").trim()));
lua.lua_setglobal(L, to_luastring("TOC_VERSION"));

const status = lauxlib.luaL_dofile(L, to_luastring(path.join(here, "spec.lua")));
if (status !== lua.LUA_OK) {
  console.error("Erreur Lua :\n" + lua.lua_tojsstring(L, -1));
  process.exit(2);
}

const report = lua.lua_tojsstring(L, -2);
let failed = lua.lua_tonumber(L, -1);

// Static source check, not a logic test: neither Expressway nor FRIZQT__.TTF
// carries arrows, bullets, check marks or geometric shapes, and they render as
// empty boxes. French needs only two-byte sequences, so any three-byte one is
// suspect unless it is a typographic mark the fonts do carry.
const ALLOWED = new Set(["\u2019", "\u2026", "\u201C", "\u201D", "\u2014", "\u2013"]);
const glyphOffenders = [];
for (const file of fs.readdirSync(addon).filter(f => f.endsWith(".lua")).sort()) {
  const lines = fs.readFileSync(path.join(addon, file), "utf8").split("\n");
  lines.forEach((line, i) => {
    for (const ch of line) {
      if (ch.codePointAt(0) > 0x7FF && !ALLOWED.has(ch)) {
        glyphOffenders.push(`${file}:${i + 1} ${JSON.stringify(ch)}`);
      }
    }
  });
}

// Static layout check, not a logic test: a slider anchored at y draws its
// control from y-25 to y-55, so anything else anchored inside that band and
// in the same column lands on top of the bar. This shape shipped twice --
// 1.4.7 (sound budget over "Quick tools") and 1.5.7 (the resize note over the
// columns and opacity sliders) -- and neither the mock nor the game reports it.
const layoutOffenders = [];
{
  const ux = path.join(addon, "EllesmereUX.lua");
  if (fs.existsSync(ux)) {
    const lines = fs.readFileSync(ux, "utf8").split("\n");
    const sliders = [];   // {page, x, y, width, line}
    const anchored = [];  // {page, x, y, line, name}
    let page = null;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.trim().startsWith("--")) continue;
      // self.optionsPages.<name> = <frame> marks which page follows.
      const p = line.match(/self\.optionsPages\.(\w+)\s*=\s*(\w+)/);
      if (p) page = p[2];
      const s = line.match(/slider\(\s*(\w+)\s*,[^,]+,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(\d+)/);
      if (s) sliders.push({ page: s[1], x: +s[2], y: +s[3], width: +s[4], line: i + 1 });
      const a = line.match(/(\w+):SetPoint\("TOPLEFT",\s*(-?\d+)\s*,\s*(-?\d+)\s*\)/);
      if (a) anchored.push({ page, x: +a[2], y: +a[3], line: i + 1, name: a[1] });
      const sec = line.match(/\bsection\(\s*(\w+)\s*,.*?,\s*(-?\d+)\s*\)/);
      if (sec) anchored.push({ page: sec[1], x: 0, y: +sec[2], line: i + 1, name: "section" });
    }
    for (const s of sliders) {
      for (const a of anchored) {
        if (a.page !== s.page) continue;
        if (a.line === s.line) continue;
        // Le cadre du curseur est passe de 30 a 22 px de haut en 1.5.29 : la
        // bande suit, sinon le controle protege une zone qui n'existe plus.
        const inBand = a.y <= s.y - 22 && a.y >= s.y - 44;
        const sameColumn = a.x >= s.x && a.x <= s.x + s.width;
        if (inBand && sameColumn) {
          layoutOffenders.push(
            `EllesmereUX.lua:${a.line} ${a.name} en y=${a.y} tombe sur le curseur ligne ${s.line} (bande ${s.y - 22}..${s.y - 44}, colonne ${s.x}..${s.x + s.width})`);
        }
      }
    }
  }
}

// The spec loads the eight logic files; the two UI files are far too frame-
// heavy to execute against the mock. They are still edited constantly, so at
// least parse them: a typo there stops the whole addon from loading.
const parseOffenders = [];
for (const file of fs.readdirSync(addon).filter(f => f.endsWith(".lua")).sort()) {
  const L2 = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L2);
  if (lauxlib.luaL_loadfile(L2, to_luastring(path.join(addon, file))) !== lua.LUA_OK) {
    parseOffenders.push(`${file}: ${lua.lua_tojsstring(L2, -1)}`);
  }
}

// Static identity check. UnitGUID is SecretWhenUnitIdentityRestricted and
// UnitIsUnit is SecretWhenUnitComparisonRestricted: their results cannot be
// used in `or`, in a comparison, or as a table key where the restriction
// applies. A Lua table can be a table key, so the mock cannot reproduce the
// raise and no behavioural test can guard this -- only the shape can. Both
// calls belong inside their guards in Core.lua and nowhere else.
const identityOffenders = [];
{
  const guardNames = ["SafeUnitGUID", "IsPlayerUnit", "SafeUnitName", "SafeUnitFullName", "SafeUnitClass"];
  for (const file of fs.readdirSync(addon).filter(f => f.endsWith(".lua")).sort()) {
    const lines = fs.readFileSync(path.join(addon, file), "utf8").split("\n");
    let guard = null;
    lines.forEach((line, i) => {
      const open = line.match(/^function NS:(\w+)/);
      if (open) guard = guardNames.includes(open[1]) ? open[1] : null;
      else if (/^end\s*$/.test(line)) guard = null;
      if (guard) return;
      if (line.trim().startsWith("--")) return;
      if (/\b(UnitGUID|UnitIsUnit|UnitName|UnitFullName|UnitClass|GetUnitName)\s*\(/.test(line)) {
        identityOffenders.push(`${file}:${i + 1} ${line.trim().slice(0, 90)}`);
      }
    });
  }
}

// Static wording check. Two tooltips described behaviour the code does not
// have -- enabling was said to leave saved settings alone while it writes the
// profile, and the layout modes were said to be one row or one column after
// 1.5.18 made them wrap. A behavioural test guards what the code does; only a
// text rule stops the old sentence from coming back.
const wordingOffenders = [];
{
  const banned = [
    { text: "without changing your saved settings", why: "l'activation ecrit bien db.enabled" },
    { text: "sans modifier vos réglages enregistrés", why: "l'activation ecrit bien db.enabled" },
    { text: "one horizontal row, or one vertical column", why: "les modes se replient depuis 1.5.18" },
    { text: "une ligne horizontale ou une colonne verticale", why: "les modes se replient depuis 1.5.18" },
  ];
  const localePath = path.join(addon, "Locale.lua");
  if (fs.existsSync(localePath)) {
    const lines = fs.readFileSync(localePath, "utf8").split("\n");
    lines.forEach((line, i) => {
      for (const rule of banned) {
        if (line.includes(rule.text)) {
          wordingOffenders.push(`Locale.lua:${i + 1} « ${rule.text} » — ${rule.why}`);
        }
      }
    });
  }
}

// Un .toc vide ou incomplet est le seul defaut qui empeche l'addon de se
// charger entierement, et aucun test Lua ne peut le voir : la suite charge les
// fichiers elle-meme. Vecu le 28/08/2026, ou le .toc reduit a zero octet a
// laisse les 487 tests au vert.
// La page Aide annonce « toutes les commandes ». Elle en oubliait huit, dont
// les deux fonctions les plus recentes -- remappage des clics et profils par
// lieu -- qui n'ont aucun controle graphique : un joueur qui n'a pas lu le
// changelog ne pouvait pas les decouvrir du tout. Une promesse tenue par
// personne se verifie donc ici, pas a la relecture.
// Une couleur de texte est posee en blanc a une opacite : la couleur REELLE
// est sa composition sur le panneau, pas le blanc. Personne ne la mesurait, et
// le token des titres de section rendait 3,95:1 la ou un texte de moins de
// 18 px en demande 4,5. Les valeurs sont exactes : autant les calculer.
const contrastOffenders = [];
{
  const ux = fs.readFileSync(path.join(addon, "EllesmereUX.lua"), "utf8");
  const table = ux.match(/^local C = \{([\s\S]*?)^\}/m);
  const tokens = {};
  if (!table) {
    contrastOffenders.push("table des couleurs introuvable dans EllesmereUX.lua");
  } else {
    for (const m of table[1].matchAll(/(\w+)\s*=\s*\{\s*([0-9., ]+)\}/g)) {
      tokens[m[1]] = m[2].split(",").map(v => parseFloat(v.trim())).filter(v => !isNaN(v));
    }
  }
  const linear = c => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
  const luminance = c => 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2]);
  const panel = tokens.panel;
  // Les roles qui portent du TEXTE. Les surfaces n'ont pas de seuil a tenir.
  for (const role of ["text", "dim", "section"]) {
    const token = tokens[role];
    if (!token || !panel) {
      contrastOffenders.push(`token « ${role} » ou « panel » absent`);
      continue;
    }
    const alpha = token.length > 3 ? token[3] : 1;
    const composed = [0, 1, 2].map(i => alpha * token[i] + (1 - alpha) * panel[i]);
    const hi = Math.max(luminance(composed), luminance(panel));
    const lo = Math.min(luminance(composed), luminance(panel));
    const ratio = (hi + 0.05) / (lo + 0.05);
    if (ratio < 4.5) {
      contrastOffenders.push(
        `« ${role} » sur « panel » : ${ratio.toFixed(2)}:1, seuil 4.5:1 pour un texte sous 18 px`);
    }
  }
}

const helpOffenders = [];
{
  const core = fs.readFileSync(path.join(addon, "Core.lua"), "utf8");
  const locale = fs.readFileSync(path.join(addon, "Locale.lua"), "utf8");
  const verbs = new Set();
  for (const m of core.matchAll(/command\s*==\s*"([a-z]+)"/g)) verbs.add(m[1]);
  // Ces quatre-la sont des alias ou l'aide elle-meme ; les annoncer deux fois
  // allongerait la page sans rien apprendre.
  for (const alias of ["priority", "filter", "help", "cls"]) verbs.delete(alias);
  const blocks = [...locale.matchAll(/HELP_COMMANDS_TEXT = \[\[([\s\S]*?)\]\]/g)];
  if (blocks.length !== 2) {
    helpOffenders.push(`${blocks.length} page(s) d'aide trouvee(s), 2 attendues (une par langue)`);
  }
  for (const [index, block] of blocks.entries()) {
    const language = index === 0 ? "en" : "fr";
    for (const verb of [...verbs].sort()) {
      if (!new RegExp(`/cleansive[^\\n]*\\b${verb}\\b`).test(block[1])) {
        helpOffenders.push(`${language} : « /cleansive ${verb} » existe mais l'aide ne la cite pas`);
      }
    }
  }
}

const tocOffenders = [];
{
  const tocFiles = fs.readdirSync(addon).filter(f => f.toLowerCase().endsWith(".toc"));
  if (tocFiles.length !== 1) {
    tocOffenders.push(`${tocFiles.length} fichier(s) .toc a la racine, il en faut exactement un`);
  } else {
    const raw = fs.readFileSync(path.join(addon, tocFiles[0]), "utf8");
    if (!raw.trim()) {
      tocOffenders.push(`${tocFiles[0]} est vide`);
    } else {
      if (!/^##\s*Interface:\s*\d+\s*$/m.test(raw)) {
        tocOffenders.push(`${tocFiles[0]} ne declare pas de version d'interface`);
      }
      if (!(tocVersion || "").trim()) {
        tocOffenders.push(`${tocFiles[0]} ne declare pas de version`);
      }
      // Un fichier absent stoppe le chargement ; un fichier present mais non
      // liste ne se charge jamais, ce qui est la variante silencieuse.
      const listed = raw.split("\n")
        .map(l => l.trim())
        .filter(l => l && !l.startsWith("#"))
        .map(l => l.replace(/\\/g, "/"));
      for (const entry of listed) {
        if (!fs.existsSync(path.join(addon, entry))) {
          tocOffenders.push(`${tocFiles[0]} liste ${entry}, absent du dossier`);
        }
      }
      const declared = new Set(listed);
      for (const file of fs.readdirSync(addon).filter(f => f.endsWith(".lua")).sort()) {
        if (!declared.has(file)) {
          tocOffenders.push(`${file} est present mais absent du .toc : il ne sera jamais charge`);
        }
      }
    }
  }
}

// La plaque « en attente » ne peut pas mentir tant que tout report passe par
// MarkPending. Un `self.pendingX = true` pose a la main est exactement l'etat
// silencieux que cette plaque existe pour supprimer.
const pendingOffenders = [];
for (const file of fs.readdirSync(addon).filter(f => f.endsWith(".lua")).sort()) {
  const lines = fs.readFileSync(path.join(addon, file), "utf8").split("\n");
  lines.forEach((line, i) => {
    // Plus aucune exception : pendingSoundRefresh, seul drapeau exempte, etait
    // pose et jamais lu. Il a ete supprime plutot que documente une fois de
    // plus. La regle attrape aussi une valeur non litterale, ce qui manquait :
    // pendingEnabled recevait un booleen metier et echappait au controle.
    // Une valeur capturee plutot qu'une anticipation negative : \s* pouvait
    // reculer d'un espace et laisser passer « = nil » comme une pose.
    // Tout ce qui commence par « pending » n'est pas un report: ces champs-la
    // portent le prefixe sans etre des drapeaux, chacun avec sa raison.
    const notFlags = {
      pendingSoundRefreshReason: "la raison d'un rafraichissement, pas un report",
      pendingIndicator: "la plaque elle-meme",
      pendingAnnounced: "la table des reports annonces",
      pendingNoticeSuppressed: "la suppression d'annonce d'un evenement du jeu",
      pendingEnabledValue: "la valeur demandee, le drapeau est a cote",
      pendingGridVisibilityValue: "idem pour la visibilite de la grille",
      pendingAuraEngineReconcile: "budget de reprises du moteur, le joueur n'attend rien",
    };
    const assigned = line.match(/\bself\.(pending[A-Za-z]*)\s*=\s*([^\s;]+)/);
    if (assigned && !notFlags[assigned[1]]
      && assigned[2] !== "nil" && assigned[2] !== "false") {
      pendingOffenders.push(`${file}:${i + 1} report pose a la main, hors de MarkPending`);
    }
  });
}

console.log("Cleansive — tests de non-regression");
console.log("source : " + addon + "\n");
console.log(report);

if (glyphOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC polices : glyphe(s) que l'interface ne sait pas dessiner");
  for (const o of glyphOffenders.slice(0, 8)) console.log("          " + o);
  if (glyphOffenders.length > 8) console.log(`          … et ${glyphOffenders.length - 8} autre(s)`);
} else {
  console.log("  ok    polices : aucun glyphe hors du repertoire des polices WoW");
}

if (identityOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC identite : API d'identite appelee hors de son garde-fou");
  for (const o of identityOffenders) console.log("          " + o);
} else {
  console.log("  ok    identite : les 6 API d'identite passent par leurs garde-fous");
}

if (wordingOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC libelles : un texte decrit un comportement que le code n'a pas");
  for (const o of wordingOffenders) console.log("          " + o);
} else {
  console.log("  ok    libelles : aucun texte ne contredit le comportement connu");
}

if (contrastOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC contraste : un token de texte ne tient pas son seuil");
  for (const o of contrastOffenders) console.log("          " + o);
} else {
  console.log("  ok    contraste : les tokens de texte tiennent 4.5:1 sur le panneau");
}

if (helpOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC aide : la page annonce toutes les commandes et en oublie");
  for (const o of helpOffenders) console.log("          " + o);
} else {
  console.log("  ok    aide : chaque commande du code est citee dans les deux langues");
}

if (tocOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC toc : le manifeste ne permet pas de charger l'addon");
  for (const o of tocOffenders) console.log("          " + o);
} else {
  console.log("  ok    toc : manifeste complet, chaque fichier Lua declare et present");
}

if (pendingOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC report : un report de combat n'annonce rien au joueur");
  for (const o of pendingOffenders) console.log("          " + o);
} else {
  console.log("  ok    report : chaque report de combat passe par MarkPending");
}

if (parseOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC syntaxe : fichier(s) que Lua refuse de charger");
  for (const o of parseOffenders) console.log("          " + o);
} else {
  console.log("  ok    syntaxe : les " + fs.readdirSync(addon).filter(f => f.endsWith(".lua")).length + " fichiers Lua se chargent");
}

// Static restricted-event check. Blizzard marks some events HasRestrictions in
// its own generated documentation; registering one fires ADDON_ACTION_FORBIDDEN,
// a dialog whose first button disables the addon. 1.5.36 registered
// COMBAT_LOG_EVENT_UNFILTERED and the very next real session raised it. The list
// is read from DefinitionsAPI rather than written here, so it follows the client
// instead of a memory of it.
const restrictedOffenders = [];
{
  const docs = path.join(here, "..", "DefinitionsAPI", "InGameUI", "Interface",
    "AddOns", "Blizzard_APIDocumentationGenerated");
  const restricted = new Set();
  if (fs.existsSync(docs)) {
    for (const file of fs.readdirSync(docs).filter(f => f.endsWith(".lua"))) {
      const lines = fs.readFileSync(path.join(docs, file), "utf8").split("\n");
      lines.forEach((line, i) => {
        if (!/HasRestrictions\s*=\s*true/.test(line)) return;
        for (let k = i; k >= Math.max(0, i - 6); k--) {
          const m = lines[k].match(/LiteralName\s*=\s*"([A-Z0-9_]+)"/);
          if (m) { restricted.add(m[1]); break; }
        }
      });
    }
  }
  if (restricted.size) {
    for (const file of fs.readdirSync(addon).filter(f => f.endsWith(".lua"))) {
      const lines = fs.readFileSync(path.join(addon, file), "utf8").split("\n");
      lines.forEach((line, i) => {
        if (line.trim().startsWith("--")) return;
        for (const name of restricted) {
          if (line.includes('"' + name + '"')) {
            restrictedOffenders.push(`${file}:${i + 1} ${name} est marque HasRestrictions`);
          }
        }
      });
    }
  }
}

if (restrictedOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC evenements : un evenement restreint par Blizzard est nomme dans le code");
  for (const o of restrictedOffenders) console.log("          " + o);
} else {
  console.log("  ok    evenements : aucun evenement marque HasRestrictions n'est demande");
}

// Static coverage check. spec.lua keeps its own hand-written list of files to
// load, and it drifts: EllesmereUX.lua sat outside it for years on a reason
// that had stopped being true, and six blank sliders survived because of it.
// Diagnostics.lua was added to the .toc and forgotten there the same day this
// check was written. A Lua file the addon loads and no test ever executes is a
// file whose defects are invisible by construction.
const coverageOffenders = [];
{
  // Deliberate exclusions, each with the reason it is not in FILES.
  const excused = {
    "EllesmereUX.lua": "charge a la fin de spec.lua, apres les bouchons d'interface",
    "SetupWizard.lua": "assistant de premier lancement, sans logique a verifier",
  };
  const tocPath = path.join(addon, "Cleansive.toc");
  const specPath = path.join(here, "spec.lua");
  if (fs.existsSync(tocPath) && fs.existsSync(specPath)) {
    const declared = fs.readFileSync(tocPath, "utf8").split("\n")
      .map(l => l.trim()).filter(l => l.endsWith(".lua"));
    const spec = fs.readFileSync(specPath, "utf8");
    for (const file of declared) {
      if (spec.includes('"' + file + '"')) continue;
      if (excused[file]) continue;
      coverageOffenders.push(`${file} est charge par l'addon et par aucun test`);
    }
  }
}

if (coverageOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC couverture : un fichier de l'addon n'est execute par aucun test");
  for (const o of coverageOffenders) console.log("          " + o);
} else {
  console.log("  ok    couverture : chaque fichier du .toc est execute par la suite");
}

if (layoutOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC mise en page : element pose sur la barre d'un curseur");
  for (const o of layoutOffenders) console.log("          " + o);
} else {
  console.log("  ok    mise en page : aucun element pose sur la barre d'un curseur");
}

// ---------------------------------------------------------------------------
// Ce qui part reellement chez le joueur
//
// Les tests ci-dessus lisent les sources. Rien ne verifiait le DOSSIER : un
// fichier oublie, un reste de developpement, un BOM, deux noms qui ne different
// que par la casse -- autant de choses qui ne se voient qu'apres la
// publication, et sur la machine de quelqu'un d'autre.
// ---------------------------------------------------------------------------
const packageOffenders = [];
{
  // Ce qui part chez le joueur, c'est ce que l'empaqueteur laisse passer. La
  // liste d'exclusions vit deja dans .pkgmeta : la relire ici evite d'en tenir
  // une seconde a cote, qui divergerait au premier ajout.
  const ignored = new Set([".git", "node_modules"]);
  const pkgmeta = path.join(addon, ".pkgmeta");
  if (fs.existsSync(pkgmeta)) {
    let inIgnore = false;
    for (const line of fs.readFileSync(pkgmeta, "utf8").split("\n")) {
      if (/^ignore:/.test(line)) { inIgnore = true; continue; }
      if (inIgnore && /^\S/.test(line)) inIgnore = false;
      const entry = inIgnore && line.match(/^\s*-\s*"?([^"\s]+)"?\s*$/);
      if (entry) ignored.add(entry[1]);
    }
  }
  const entries = [];
  const directories = [];
  const walk = (dir, prefix) => {
    for (const name of fs.readdirSync(dir).sort()) {
      if (ignored.has(name) || ignored.has(prefix ? prefix + "/" + name : name)) continue;
      const full = path.join(dir, name);
      const relative = prefix ? prefix + "/" + name : name;
      if (fs.statSync(full).isDirectory()) {
        directories.push({ relative, name });
        walk(full, relative);
      } else entries.push({ relative, full, name });
    }
  };
  walk(addon, "");

  // Un dossier vide ne contient aucun fichier, donc il echappait entierement a
  // ce controle -- et .git-rewrite, residu d'une reecriture d'historique, est
  // parti dans l'archive 1.6 sous forme de trois dossiers vides. Ce qui
  // commence par un point n'a rien a faire chez le joueur, vide ou non.
  for (const entry of [...directories, ...entries]) {
    if (entry.name.startsWith(".")) {
      packageOffenders.push(`${entry.relative} est un element cache et ne doit pas etre livre`);
    }
  }

  // #278 : la licence doit voyager avec le code. Un depot MIT dont l'archive
  // n'embarque pas sa licence n'est pas distribue sous MIT.
  if (!entries.some(e => /^licen[cs]e/i.test(e.name))) {
    packageOffenders.push("aucun fichier de licence dans le dossier livre");
  }

  // #280 : la documentation de developpement et les restes d'edition ne
  // regardent pas le joueur, et ils gonflent le telechargement.
  for (const entry of entries) {
    if (/\.(bak|orig|rej|tmp|swp|zip)$/i.test(entry.name)
      || entry.name === ".DS_Store"
      || /^(spec|run)\.(lua|js)$/i.test(entry.name)) {
      packageOffenders.push(`${entry.relative} n'a rien a faire dans l'archive`);
    }
  }

  // #281 : macOS et Windows ne distinguent pas la casse, Linux si. Deux noms
  // qui ne different que par elle produisent une archive qui se decompresse
  // differemment selon la machine.
  //
  // ⚠️ Ce controle-ci ne peut PAS etre mis en defaut depuis un Mac : le systeme
  // de fichiers refuse de creer la situation. Il protege la CI Linux ou tourne
  // le packager, et un contributeur sous Linux. Il est donc le seul controle de
  // ce bloc qui n'a jamais ete vu rouge.
  const byLowerCase = new Map();
  for (const entry of entries) {
    const key = entry.relative.toLowerCase();
    if (byLowerCase.has(key)) {
      packageOffenders.push(`${entry.relative} et ${byLowerCase.get(key)} ne different que par la casse`);
    }
    byLowerCase.set(key, entry.relative);
  }

  // #282/#283 : un BOM en tete d'un .lua fait echouer son chargement chez
  // certains clients, et des fins de ligne CRLF cassent les scripts.
  for (const entry of entries) {
    if (!/\.(lua|toc|xml|md|txt)$/i.test(entry.name)) continue;
    const raw = fs.readFileSync(entry.full);
    if (raw.length >= 3 && raw[0] === 0xEF && raw[1] === 0xBB && raw[2] === 0xBF) {
      packageOffenders.push(`${entry.relative} commence par un BOM UTF-8`);
    }
    // Le CRLF n'est refuse que dans le DEPOT. L'empaqueteur BigWigs convertit
    // en CRLF a la construction : c'est la convention des addons WoW depuis
    // toujours, et le client charge les deux. Un .gitattributes en LF n'y
    // change rien, essaye et verifie sur l'archive publiee de la v1.6.15.
    // Refuser le paquet pour cela, c'etait refuser une convention que je ne
    // controle pas -- et un controle qu'on doit ignorer ne sert plus a rien.
    const inRepository = fs.existsSync(pkgmeta);
    if (inRepository && /\.(lua|toc|xml)$/i.test(entry.name)
      && raw.includes(Buffer.from("\r\n"))) {
      packageOffenders.push(`${entry.relative} contient des fins de ligne CRLF`);
    }
  }

  // #279 : un jeton de version laisse tel quel se retrouve affiche au joueur.
  if (tocVersion && /@[a-z-]+@/i.test(tocVersion)) {
    packageOffenders.push(`la version du .toc est restee un jeton : ${tocVersion}`);
  }

  // #287 : la version du .toc doit exister dans le changelog, sinon la page de
  // telechargement annonce une version dont personne ne sait ce qu'elle change.
  const changelog = entries.find(e => /^changelog\.md$/i.test(e.name));
  if (tocVersion && changelog) {
    // Comparer la ligne entiere : "## 1.5.55" est un prefixe de "## 1.5.55bis",
    // et un simple includes() declarait la version documentee alors qu'une
    // autre l'etait a sa place.
    const heading = "## " + tocVersion;
    const documented = fs.readFileSync(changelog.full, "utf8").split("\n")
      .some(line => line.trim() === heading);
    if (!documented) {
      packageOffenders.push(`le changelog ne dit rien de la version ${tocVersion}`);
    }
  } else if (!changelog) {
    packageOffenders.push("aucun CHANGELOG.md dans le dossier livre");
  }

  // Le fichier declare dans .pkgmeta sert de corps a la release GitHub, qui
  // refuse au-dela de 125 000 caracteres. La v1.6.13 l'a franchie : CurseForge
  // et Wago avaient bien recu l'archive, seule la release GitHub echouait --
  // une chaine a moitie reussie, qui est le pire des resultats.
  // Un paquet construit n'embarque pas .pkgmeta : la question ne se pose que
  // dans le depot.
  if (fs.existsSync(pkgmeta)) {
    const declared = (fs.readFileSync(pkgmeta, "utf8")
      .match(/manual-changelog:\s*\n\s*filename:\s*(\S+)/) || [])[1];
    if (declared) {
      const notes = entries.find(e => e.name === declared);
      if (!notes) {
        packageOffenders.push(`le .pkgmeta annonce ${declared}, absent du dossier livre`);
      } else {
        const size = fs.statSync(notes.full).size;
        if (size > 125000) {
          packageOffenders.push(
            `${declared} fait ${size} caracteres : GitHub refuse une release au-dela de 125000`);
        }
      }
    }
  }

  // Le README affiche la version en titre. Deux sources de verite divergent
  // toujours : celle du .toc gagne, l'autre doit la suivre.
  const readme = entries.find(e => /^readme\.md$/i.test(e.name));
  if (tocVersion && readme) {
    const firstLine = fs.readFileSync(readme.full, "utf8").split("\n")[0];
    if (firstLine.includes("Cleansive") && !firstLine.includes(tocVersion)) {
      packageOffenders.push(`le README annonce « ${firstLine.trim()} » et le .toc ${tocVersion}`);
    }
  }
}

if (packageOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC archive : le dossier livre n'est pas propre");
  for (const o of packageOffenders) console.log("          " + o);
} else {
  console.log("  ok    archive : licence, changelog, versions accordees, aucun reste de developpement");
}

// ---------------------------------------------------------------------------
// pcall dont personne ne lit le retour
//
// pcall empeche l'erreur Lua, il ne dit pas que l'operation a eu lieu. Un appel
// dont le retour part a la poubelle transforme un refus du client en silence :
// c'est exactement ce qui a masque les 480 refus de mise en forme jusqu'a ce
// qu'on les compte.
// ---------------------------------------------------------------------------
const pcallOffenders = [];
{
  for (const file of fs.readdirSync(addon).filter(f => f.endsWith(".lua")).sort()) {
    const lines = fs.readFileSync(path.join(addon, file), "utf8").split("\n");
    lines.forEach((line, i) => {
      const trimmed = line.trim();
      if (trimmed.startsWith("--") || !/\bpcall\s*\(/.test(trimmed)) return;
      // Le retour est lu s'il est affecte, teste, renvoye, ou combine.
      if (/(local\s+[\w,\s]+=|^[\w.\[\]:]+\s*=|[\w,\s]+\s*=\s*[^=]*|\bif\b|\breturn\b|\band\b|\bor\b|\bnot\b)[^=]*\bpcall\s*\(/.test(trimmed)) return;
      pcallOffenders.push(`${file}:${i + 1} ${trimmed.slice(0, 90)}`);
    });
  }
}

if (pcallOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC pcall : un refus du client part a la poubelle");
  for (const o of pcallOffenders) console.log("          " + o);
} else {
  console.log("  ok    pcall : chaque appel protege lit son resultat");
}

// ---------------------------------------------------------------------------
// Ne jamais aller vivre chez le voisin
//
// La cellule securisee doit rester enfant d'un cadre que Cleansive possede.
// La reparenter dans le header securise d'un autre addon melerait les deux
// arbres de securite : la moindre erreur de l'un fermerait l'autre, et une
// mise a jour du voisin casserait Cleansive sans prevenir. La regle est facile
// a tenir aujourd'hui et facile a oublier le jour ou une integration arrivera.
// ---------------------------------------------------------------------------
const parentOffenders = [];
{
  for (const file of fs.readdirSync(addon).filter(f => f.endsWith(".lua")).sort()) {
    const lines = fs.readFileSync(path.join(addon, file), "utf8").split("\n");
    lines.forEach((line, i) => {
      const trimmed = line.trim();
      if (trimmed.startsWith("--")) return;
      if (/:SetParent\s*\(/.test(trimmed)) {
        parentOffenders.push(`${file}:${i + 1} ${trimmed.slice(0, 90)}`);
      }
      // Un cadre cree avec un parent nomme par une chaine vient forcement
      // d'ailleurs : les cadres de Cleansive sont des variables locales.
      if (/CreateFrame\s*\([^)]*,\s*_G\[/.test(trimmed)) {
        parentOffenders.push(`${file}:${i + 1} ${trimmed.slice(0, 90)}`);
      }
    });
  }
}

if (parentOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC parente : une cellule quitte l'arbre de Cleansive");
  for (const o of parentOffenders) console.log("          " + o);
} else {
  console.log("  ok    parente : aucune cellule ne va vivre dans l'arbre d'un autre addon");
}

// ---------------------------------------------------------------------------
// La chaine de publication
//
// Deux invariants qu'une modification distraite ferait sauter sans bruit : le
// travail de verification ne doit tenir aucun secret de publication, et rien ne
// doit pouvoir publier sans etre passe par lui. Les deux se lisent dans le
// fichier, donc les deux se verifient.
// ---------------------------------------------------------------------------
const ciOffenders = [];
{
  // Ce controle vise le DEPOT, pas l'archive livree : .github en est exclu a
  // dessein. .pkgmeta ne vit qu'a la racine du depot et sert donc a distinguer
  // les deux. Sans cette distinction, valider une archive construite echouait
  // en reprochant l'absence d'un fichier qu'on avait volontairement retire.
  const isRepository = fs.existsSync(path.join(addon, ".pkgmeta"));
  const workflow = path.join(addon, ".github", "workflows", "release.yml");
  if (!isRepository) {
    // Rien a dire : on regarde un paquet, pas un depot.
  } else if (!fs.existsSync(workflow)) {
    ciOffenders.push("aucun workflow de publication a verifier");
  } else {
    const lines = fs.readFileSync(workflow, "utf8").split("\n");
    const jobs = {};
    let current = null;
    for (const line of lines) {
      const header = line.match(/^  ([\w-]+):\s*$/);
      if (header) { current = header[1]; jobs[current] = { needs: false, secrets: false, packager: false }; continue; }
      if (!current) continue;
      if (/^\s*needs:.*\bverify\b/.test(line)) jobs[current].needs = true;
      if (/secrets\./.test(line) && !line.trim().startsWith("#")) jobs[current].secrets = true;
      if (/BigWigsMods\/packager/.test(line)) jobs[current].packager = true;
    }
    if (!jobs.verify) {
      ciOffenders.push("aucun travail nomme verify : rien ne garde la publication");
    } else if (jobs.verify.secrets) {
      ciOffenders.push("le travail verify tient un secret de publication");
    }
    for (const [name, job] of Object.entries(jobs)) {
      if (name === "verify") continue;
      if (!job.packager && !job.secrets) continue;
      if (!job.needs) {
        ciOffenders.push(`le travail ${name} peut publier sans passer par verify`);
      }
    }
  }
}

if (ciOffenders.length) {
  failed += 1;
  console.log("\n  ECHEC publication : la chaine ne protege plus la page de telechargement");
  for (const o of ciOffenders) console.log("          " + o);
} else if (fs.existsSync(path.join(addon, ".pkgmeta"))) {
  console.log("  ok    publication : verify ne tient aucun secret, et rien ne publie sans lui");
} else {
  console.log("  ok    publication : sans objet, ceci est un paquet et non le depot");
}

process.exit(failed > 0 ? 1 : 0);
