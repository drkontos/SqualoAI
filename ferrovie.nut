/*
 * SqualoAI - ferrovie.nut
 * Treni merci semplici: due stazioni terminali da 1 binario, una linea a binario unico,
 * UN solo treno per linea (cosi non servono segnali e non ci sono scontri).
 * Usa la libreria ufficiale "pathfinder.rail" v1.
 *
 * Una rotta treno e una tabella:
 *   { src, dst, cargo,   industrie e merce
 *     sa, sb,            StationID delle due stazioni
 *     ta, tb,            casella base delle due stazioni
 *     dep,               casella del deposito
 *     rt,                RailType usato
 *     gr }               gruppo
 */

class Ferrovie {}

const TRENO_LUNGHEZZA = 4;     /* caselle di banchina */
const TRENO_DIST_MIN = 40;
const TRENO_DIST_MAX = 150;
const TRENO_PROD_MIN = 60;
const TRENO_CASSA_MIN = 250000;

function Ferrovie::CassaMinima() { return TRENO_CASSA_MIN; }

/* Pathfinder ferroviario pesato (stessa idea di quello stradale: piu veloce, percorso quasi ottimo). */
class BinarioVeloce extends RailPathFinder {}

function BinarioVeloce::_Estimate(cur_tile, cur_direction, goal_tiles, self)
{
	return ::RailPathFinder._Estimate(cur_tile, cur_direction, goal_tiles, self) * 13 / 10;
}

/*
 * Miglior combinazione tipo di binario + locomotiva + vagone per la merce.
 * Ritorna { rt, loco, vagone } oppure null.
 */
function Ferrovie::ScegliTreno(cargo, solo_rt = -1)
{
	local migliore = null, velocita_max = 0;
	foreach (rt, _ in AIRailTypeList()) {
		if (!AIRail.IsRailTypeAvailable(rt)) continue;
		if (solo_rt != -1 && rt != solo_rt) continue;

		local vagoni = AIEngineList(AIVehicle.VT_RAIL);
		vagoni.Valuate(AIEngine.IsBuildable);
		vagoni.KeepValue(1);
		vagoni.Valuate(AIEngine.IsWagon);
		vagoni.KeepValue(1);
		vagoni.Valuate(AIEngine.CanRunOnRail, rt);
		vagoni.KeepValue(1);
		vagoni.Valuate(function(e, c) {
			return (AIEngine.GetCargoType(e) == c || AIEngine.CanRefitCargo(e, c)) ? 1 : 0;
		}, cargo);
		vagoni.KeepValue(1);
		if (vagoni.IsEmpty()) continue;
		vagoni.Valuate(AIEngine.GetCapacity);
		vagoni.Sort(AIList.SORT_BY_VALUE, false);

		local loco = AIEngineList(AIVehicle.VT_RAIL);
		loco.Valuate(AIEngine.IsBuildable);
		loco.KeepValue(1);
		loco.Valuate(AIEngine.IsWagon);
		loco.KeepValue(0);
		loco.Valuate(AIEngine.HasPowerOnRail, rt);
		loco.KeepValue(1);
		loco.Valuate(AIEngine.GetPower);
		loco.KeepAboveValue(0);
		if (loco.IsEmpty()) continue;
		loco.Valuate(AIEngine.GetMaxSpeed);
		loco.Sort(AIList.SORT_BY_VALUE, false);

		local v = loco.GetValue(loco.Begin());
		if (v > velocita_max) {
			velocita_max = v;
			migliore = { rt = rt, loco = loco.Begin(), vagone = vagoni.Begin() };
		}
	}
	return migliore;
}

function Ferrovie::FonteUsata(ai, src, cargo)
{
	return Merci.FonteUsata(ai, src, cargo);  /* controlla sia camion sia treni */
}

function Ferrovie::Chiave(src, dst, cargo) { return "t" + src + "_" + dst + "_" + cargo; }

function Ferrovie::Scarta(ai, src, dst, cargo, mesi)
{
	ai.coppie[Ferrovie.Chiave(src, dst, cargo)] <- (mesi < 0) ? 2000000000 : Util.Oggi() + mesi * 30;
}

