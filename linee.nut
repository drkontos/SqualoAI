/*
 * SqualoAI - linee.nut
 * Scelta delle coppie di citta, costruzione di fermate, deposito e prima flotta di bus.
 *
 * Una linea e una tabella:
 *   { a, b,        citta di partenza e arrivo
 *     sa, sb,      StationID delle due fermate
 *     ta, tb,      caselle delle due fermate
 *     dep,         casella del deposito
 *     gr }         gruppo veicoli
 */

class Linee {}

const POP_MINIMA = 500;
const DIST_MIN = 20;
const DIST_MAX = 110;
const DIST_CORTE_PRIME_LINEE = 3;  /* le prime N linee al massimo 60 caselle */
const LINEE_PER_CITTA = 3;
const MESI_ATTESA_COPPIA = 6;

/* Quante linee toccano gia una citta. */
function Linee::LineeInCitta(ai, citta)
{
	local n = 0;
	foreach (l in ai.linee) {
		if (l.a == citta || l.b == citta) n++;
	}
	return n;
}

function Linee::Chiave(a, b)
{
	return (a < b) ? (a + "_" + b) : (b + "_" + a);
}

/*
 * Sceglie la coppia di citta piu promettente. Ritorna [a, b] oppure null.
 * Se con le citta grandi non trova nulla, abbassa la soglia di popolazione.
 */
function Linee::ScegliCoppia(ai)
{
	foreach (soglia in [POP_MINIMA, 300, 150]) {
		local coppia = Linee._ScegliCoppia(ai, soglia);
		if (coppia != null) return coppia;
	}
	return null;
}

function Linee::_ScegliCoppia(ai, pop_min)
{
	local lista = AITownList();
	lista.Valuate(AITown.GetPopulation);
	lista.KeepAboveValue(pop_min);
	lista.Sort(AIList.SORT_BY_VALUE, false);
	lista.KeepTop(60);
	local citta = Util.InArray(lista);
	/* Le prime linee devono costare poco e rendere presto: distanze piu corte. */
	local dist_max = (ai.linee.len() < DIST_CORTE_PRIME_LINEE) ? 60 : DIST_MAX;
	Util.Log("Citta con piu di " + pop_min + " abitanti: " + citta.len(), 2);
	local oggi = Util.Oggi();

	local migliore = null;
	local punteggio_max = 0;
	for (local i = 0; i < citta.len(); i++) {
		local a = citta[i];
		if (Linee.LineeInCitta(ai, a) >= LINEE_PER_CITTA) continue;
		local popA = AITown.GetPopulation(a);
		local locA = AITown.GetLocation(a);
		for (local j = i + 1; j < citta.len(); j++) {
			local b = citta[j];
			if (Linee.LineeInCitta(ai, b) >= LINEE_PER_CITTA) continue;
			local chiave = Linee.Chiave(a, b);
			if (chiave in ai.coppie && ai.coppie[chiave] > oggi) continue;
			local dist = AIMap.DistanceManhattan(locA, AITown.GetLocation(b));
			if (dist < DIST_MIN || dist > dist_max) continue;
			local popB = AITown.GetPopulation(b);
			/* Rende di piu: citta grandi entrambe e distanza maggiore (biglietti piu cari). */
			local punteggio = Util.Min(popA, popB) * dist / 10;
			/* Penalita se l'autorita locale ci odia gia. */
			local me = Util.Me();
			local ra = AITown.GetRating(a, me);
			local rb = AITown.GetRating(b, me);
			if ((ra != AITown.TOWN_RATING_NONE && ra <= AITown.TOWN_RATING_VERY_POOR) ||
			    (rb != AITown.TOWN_RATING_NONE && rb <= AITown.TOWN_RATING_VERY_POOR)) {
				punteggio = punteggio / 3;
			}
			if (punteggio > punteggio_max) {
				punteggio_max = punteggio;
				migliore = [a, b];
			}
		}
	}
	return migliore;
}

/* Blocca una coppia per qualche mese (o per sempre se mesi < 0). */
function Linee::Scarta(ai, a, b, mesi)
{
	local scadenza = (mesi < 0) ? 2000000000 : Util.Oggi() + mesi * 30;
	ai.coppie[Linee.Chiave(a, b)] <- scadenza;
}

