// NAME: Island Queue
// AUTHOR: gamecat
// DESCRIPTION: Schickt vorherige/aktuelle/naechste Titel der Spotify-Queue per
//              WebSocket an die Dynamic-Island-Shell (ws://127.0.0.1:28199).
//              MPRIS kennt keine Queue, darum dieser Umweg.

/// <reference path="../globals.d.ts" />

(function IslandQueue() {
	if (!Spicetify?.Player?.addEventListener || !Spicetify.Queue) {
		setTimeout(IslandQueue, 500);
		return;
	}

	const URL = "ws://127.0.0.1:28199";
	const DEPTH_PREV = 5; // Titel zurueck
	const DEPTH_NEXT = 30; // Titel voraus (aufklappbare Warteschlange)
	const IMAGE = "https://i.scdn.co/image/";

	let ws = null;
	let retry = 2000;
	let lastSent = "";

	// spotify:image:<id> → https://i.scdn.co/image/<id>; lokale Dateien haben kein Cover
	const image = (meta) => {
		const raw = meta.image_url || meta.image_large_url || meta.image_xlarge_url || meta.image_small_url || "";
		if (raw.startsWith("spotify:image:")) return IMAGE + raw.slice(14);
		return raw.startsWith("https://") ? raw : "";
	};

	const artists = (meta) => {
		let out = meta.artist_name || "";
		for (let i = 1; meta[`artist_name:${i}`]; i++) out += `, ${meta[`artist_name:${i}`]}`;
		return out || meta.album_title || "";
	};

	// Trenner, Werbung und entfernte Eintraege tauchen in der Queue mit auf
	const usable = (t) =>
		t?.uri && !t.uri.startsWith("spotify:delimiter") && !t.uri.startsWith("spotify:ad:") && !t.removed?.length && t.metadata?.title;

	const pack = (t) => ({
		uri: t.uri,
		uid: t.uid || "",
		title: t.metadata.title,
		artist: artists(t.metadata),
		album: t.metadata.album_title || "",
		art: image(t.metadata),
		queued: t.provider === "queue",
	});

	// Queue-Eintraege kommen je nach Quelle als ProvidedTrack oder mit contextTrack-Huelle
	const unwrap = (t) => t?.contextTrack ?? t;

	// Spicetify.Queue ist nur ein Getter auf PlayerAPI._queue._state; der ist bis zum
	// ersten Queue-Event leer, darum zusaetzlich die internen Rohlisten (wie shuffle+).
	function lists() {
		const pq = Spicetify.Player.origin?._queue ?? Spicetify.Platform?.PlayerAPI?._queue;
		const q = Spicetify.Queue;
		const state = pq?._queueState;
		let next = q?.nextTracks ?? [];
		if (!next.length && state) next = [...(state.queued ?? []), ...(state.nextUp ?? [])];
		let prev = q?.prevTracks ?? [];
		if (!prev.length) prev = pq?._queue?.prevTracks ?? [];
		return { current: q?.track ?? state?.current ?? Spicetify.Player.data?.item, next, prev };
	}

	function snapshot() {
		const { current, next, prev } = lists();
		const cur = unwrap(current);
		return {
			type: "queue",
			current: usable(cur) ? pack(cur) : null,
			// prevTracks ist chronologisch, der direkte Vorgaenger steht am Ende
			prev: prev.map(unwrap).filter(usable).slice(-DEPTH_PREV).reverse().map(pack),
			next: next.map(unwrap).filter(usable).slice(0, DEPTH_NEXT).map(pack),
		};
	}

	function send(force = false) {
		if (ws?.readyState !== WebSocket.OPEN) return;
		const json = JSON.stringify(snapshot());
		if (!force && json === lastSent) return;
		lastSent = json;
		ws.send(json);
	}

	function connect() {
		try {
			ws = new WebSocket(URL);
		} catch {
			return schedule();
		}
		ws.onopen = () => {
			retry = 2000;
			send(true);
		};
		ws.onmessage = (ev) => {
			let msg;
			try {
				msg = JSON.parse(ev.data);
			} catch {
				return;
			}
			if (msg.cmd === "refresh") send(true);
			else if (msg.cmd === "skip") skip(msg);
			else if (msg.cmd === "lyrics") lyrics();
			else if (msg.cmd === "play") play(msg);
			else if (msg.cmd === "introspect") introspect();
			else if (msg.cmd === "library") library();
		};
		ws.onclose = schedule;
		ws.onerror = () => ws?.close();
	}

	// Zu einem Titel der Warteschlange springen: Spotifys PlayerAPI.skipTo,
	// sonst so oft "weiter", bis er dran ist
	async function skip({ uri, uid, index }) {
		const api = Spicetify.Platform?.PlayerAPI;
		try {
			if (api?.skipTo) {
				await api.skipTo({ uri, uid });
				return;
			}
		} catch (e) {
			console.warn("[islandQueue] skipTo:", e);
		}
		for (let i = 0; i <= index; i++) {
			await Spicetify.Player.next();
			await new Promise((r) => setTimeout(r, 120));
		}
	}

	// Songtext ueber denselben Weg wie Spotifys eigene Lyrics-Ansicht.
	// Antwort immer schicken (auch leer), dann faellt die Shell sofort auf
	// lrclib zurueck statt auf ihren Timeout zu warten.
	async function lyrics() {
		const item = Spicetify.Player.data?.item;
		const uri = item?.uri || "";
		const title = item?.metadata?.title || item?.name || "";
		const answer = { type: "lyrics", uri, title, synced: false, lines: [] };
		const id = uri.startsWith("spotify:track:") ? uri.slice(14) : "";
		if (id) {
			try {
				const res = await Spicetify.CosmosAsync.get(
					`https://spclient.wg.spotify.com/color-lyrics/v2/track/${id}?format=json&vocalRemoval=false&market=from_token`,
				);
				const l = res?.lyrics;
				if (l?.lines?.length) {
					answer.synced = l.syncType === "LINE_SYNCED";
					answer.lines = l.lines.map((x) => ({
						t: answer.synced ? Number(x.startTimeMs) : -1,
						text: x.words === "♪" ? "♪" : x.words || "",
					}));
				}
			} catch (e) {
				// 404 = Spotify hat keinen Text
			}
		}
		if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify(answer));
	}

	// Suchen und abspielen (fuer lokale Clients ueber die Shell, z. B. Sprachsteuerung).
	// Playlists zuerst in der eigenen Bibliothek (auch private, unscharf nach Namen), "liked"/
	// "lieblings…" = Lieblingssongs; sonst erster Treffer der Spotify-Suche. Antwort immer schicken.
	const norm = (t) => (t || "").toLowerCase().normalize("NFKD").replace(/[^\p{L}\p{N} ]/gu, " ").replace(/\b(playlist|my|meine?n?|die|the)\b/g, " ").replace(/\s+/g, " ").trim();

	// Ersten Eintrag mit passender URI irgendwo in einer (GraphQL-)Antwort finden – Spotify baut die
	// Struktur je Version um, die URIs bleiben gleich.
	function findEntities(obj, prefix, out = [], seen = new Set()) {
		if (!obj || typeof obj !== "object" || seen.has(obj) || out.length > 30) return out;
		seen.add(obj);
		if (typeof obj.uri === "string" && obj.uri.startsWith(prefix) && !out.some((o) => o.uri === obj.uri)) out.push(obj);
		for (const v of Array.isArray(obj) ? obj : Object.values(obj)) findEntities(v, prefix, out, seen);
		return out;
	}

	const entityName = (d) => d?.name || d?.profile?.name || d?.data?.name || "";
	const entityArtists = (d) => (d?.artists?.items || d?.albumOfTrack?.artists?.items || [])
		.map((a) => a?.profile?.name).filter(Boolean).join(", ") || d?.ownerV2?.data?.name || "";

	async function ownPlaylists() {
		// Interne Bibliothek (die Web-API ist aus dem Client heraus blockiert)
		const lib = Spicetify.Platform?.LibraryAPI;
		if (lib?.getContents) {
			const res = await lib.getContents({ limit: 500, offset: 0, filters: ["Playlists"] }).catch(() => null)
				|| await lib.getContents({ limit: 500 }).catch(() => null);
			const found = findEntities(res, "spotify:playlist:");
			if (found.length) return found.map((p) => ({ uri: p.uri, name: entityName(p), owner: p.owner }));
		}
		const out = [];
		let url = "https://api.spotify.com/v1/me/playlists?limit=50";
		for (let i = 0; url && i < 6; i++) {
			const res = await Spicetify.CosmosAsync.get(url);
			out.push(...(res?.items || []).filter(Boolean));
			url = res?.next;
		}
		return out;
	}

	// Suche wie der Client selbst (GraphQL searchDesktop); REST ueber CosmosAsync nur als Rueckfall.
	// Liefert {uri, name, artist} oder null; Fehler landen in debug.
	async function search(query, type, debug) {
		const gql = Spicetify.GraphQL;
		const defs = gql?.Definitions || {};
		// the operation name differs between Spotify versions: take the first that exists
		const name = ["searchDesktop", "searchTopResultsList", "searchTracks", "searchModalResults"].find((n) => defs[n])
			|| Object.keys(defs).find((n) => /^search/i.test(n));
		const def = name ? defs[name] : null;
		if (def) {
			try {
				const res = await gql.Request(def, {
					searchTerm: query, offset: 0, limit: 10, numberOfTopResults: 5,
					includeAudiobooks: false, includeArtistHasConcertsField: false, includePreReleases: false,
					includeLocalConcertsField: false, includeAuthors: false,
				});
				const hit = findEntities(res?.data ?? res, `spotify:${type}:`)[0];
				if (hit) return { uri: hit.uri, name: entityName(hit), artist: entityArtists(hit) };
				const v2 = res?.data?.searchV2;
				debug.push("graphql " + name + ": no " + type + " (" + Object.keys(v2 || res?.data || res || {}).slice(0, 8).join(",") + ")");
			} catch (e) {
				debug.push("graphql: " + String(e?.message || e));
			}
		} else debug.push("graphql: no search definition");
		try {
			const res = await Spicetify.CosmosAsync.get(
				`https://api.spotify.com/v1/search?q=${encodeURIComponent(query)}&type=${type}&limit=1`,
			);
			const hit = res?.[`${type}s`]?.items?.find(Boolean);
			if (hit?.uri) return { uri: hit.uri, name: hit.name || "", artist: (hit.artists || []).map((a) => a.name).join(", ") || hit.owner?.display_name || "" };
			debug.push("rest: " + (res?.error?.message || res?.message || res?.code || "empty"));
		} catch (e) {
			debug.push("rest: " + String(e?.message || e));
		}
		return null;
	}

	// Welche Such-Werkzeuge bietet diese Spotify-Version? (Fehlersuche)
	function introspect() {
		const defs = Object.keys(Spicetify.GraphQL?.Definitions || {});
		const answer = {
			type: "introspect_result",
			graphql: defs.filter((n) => /search/i.test(n)),
			graphqlCount: defs.length,
			platform: Object.keys(Spicetify.Platform || {}).filter((n) => /search|library|playlist/i.test(n)),
			version: Spicetify.Platform?.version || "",
		};
		if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify(answer));
	}

	// Eigene Playlists auflisten (fuer "welche Playlists habe ich?")
	async function library() {
		const answer = { type: "library_result", playlists: [] };
		try {
			answer.playlists = (await ownPlaylists()).map((p) => ({
				name: p.name,
				owner: p.owner?.display_name || p.owner?.name || (typeof p.owner === "string" ? p.owner : ""),
			}));
		} catch (e) {
			answer.error = String(e?.message || e);
		}
		if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify(answer));
	}

	async function play({ query = "", kind = "track" }) {
		const types = ["track", "artist", "album", "playlist"];
		const type = types.includes(kind) ? kind : "track";
		const answer = { type: "play_result", ok: false, query, kind: type };
		const debug = [];
		const done = (uri, title, artist = "", source = "") => Object.assign(answer, { ok: true, uri, title, artist, source });
		try {
			const q = norm(query);
			if (/\b(liked|lieblings\w*|favorit\w*|gespeichert\w*)\b/.test(q)) {
				await Spicetify.Player.playUri(`spotify:user:${Spicetify.Platform?.username}:collection`);
				done("collection", "Liked Songs", "", "library");
			} else if (type === "playlist") {
				let mine = [];
				try {
					mine = await ownPlaylists();
				} catch (e) {
					debug.push("library: " + String(e?.message || e));
				}
				const hit = mine.find((p) => norm(p.name) === q) || mine.find((p) => norm(p.name).includes(q))
					|| mine.find((p) => q.includes(norm(p.name)) && norm(p.name).length > 2);
				if (hit) {
					await Spicetify.Player.playUri(hit.uri);
					done(hit.uri, hit.name, hit.owner?.display_name || hit.owner?.name || "", "library");
				} else if (mine.length) answer.yourPlaylists = mine.map((p) => p.name).slice(0, 40);
			}
			if (!answer.ok) {
				const hit = await search(query, type, debug);
				if (hit) {
					await Spicetify.Player.playUri(hit.uri);
					done(hit.uri, hit.name, hit.artist, "search");
				} else answer.error = "no result";
			}
		} catch (e) {
			answer.error = String(e?.message || e);
		}
		if (debug.length) answer.debug = debug;
		if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify(answer));
	}

	// Shell aus → leise mit wachsendem Abstand (max. 30 s) neu versuchen
	function schedule() {
		ws = null;
		setTimeout(connect, retry);
		retry = Math.min(retry * 1.5, 30000);
	}

	Spicetify.Player.addEventListener("songchange", () => setTimeout(send, 300));
	// Queue-Aenderungen ohne Titelwechsel (Hinzufuegen, Umsortieren) melden sich ueber "update"
	Spicetify.Player.origin?._events?.addListener?.("update", () => send());
	// Sicherheitsnetz; send() vergleicht und schickt nur bei Aenderung
	setInterval(send, 3000);

	connect();
})();