/* Come per i camion, ma distanze piu lunghe e fonti piu grandi. */
function Ferrovie::ScegliRotta(ai)
{
	local oggi = Util.Oggi();
	local migliore = null, punteggio_max = 0;
	foreach (c in Merci.CargoTreno()) {
		local fonti = AIIndustryList_CargoProducing(c);
		fonti.Valuate(AIIndustry.GetLastMonthProduction, c);
		fonti.KeepAboveValue(TRENO_PROD_MIN - 1);
		fonti.Valuate(AIIndustry.GetLastMonthTransportedPercentage, c);
		fonti.KeepBelowValue(MERCI_TRASP_MAX);
		foreach (src in Util.InArray(fonti)) {
			if (Ferrovie.FonteUsata(ai, src, c)) continue;
			local prod = AIIndustry.GetLastMonthProduction(src, c);
			local dest = AIIndustryList_CargoAccepting(c);
			dest.Valuate(AIIndustry.GetDistanceManhattanToTile, AIIndustry.GetLocation(src));
			dest.KeepAboveValue(TRENO_DIST_MIN - 1);
			dest.KeepBelowValue(TRENO_DIST_MAX + 1);
			foreach (dst, dist in dest) {
				local k = Ferrovie.Chiave(src, dst, c);
				if (k in ai.coppie && ai.coppie[k] > oggi) continue;
				local p = AICargo.GetCargoIncome(c, dist, dist / 3 + 5) * prod;
				if (p > punteggio_max) {
					punteggio_max = p;
					migliore = { src = src, dst = dst, cargo = c };
				}
			}
		}
	}
	return migliore;
}

function Ferrovie::_ProvaStazione(t, dir)
{
	local test = AITestMode();
	return AIRail.BuildRailStation(t, dir, 1, TRENO_LUNGHEZZA, AIStation.STATION_NEW);
}

/*
 * Stazione terminale da 1 binario vicino all'industria, con l'ingresso dal lato verso "verso".
 * Ritorna { tile, fine, ingresso } (fine = ultima casella di banchina, ingresso = casella fuori)
 * oppure null.
 */
function Ferrovie::CostruisciStazione(ind, cargo, presa, verso)
{
	local raggio = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
	local tiles = presa ? AITileList_IndustryProducing(ind, raggio) : AITileList_IndustryAccepting(ind, raggio);
	tiles.Valuate(AITile.IsBuildable);
	tiles.KeepValue(1);
	tiles.Valuate(AIMap.DistanceManhattan, verso);
	tiles.Sort(AIList.SORT_BY_VALUE, true);

	local dx = 1, dy = AIMap.GetMapSizeX();
	local prove = 0;
	foreach (t, _ in tiles) {
		if (prove++ >= 40) break;
		foreach (dir in [AIRail.RAILTRACK_NE_SW, AIRail.RAILTRACK_NW_SE]) {
			local passo = (dir == AIRail.RAILTRACK_NE_SW) ? dx : dy;
			local w = (dir == AIRail.RAILTRACK_NE_SW) ? TRENO_LUNGHEZZA : 1;
			local h = (dir == AIRail.RAILTRACK_NE_SW) ? 1 : TRENO_LUNGHEZZA;
			if (presa) {
				if (AITile.GetCargoProduction(t, cargo, w, h, raggio) < 1) continue;
			} else {
				if (AITile.GetCargoAcceptance(t, cargo, w, h, raggio) < 8) continue;
			}
			/* le due estremita: scegli quella piu vicina alla destinazione */
			local fine1 = t, ingr1 = t - passo;
			local fine2 = t + passo * (TRENO_LUNGHEZZA - 1), ingr2 = t + passo * TRENO_LUNGHEZZA;
			local fine = fine1, ingresso = ingr1;
			if (AIMap.DistanceManhattan(ingr2, verso) < AIMap.DistanceManhattan(ingr1, verso)) {
				fine = fine2;
				ingresso = ingr2;
			}
			if (!AITile.IsBuildable(ingresso)) continue;
			if (!Ferrovie._ProvaStazione(t, dir)) continue;
			if (!Banca.Assicura(20000)) return null;
			if (!AIRail.BuildRailStation(t, dir, 1, TRENO_LUNGHEZZA, AIStation.STATION_NEW)) continue;
			return { tile = t, ultima = fine2, fine = fine, ingresso = ingresso };
		}
	}
	return null;
}