/* Se la casella e una strada dritta, ritorna la casella "davanti"; altrimenti null. */
function Linee::Rettilineo(t)
{
	local dx = 1;
	local dy = AIMap.GetMapSizeX();
	local asse_x = AIRoad.AreRoadTilesConnected(t, t + dx) && AIRoad.AreRoadTilesConnected(t, t - dx);
	local asse_y = AIRoad.AreRoadTilesConnected(t, t + dy) && AIRoad.AreRoadTilesConnected(t, t - dy);
	local lato_x = AIRoad.AreRoadTilesConnected(t, t + dx) || AIRoad.AreRoadTilesConnected(t, t - dx);
	local lato_y = AIRoad.AreRoadTilesConnected(t, t + dy) || AIRoad.AreRoadTilesConnected(t, t - dy);
	if (asse_x && !lato_y) return t + dx;
	if (asse_y && !lato_x) return t + dy;
	return null;
}

/* Caselle candidate per una fermata passante in centro citta: array di [casella, davanti]. */
function Linee::Candidati(citta, cargo)
{
	local centro = AITown.GetLocation(citta);
	local raggio = AIStation.GetCoverageRadius(AIStation.STATION_BUS_STOP);
	local tiles = Util.Rettangolo(centro, 8);
	tiles.Valuate(AIRoad.IsRoadTile);
	tiles.KeepValue(1);
	tiles.Valuate(AIRoad.IsRoadStationTile);
	tiles.KeepValue(0);
	tiles.Valuate(AIRoad.IsRoadDepotTile);
	tiles.KeepValue(0);
	tiles.Valuate(AITile.GetSlope);
	tiles.KeepValue(AITile.SLOPE_FLAT);
	tiles.Valuate(AITile.GetCargoAcceptance, cargo, 1, 1, raggio);
	tiles.KeepAboveValue(9);
	tiles.Valuate(AIMap.DistanceManhattan, centro);
	tiles.Sort(AIList.SORT_BY_VALUE, true);

	local risultato = [];
	foreach (t, _ in tiles) {
		if (AIRail.IsLevelCrossingTile(t) || AIBridge.IsBridgeTile(t) || AITunnel.IsTunnelTile(t)) continue;
		local davanti = Linee.Rettilineo(t);
		if (davanti == null) continue;
		risultato.append([t, davanti]);
		if (risultato.len() >= 15) break;
	}
	return risultato;
}

/*
 * Prova a costruire una fermata tra i candidati.
 * Ritorna la casella, oppure -1 (nessun posto) o -2 (l'autorita locale rifiuta).
 */
function Linee::CostruisciFermata(candidati)
{
	local rifiuto = false;
	foreach (c in candidati) {
		if (!Banca.Assicura(3000)) return -1;
		if (AIRoad.BuildDriveThroughRoadStation(c[0], c[1], AIRoad.ROADVEHTYPE_BUS, AIStation.STATION_NEW)) {
			return c[0];
		}
		if (AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) rifiuto = true;
		Util.Log("Fermata non costruita in " + c[0] + ": " + AIError.GetLastErrorString(), 2);
	}
	return rifiuto ? -2 : -1;
}

/* Costruisce un deposito vicino alla casella data. Ritorna la casella o null. */
function Linee::CostruisciDeposito(vicino)
{
	local tiles = Util.Rettangolo(vicino, 6);
	tiles.Valuate(AITile.IsBuildable);
	tiles.KeepValue(1);
	tiles.Valuate(AITile.GetSlope);
	tiles.KeepValue(AITile.SLOPE_FLAT);
	tiles.Valuate(AIMap.DistanceManhattan, vicino);
	tiles.Sort(AIList.SORT_BY_VALUE, true);

	foreach (t, _ in tiles) {
		foreach (d in Util.Direzioni()) {
			local f = t + d;
			if (!AIRoad.IsRoadTile(f)) continue;
			if (AIRoad.IsRoadStationTile(f) || AIRoad.IsRoadDepotTile(f)) continue;
			if (AIRail.IsLevelCrossingTile(f) || AIBridge.IsBridgeTile(f) || AITunnel.IsTunnelTile(f)) continue;
			if (!Banca.Assicura(5000)) return null;
			if (!AIRoad.BuildRoadDepot(t, f)) continue;
			if (!AIRoad.BuildRoad(f, t)) {
				AITile.DemolishTile(t);
				continue;
			}
			return t;
		}
	}
	return null;
}

/* Sceglie il miglior bus disponibile per il cargo. null se nessuno. */
function Linee::ScegliBus(cargo)
{
	local motori = AIEngineList(AIVehicle.VT_ROAD);
	motori.Valuate(AIEngine.IsBuildable);
	motori.KeepValue(1);
	motori.Valuate(AIEngine.GetRoadType);
	motori.KeepValue(AIRoad.GetCurrentRoadType());
	motori.Valuate(function(e, c) {
		return (AIEngine.GetCargoType(e) == c || AIEngine.CanRefitCargo(e, c)) ? 1 : 0;
	}, cargo);
	motori.KeepValue(1);
	if (motori.IsEmpty()) return null;
	motori.Valuate(function(e) {
		return AIEngine.GetCapacity(e) * AIEngine.GetMaxSpeed(e);
	});
	motori.Sort(AIList.SORT_BY_VALUE, false);
	return motori.Begin();
}

/* Stampa nel log perche non si trovano bus: utile quando l'AI resta ferma. */
function Linee::DiagnosiBus(cargo)
{
	local motori = AIEngineList(AIVehicle.VT_ROAD);
	AILog.Info("  Veicoli stradali nel gioco: " + motori.Count());
	motori.Valuate(AIEngine.IsBuildable);
	motori.KeepValue(1);
	AILog.Info("  ...acquistabili: " + motori.Count());
	foreach (e, _ in motori) {
		AILog.Info("    " + AIEngine.GetName(e) + " | tipo strada " + AIEngine.GetRoadType(e) +
		           " | cargo " + AICargo.GetCargoLabel(AIEngine.GetCargoType(e)) +
		           " | rifit passeggeri " + AIEngine.CanRefitCargo(e, cargo));
	}
	AILog.Info("  Tipo strada corrente: " + AIRoad.GetCurrentRoadType());
}

/* Compra un bus per la linea e lo mette in servizio. */
function Linee::AggiungiBus(ai, linea)
{
	if (Util.PostiLiberi(AIVehicle.VT_ROAD) <= 0) return false;  /* limite veicoli raggiunto */
	local motore = Linee.ScegliBus(ai.cargo);
	if (motore == null) {
		Util.Avviso("Nessun bus disponibile per i passeggeri");
		return false;
	}
	if (!Banca.Assicura(AIEngine.GetPrice(motore))) return false;

	local v = AIVehicle.BuildVehicle(linea.dep, motore);
	if (!AIVehicle.IsValidVehicle(v)) {
		Util.Errore("Acquisto bus fallito");
		return false;
	}
	if (AIEngine.GetCargoType(motore) != ai.cargo) AIVehicle.RefitVehicle(v, ai.cargo);

	local esistenti = AIVehicleList_Group(linea.gr);
	esistenti.RemoveItem(v);
	if (!esistenti.IsEmpty()) {
		AIOrder.ShareOrders(v, esistenti.Begin());
	} else {
		AIOrder.AppendOrder(v, linea.ta, AIOrder.OF_NON_STOP_INTERMEDIATE);
		AIOrder.AppendOrder(v, linea.tb, AIOrder.OF_NON_STOP_INTERMEDIATE);
	}
	AIGroup.MoveVehicle(linea.gr, v);
	AIVehicle.StartStopVehicle(v);
	local tot = AIVehicleList_Group(linea.gr).Count();
	Util.Log("Nuovo bus sulla linea " + AITown.GetName(linea.a) + " - " + AITown.GetName(linea.b) + " (ora " + tot + ")", 2);
	return true;
}