/* Cerca il percorso dei binari. Ritorna un array di caselle (con le due estremita di banchina) o null. */
function Ferrovie::Cerca(A, B, ai)
{
	local pf = BinarioVeloce();
	pf.cost.max_bridge_length = 10;
	pf.cost.max_tunnel_length = 10;
	pf.cost.max_cost = AIMap.DistanceManhattan(A.ingresso, B.ingresso) * 100 * 3 + 10000;
	pf.InitializePath([[A.ingresso, A.fine]], [[B.ingresso, B.fine]]);
	local inizio = Util.Oggi();
	local percorso = false, giri = 0;
	while (percorso == false && giri < 60) {
		percorso = pf.FindPath(5000);
		giri++;
		if (ai != null) ai.Manutenzione();
		AIController.Sleep(1);
	}
	if (percorso == false || percorso == null) {
		AILog.Info("Treni: nessun percorso per i binari (" + (Util.Oggi() - inizio) + " giorni)");
		return null;
	}
	local L = [];
	while (percorso != null) {
		L.append(percorso.GetTile());
		percorso = percorso.GetParent();
	}
	return L;
}

/* Costruisce (o stima, in modalita test) i binari lungo l'array di caselle. Ritorna il numero di errori. */
function Ferrovie::_Posa(L, reale)
{
	local errori = 0;
	for (local i = 1; i < L.len() - 1; i++) {
		if (AIMap.DistanceManhattan(L[i], L[i + 1]) > 1) {
			if (AITunnel.GetOtherTunnelEnd(L[i]) == L[i + 1]) {
				if (!AITunnel.BuildTunnel(AIVehicle.VT_RAIL, L[i])) errori++;
			} else {
				local ponti = AIBridgeList_Length(AIMap.DistanceManhattan(L[i], L[i + 1]) + 1);
				ponti.Valuate(AIBridge.GetMaxSpeed);
				ponti.Sort(AIList.SORT_BY_VALUE, false);
				if (ponti.IsEmpty() || !AIBridge.BuildBridge(AIVehicle.VT_RAIL, ponti.Begin(), L[i], L[i + 1])) errori++;
			}
		} else if (AIMap.DistanceManhattan(L[i - 1], L[i]) > 1) {
			/* L[i] e la testa d'arrivo di un ponte o galleria: gia costruita */
		} else {
			local ok = false;
			for (local k = 0; k < 5 && !ok; k++) {
				if (AIRail.BuildRail(L[i - 1], L[i], L[i + 1])) ok = true;
				else if (AIError.GetLastError() == AIError.ERR_ALREADY_BUILT) ok = true;
				else if (reale && AIError.GetLastError() == AIError.ERR_VEHICLE_IN_THE_WAY) AIController.Sleep(10);
				else break;
			}
			if (!ok) {
				errori++;
				if (reale) Util.Errore("Treni: binario non posato");
			}
		}
	}
	return errori;
}

function Ferrovie::Stima(L)
{
	local test = AITestMode();
	local conto = AIAccounting();
	Ferrovie._Posa(L, false);
	return conto.GetCosts();
}

/* Deposito accanto alla linea vicino alla stazione A (L e ordinato da B verso A). */
function Ferrovie::CostruisciDeposito(L)
{
	local n = L.len();
	for (local i = n - 2; i >= 1 && i >= n - 12; i--) {
		local p = L[i], verso_a = L[i + 1], altro = L[i - 1];
		if (AIMap.DistanceManhattan(p, verso_a) != 1 || AIMap.DistanceManhattan(p, altro) != 1) continue;
		if (p - verso_a != altro - p) continue;  /* solo tratti dritti */
		local perp = (Util.Abs(p - verso_a) == 1) ? AIMap.GetMapSizeX() : 1;
		foreach (d in [p + perp, p - perp]) {
			if (!AITile.IsBuildable(d)) continue;
			if (!AIRail.BuildRailDepot(d, p)) continue;
			if (AIRail.BuildRail(d, p, verso_a)) return d;
			AITile.DemolishTile(d);
		}
	}
	return null;
}

/* Compone un treno: locomotiva + vagoni finche ci stanno nella banchina. */
function Ferrovie::CompraTreno(ai, r)
{
	if (Util.PostiLiberi(AIVehicle.VT_RAIL) <= 0) return false;  /* limite treni raggiunto */
	local info = Ferrovie.ScegliTreno(r.cargo, r.rt);
	if (info == null) {
		AILog.Warning("Treni: nessun treno adatto per " + AICargo.GetCargoLabel(r.cargo));
		return false;
	}
	AIRail.SetCurrentRailType(r.rt);
	if (!Banca.Assicura(AIEngine.GetPrice(info.loco) + AIEngine.GetPrice(info.vagone) * 6)) return false;
	local loco = AIVehicle.BuildVehicle(r.dep, info.loco);
	if (!AIVehicle.IsValidVehicle(loco)) {
		Util.Errore("Treni: locomotiva non acquistata");
		return false;
	}
	local max_len = TRENO_LUNGHEZZA * 16;
	local lun = AIVehicle.GetLength(loco);
	for (local i = 0; i < 20; i++) {
		local w = AIVehicle.BuildVehicle(r.dep, info.vagone);
		if (!AIVehicle.IsValidVehicle(w)) break;
		if (AIEngine.GetCargoType(info.vagone) != r.cargo) AIVehicle.RefitVehicle(w, r.cargo);
		local lw = AIVehicle.GetLength(w);
		if (lun + lw > max_len || !AIVehicle.MoveWagon(w, 0, loco, AIVehicle.GetNumWagons(loco) - 1)) {
			AIVehicle.SellVehicle(w);
			break;
		}
		lun += lw;
	}
	if (AIVehicle.GetNumWagons(loco) < 2) {
		AILog.Warning("Treni: impossibile agganciare vagoni alla locomotiva");
		AIVehicle.SellVehicle(loco);
		return false;
	}
	AIOrder.AppendOrder(loco, r.ta, AIOrder.OF_FULL_LOAD_ANY);
	AIOrder.AppendOrder(loco, r.tb, AIOrder.OF_NONE);
	AIGroup.MoveVehicle(r.gr, loco);
	AIVehicle.StartStopVehicle(loco);
	AILog.Info("Treno in servizio: " + AIEngine.GetName(info.loco) + " + " + (AIVehicle.GetNumWagons(loco) - 1) + " vagoni");
	return true;
}

function Ferrovie::Nome(r)
{
	return AIIndustry.GetName(r.src) + " -> " + AIIndustry.GetName(r.dst);
}