/* Prova a costruire una nuova linea completa. Ritorna true se ce l'ha fatta. */
function Linee::CostruisciNuova(ai)
{
	if (ai.cargo == null) {
		AILog.Warning("Nuova linea: nessun cargo passeggeri");
		return false;
	}
	if (Util.PostiLiberi(AIVehicle.VT_ROAD) < 5) return false;  /* niente linee senza posto per i bus */
	if (Linee.ScegliBus(ai.cargo) == null) {
		AILog.Warning("Nuova linea: nessun bus acquistabile (vedi diagnosi all'avvio)");
		return false;
	}
	if (Banca.Disponibile() < 30000) {
		Util.Log("Nuova linea: disponibili solo " + Banca.Disponibile() + ", aspetto", 2);
		return false;
	}

	local coppia = Linee.ScegliCoppia(ai);
	if (coppia == null) {
		AILog.Info("Nuova linea: nessuna coppia di citta valida (" + DIST_MIN + "-" + DIST_MAX + " caselle, almeno 150 abitanti)");
		return false;
	}
	local a = coppia[0];
	local b = coppia[1];
	Util.Log("Valuto linea " + AITown.GetName(a) + " - " + AITown.GetName(b), 2);

	/* 1. Ci sono posti per le fermate? */
	local candA = Linee.Candidati(a, ai.cargo);
	local candB = Linee.Candidati(b, ai.cargo);
	if (candA.len() == 0 || candB.len() == 0) {
		AILog.Info("Nessun posto per le fermate (" + candA.len() + " / " + candB.len() + "), scarto la coppia");
		Linee.Scarta(ai, a, b, -1);
		return false;
	}

	/* 2. Percorso stradale tra i centri */
	local percorso = Strade.Cerca(AITown.GetLocation(a), AITown.GetLocation(b), ai);
	if (percorso == null) {
		Linee.Scarta(ai, a, b, -1);
		return false;
	}

	/* 3. Soldi: strada + fermate + deposito + 2 bus */
	local prezzo_bus = AIEngine.GetPrice(Linee.ScegliBus(ai.cargo));
	local costo = Strade.Stima(percorso) + 15000 + prezzo_bus * 2;
	Util.Log("Costo stimato: " + costo, 2);
	if (costo > Banca.Disponibile() * 6 / 10) {
		AILog.Info("Linea troppo cara rispetto ai fondi (" + Banca.Disponibile() + "), riprovo tra qualche mese");
		Linee.Scarta(ai, a, b, 6);
		return false;
	}
	if (!Banca.Assicura(costo)) {
		Util.Log("Soldi insufficienti, riprovo piu avanti", 1);
		Linee.Scarta(ai, a, b, 3);
		return false;
	}

	/* 4. Strada */
	if (!Strade.Costruisci(percorso)) {
		Linee.Scarta(ai, a, b, MESI_ATTESA_COPPIA);
		return false;
	}

	/* 5. Fermate */
	local ta = Linee.CostruisciFermata(candA);
	if (ta < 0) {
		if (ta == -2) Autorita.Recupera(ai, a);
		Linee.Scarta(ai, a, b, MESI_ATTESA_COPPIA);
		return false;
	}
	local tb = Linee.CostruisciFermata(candB);
	if (tb < 0) {
		if (tb == -2) Autorita.Recupera(ai, b);
		AIRoad.RemoveRoadStation(ta);
		Linee.Scarta(ai, a, b, MESI_ATTESA_COPPIA);
		return false;
	}

	/* 6. Deposito */
	local dep = Linee.CostruisciDeposito(ta);
	if (dep == null) dep = Linee.CostruisciDeposito(tb);
	if (dep == null) {
		Util.Avviso("Nessun deposito possibile, smonto le fermate");
		AIRoad.RemoveRoadStation(ta);
		AIRoad.RemoveRoadStation(tb);
		Linee.Scarta(ai, a, b, -1);
		return false;
	}

	/* 7. Gruppo e bus */
	local gr = AIGroup.CreateGroup(AIVehicle.VT_ROAD, AIGroup.GROUP_INVALID);
	local linea = {
		a = a, b = b,
		sa = AIStation.GetStationID(ta), sb = AIStation.GetStationID(tb),
		ta = ta, tb = tb,
		dep = dep, gr = gr
	};
	if (AIGroup.IsValidGroup(gr)) {
		local nome = AITown.GetName(a) + "-" + AITown.GetName(b);
		if (nome.len() > 30) nome = nome.slice(0, 30);
		AIGroup.SetName(gr, nome);
	}
	ai.linee.append(linea);
	Linee.Scarta(ai, a, b, -1); /* coppia ormai usata */

	Linee.AggiungiBus(ai, linea);
	Linee.AggiungiBus(ai, linea);
	AILog.Info("+ Linea bus: " + AITown.GetName(a) + " - " + AITown.GetName(b) + " (" + AIMap.DistanceManhattan(ta, tb) + " caselle)");
	return true;
}

/* Dopo un caricamento, ricostruisce le linee dai dati salvati scartando quelle non piu valide. */
function Linee::Ripristina(ai, dati)
{
	if (dati == null) return;
	if ("coppie" in dati) {
		foreach (k, v in dati.coppie) ai.coppie[k] <- v;
	}
	if (!("linee" in dati)) return;
	foreach (l in dati.linee) {
		if (!AIStation.IsValidStation(l.sa) || !AIStation.IsValidStation(l.sb)) continue;
		if (!AIRoad.IsRoadDepotTile(l.dep)) continue;
		if (!AIGroup.IsValidGroup(l.gr)) continue;
		ai.linee.append(l);
	}
	AILog.Info("Ripristinate " + ai.linee.len() + " linee");
}