function Ferrovie::CostruisciNuova(ai)
{
	if (Util.PostiLiberi(AIVehicle.VT_RAIL) < 1) return false;
	if (Banca.Disponibile() < TRENO_CASSA_MIN) return false;
	local scelta = Ferrovie.ScegliRotta(ai);
	if (scelta == null) {
		Util.Log("Treni: nessuna rotta valida", 2);
		return false;
	}
	local info = Ferrovie.ScegliTreno(scelta.cargo);
	if (info == null) {
		Ferrovie.Scarta(ai, scelta.src, scelta.dst, scelta.cargo, 12);
		return false;
	}
	local src = scelta.src, dst = scelta.dst, c = scelta.cargo;
	AIRail.SetCurrentRailType(info.rt);
	Util.Log("Valuto treno " + AICargo.GetCargoLabel(c) + ": " + AIIndustry.GetName(src) + " -> " + AIIndustry.GetName(dst), 1);

	local A = Ferrovie.CostruisciStazione(src, c, true, AIIndustry.GetLocation(dst));
	if (A == null) {
		AILog.Info("Treni: nessun posto per la stazione di carico");
		Ferrovie.Scarta(ai, src, dst, c, -1);
		return false;
	}
	local B = Ferrovie.CostruisciStazione(dst, c, false, AIIndustry.GetLocation(src));
	if (B == null) {
		AILog.Info("Treni: nessun posto per la stazione di scarico");
		AIRail.RemoveRailStationTileRectangle(A.tile, A.ultima, false);
		Ferrovie.Scarta(ai, src, dst, c, -1);
		return false;
	}

	local L = Ferrovie.Cerca(A, B, ai);
	local fallita = (L == null);
	if (!fallita) {
		local costo = Ferrovie.Stima(L) + AIEngine.GetPrice(info.loco) + AIEngine.GetPrice(info.vagone) * 8 + 20000;
		Util.Log("Treni: costo stimato " + costo, 1);
		if (costo > Banca.Disponibile() * 6 / 10 || !Banca.Assicura(costo)) {
			AILog.Info("Treni: linea troppo cara per ora (" + costo + ")");
			fallita = true;
			Ferrovie.Scarta(ai, src, dst, c, 6);
		} else if (Ferrovie._Posa(L, true) > 0) {
			AILog.Warning("Treni: binari incompleti, linea abbandonata");
			fallita = true;
			Ferrovie.Scarta(ai, src, dst, c, -1);
		}
	} else {
		Ferrovie.Scarta(ai, src, dst, c, -1);
	}
	if (fallita) {
		AIRail.RemoveRailStationTileRectangle(A.tile, A.ultima, false);
		AIRail.RemoveRailStationTileRectangle(B.tile, B.ultima, false);
		return false;
	}

	local dep = Ferrovie.CostruisciDeposito(L);
	if (dep == null) {
		AILog.Warning("Treni: nessun posto per il deposito, linea abbandonata (binari restano)");
		Ferrovie.Scarta(ai, src, dst, c, -1);
		return false;
	}

	local gr = AIGroup.CreateGroup(AIVehicle.VT_RAIL, AIGroup.GROUP_INVALID);
	local r = {
		src = src, dst = dst, cargo = c,
		sa = AIStation.GetStationID(A.tile), sb = AIStation.GetStationID(B.tile),
		ta = A.tile, tb = B.tile, dep = dep, rt = info.rt, gr = gr
	};
	if (AIGroup.IsValidGroup(gr)) {
		local nome = "Treno " + AICargo.GetCargoLabel(c) + " " + AIIndustry.GetName(src);
		if (nome.len() > 30) nome = nome.slice(0, 30);
		AIGroup.SetName(gr, nome);
	}
	ai.rotte_treni.append(r);
	Ferrovie.Scarta(ai, src, dst, c, -1);
	Ferrovie.CompraTreno(ai, r);
	AILog.Info("+ Ferrovia " + AICargo.GetCargoLabel(c) + ": " + Ferrovie.Nome(r) + " (" + (L.len() - 2) + " caselle di binario)");
	return true;
}

/* Una volta al mese: un treno per linea, chiusura se un'industria sparisce. */
function Ferrovie::Mensile(ai)
{
	local restano = [];
	foreach (r in ai.rotte_treni) {
		local treni = AIVehicleList_Group(r.gr);
		foreach (v, _ in ai.da_vendere) if (treni.HasItem(v)) treni.RemoveItem(v);
		if (!AIIndustry.IsValidIndustry(r.src) || !AIIndustry.IsValidIndustry(r.dst) ||
		    !AIStation.IsValidStation(r.sa) || !AIStation.IsValidStation(r.sb)) {
			foreach (v, _ in treni) if (AIVehicle.SendVehicleToDepot(v)) ai.da_vendere[v] <- true;
			AILog.Warning("Ferrovia chiusa (industria o stazione sparita): " + AICargo.GetCargoLabel(r.cargo));
			continue;
		}
		restano.append(r);
		if (treni.Count() == 0) Ferrovie.CompraTreno(ai, r);
	}
	ai.rotte_treni = restano;
}

function Ferrovie::Ripristina(ai, dati)
{
	if (dati == null || !("rotte_treni" in dati)) return;
	foreach (r in dati.rotte_treni) {
		if (!AIStation.IsValidStation(r.sa) || !AIStation.IsValidStation(r.sb)) continue;
		if (!AIGroup.IsValidGroup(r.gr)) continue;
		ai.rotte_treni.append(r);
	}
	AILog.Info("Ripristinate " + ai.rotte_treni.len() + " ferrovie");
}
