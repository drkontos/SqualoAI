/*
 * SqualoAI - merci.nut
 * Rotte camion da industria a industria (carbone, legname, minerali, ...).
 *
 * Una rotta merci e una tabella:
 *   { src, dst,      industria che produce e industria che accetta
 *     cargo,         CargoType trasportato
 *     sa, sb,        StationID delle fermate camion (carico / scarico)
 *     ta, tb,        caselle delle fermate
 *     dep,           casella del deposito
 *     gr }           gruppo veicoli
 */

class Merci {}

const MERCI_PROD_MIN = 30;          /* produzione mensile minima della fonte */
const MERCI_TRASP_MAX = 50;         /* % gia trasportata oltre cui la fonte non interessa */
const MERCI_DIST_MIN = 15;
const MERCI_DIST_MAX = 80;
const MERCI_FONTI_PER_CARGO = 25;   /* fonti valutate per ogni tipo di merce */
const MERCI_MAX_CAMION = 10;

/* Tipi di merce trasportabili con camion (esclude passeggeri e posta). */
function Merci::CargoCamion()
{
	local r = [];
	foreach (c, _ in AICargoList()) {
		if (AICargo.HasCargoClass(c, AICargo.CC_PASSENGERS)) continue;
		if (AICargo.HasCargoClass(c, AICargo.CC_MAIL)) continue;
		if (Merci.ScegliCamion(c) == null) continue;
		r.append(c);
	}
	return r;
}

/* Tutte le merci (non passeggeri ne posta): per i treni. */
function Merci::CargoTreno()
{
	local r = [];
	foreach (c, _ in AICargoList()) {
		if (AICargo.HasCargoClass(c, AICargo.CC_PASSENGERS)) continue;
		if (AICargo.HasCargoClass(c, AICargo.CC_MAIL)) continue;
		r.append(c);
	}
	return r;
}

/* La merce e richiesta dalle citta (beni, cibo, acqua)? */
function Merci::PerCitta(cargo)
{
	local e = AICargo.GetTownEffect(cargo);
	return e == AICargo.TE_GOODS || e == AICargo.TE_FOOD || e == AICargo.TE_WATER;
}

/* Miglior camion acquistabile per quella merce, o null. */
function Merci::ScegliCamion(cargo)
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

function Merci::Chiave(src, dst, cargo)
{
	return "m" + src + "_" + dst + "_" + cargo;
}

function Merci::ChiaveCitta(src, citta, cargo)
{
	return "m" + src + "_c" + citta + "_" + cargo;
}

function Merci::ChiaveFonte(src, cargo)
{
	return "f" + src + "_" + cargo;
}

function Merci::Scarta(ai, src, dst, cargo, mesi, citta = -1)
{
	local scadenza = (mesi < 0) ? 2000000000 : Util.Oggi() + mesi * 30;
	local k = (citta >= 0) ? Merci.ChiaveCitta(src, citta, cargo) : Merci.Chiave(src, dst, cargo);
	ai.coppie[k] <- scadenza;
}

/* Fermata camion passante in citta (stessi criteri delle fermate bus, ma per la merce). */
function Merci::FermataCitta(citta, cargo)
{
	foreach (c in Linee.Candidati(citta, cargo)) {
		if (!Banca.Assicura(3000)) return null;
		if (AIRoad.BuildDriveThroughRoadStation(c[0], c[1], AIRoad.ROADVEHTYPE_TRUCK, AIStation.STATION_NEW)) return c[0];
		if (AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) return -2;
	}
	return null;
}

/* La fonte e gia servita da noi per quella merce? */
function Merci::FonteUsata(ai, src, cargo)
{
	foreach (r in ai.rotte_merci) {
		if (r.src == src && r.cargo == cargo) return true;
	}
	foreach (r in ai.rotte_treni) {
		if (r.src == src && r.cargo == cargo) return true;
	}
	return false;
}

/* Sceglie la rotta piu redditizia. Ritorna { src, dst, cargo } oppure null. */
function Merci::ScegliRotta(ai)
{
	local oggi = Util.Oggi();
	local migliore = null;
	local punteggio_max = 0;

	foreach (c in Merci.CargoCamion()) {
		local fonti = AIIndustryList_CargoProducing(c);
		fonti.Valuate(AIIndustry.GetLastMonthProduction, c);
		fonti.KeepAboveValue(MERCI_PROD_MIN - 1);
		fonti.Valuate(AIIndustry.GetLastMonthTransportedPercentage, c);
		fonti.KeepBelowValue(MERCI_TRASP_MAX);
		fonti.Valuate(AIIndustry.GetLastMonthProduction, c);
		fonti.Sort(AIList.SORT_BY_VALUE, false);
		fonti.KeepTop(MERCI_FONTI_PER_CARGO);

		foreach (src in Util.InArray(fonti)) {
			if (Merci.FonteUsata(ai, src, c)) continue;
			local prod = AIIndustry.GetLastMonthProduction(src, c);
			local loc = AIIndustry.GetLocation(src);

			local dest = AIIndustryList_CargoAccepting(c);
			dest.Valuate(AIIndustry.GetDistanceManhattanToTile, loc);
			dest.KeepAboveValue(MERCI_DIST_MIN - 1);
			dest.KeepBelowValue(MERCI_DIST_MAX + 1);

			foreach (dst, dist in dest) {
				local k = Merci.Chiave(src, dst, c);
				if (k in ai.coppie && ai.coppie[k] > oggi) continue;
				/* incasso per unita, stimando ~1 giorno ogni 2 caselle di viaggio */
				local per_unita = AICargo.GetCargoIncome(c, dist, dist / 2 + 5);
				local punteggio = per_unita * prod;
				if (punteggio > punteggio_max) {
					punteggio_max = punteggio;
					migliore = { src = src, dst = dst, citta = -1, cargo = c };
				}
			}

			/* Merci per le citta (beni, cibo, acqua): destinazione = una citta che le accetta */
			if (Merci.PerCitta(c)) {
				local raggio = AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP);
				local citta = AITownList();
				citta.Valuate(AITown.GetPopulation);
				citta.KeepAboveValue(499);
				citta.Valuate(AITown.GetDistanceManhattanToTile, loc);
				citta.KeepAboveValue(MERCI_DIST_MIN - 1);
				citta.KeepBelowValue(MERCI_DIST_MAX + 1);
				foreach (t, dist in citta) {
					local k = Merci.ChiaveCitta(src, t, c);
					if (k in ai.coppie && ai.coppie[k] > oggi) continue;
					if (AITile.GetCargoAcceptance(AITown.GetLocation(t), c, 1, 1, raggio) < 8) continue;
					local punteggio = AICargo.GetCargoIncome(c, dist, dist / 2 + 5) * prod;
					if (punteggio > punteggio_max) {
						punteggio_max = punteggio;
						migliore = { src = src, dst = -1, citta = t, cargo = c };
					}
				}
			}
		}
	}
	return migliore;
}

/*
 * Costruisce una fermata camion a baia vicino all'industria, con l'ingresso verso "verso".
 * presa = true: caselle da cui si raccoglie la merce; false: caselle che la accettano.
 * Ritorna [casella, davanti] oppure null.
 */
function Merci::CostruisciStazione(ind, cargo, presa, verso)
{
	local raggio = AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP);
	local tiles = presa ? AITileList_IndustryProducing(ind, raggio) : AITileList_IndustryAccepting(ind, raggio);
	tiles.Valuate(AITile.IsBuildable);
	tiles.KeepValue(1);
	tiles.Valuate(AITile.GetSlope);
	tiles.KeepValue(AITile.SLOPE_FLAT);
	if (!presa) {
		tiles.Valuate(AITile.GetCargoAcceptance, cargo, 1, 1, raggio);
		tiles.KeepAboveValue(7);
	}
	tiles.Valuate(AIMap.DistanceManhattan, verso);
	tiles.Sort(AIList.SORT_BY_VALUE, true);

	local tentativi = 0;
	foreach (t, _ in tiles) {
		if (tentativi++ >= 25) break;
		foreach (d in Util.Direzioni()) {
			local f = t + d;
			if (AITile.IsStationTile(f)) continue;
			local libera = AITile.IsBuildable(f) && AITile.GetSlope(f) == AITile.SLOPE_FLAT;
			local strada = AIRoad.IsRoadTile(f) && !AIRoad.IsRoadStationTile(f) && !AIRoad.IsRoadDepotTile(f);
			if (!libera && !strada) continue;
			if (!Banca.Assicura(5000)) return null;
			if (!AIRoad.BuildRoadStation(t, f, AIRoad.ROADVEHTYPE_TRUCK, AIStation.STATION_NEW)) continue;
			if (!AIRoad.BuildRoad(f, t)) {
				AIRoad.RemoveRoadStation(t);
				continue;
			}
			return [t, f];
		}
	}
	return null;
}

/* Compra un camion per la rotta e lo mette in servizio. */
function Merci::AggiungiCamion(ai, rotta)
{
	if (Util.PostiLiberi(AIVehicle.VT_ROAD) <= 0) return false;  /* limite veicoli raggiunto */
	local motore = Merci.ScegliCamion(rotta.cargo);
	if (motore == null) return false;
	if (!Banca.Assicura(AIEngine.GetPrice(motore))) return false;

	local v = AIVehicle.BuildVehicle(rotta.dep, motore);
	if (!AIVehicle.IsValidVehicle(v)) {
		Util.Errore("Acquisto camion fallito");
		return false;
	}
	if (AIEngine.GetCargoType(motore) != rotta.cargo && !AIVehicle.RefitVehicle(v, rotta.cargo)) {
		Util.Errore("Riadattamento camion fallito");
		AIVehicle.SellVehicle(v);
		return false;
	}

	local esistenti = AIVehicleList_Group(rotta.gr);
	esistenti.RemoveItem(v);
	if (!esistenti.IsEmpty()) {
		AIOrder.ShareOrders(v, esistenti.Begin());
	} else {
		AIOrder.AppendOrder(v, rotta.ta, AIOrder.OF_FULL_LOAD_ANY | AIOrder.OF_NON_STOP_INTERMEDIATE);
		AIOrder.AppendOrder(v, rotta.tb, AIOrder.OF_NON_STOP_INTERMEDIATE);
	}
	AIGroup.MoveVehicle(rotta.gr, v);
	AIVehicle.StartStopVehicle(v);
	Util.Log("Nuovo camion " + AICargo.GetCargoLabel(rotta.cargo) + " " + Merci.Nome(rotta) +
	         " (ora " + AIVehicleList_Group(rotta.gr).Count() + ")", 2);
	return true;
}

function Merci::VersoCitta(r)
{
	return ("citta" in r) && r.citta >= 0;
}

function Merci::Nome(r)
{
	local dest = Merci.VersoCitta(r) ? AITown.GetName(r.citta) : AIIndustry.GetName(r.dst);
	return AIIndustry.GetName(r.src) + " -> " + dest;
}

/* Prova a costruire una nuova rotta merci completa. */
function Merci::CostruisciNuova(ai)
{
	if (Util.PostiLiberi(AIVehicle.VT_ROAD) < 5) return false;  /* niente rotte senza posto per i camion */
	if (Banca.Disponibile() < 30000) {
		Util.Log("Merci: fondi insufficienti, aspetto", 2);
		return false;
	}
	local scelta = Merci.ScegliRotta(ai);
	if (scelta == null) {
		AILog.Info("Merci: nessuna rotta camion valida trovata");
		return false;
	}
	local src = scelta.src, dst = scelta.dst, citta = scelta.citta, c = scelta.cargo;
	local verso_citta = (citta >= 0);
	Util.Log("Valuto rotta merci " + AICargo.GetCargoLabel(c) + ": " + AIIndustry.GetName(src) + " -> " +
	         (verso_citta ? AITown.GetName(citta) : AIIndustry.GetName(dst)), 2);

	/* 1. Fermate (costano poco: si fanno prima, si smontano se la strada non si trova).
	 *    Verso una citta la fermata di scarico si fa dopo la strada, in centro. */
	local locA = AIIndustry.GetLocation(src);
	local locB = verso_citta ? AITown.GetLocation(citta) : AIIndustry.GetLocation(dst);
	local A = Merci.CostruisciStazione(src, c, true, locB);
	if (A == null) {
		AILog.Info("Merci: nessun posto per la fermata di carico");
		Merci.Scarta(ai, src, dst, c, -1, citta);
		return false;
	}
	local B = null;
	if (!verso_citta) {
		B = Merci.CostruisciStazione(dst, c, false, locA);
		if (B == null) {
			AILog.Info("Merci: nessun posto per la fermata di scarico");
			AIRoad.RemoveRoadStation(A[0]);
			Merci.Scarta(ai, src, dst, c, -1, citta);
			return false;
		}
	}

	/* 2. Strada: verso l'ingresso della fermata di scarico, oppure verso il centro citta */
	local percorso = Strade.Cerca(A[1], verso_citta ? locB : B[1], ai);
	local fallita = (percorso == null);
	local mesi = -1;
	if (!fallita) {
		local costo = Strade.Stima(percorso) + 10000 + AIEngine.GetPrice(Merci.ScegliCamion(c)) * 2;
		Util.Log("Costo stimato: " + costo, 2);
		if (costo > Banca.Disponibile() * 6 / 10 || !Banca.Assicura(costo)) {
			AILog.Info("Merci: rotta troppo cara per ora (" + costo + ")");
			fallita = true;
			mesi = 6;
		} else {
			fallita = !Strade.Costruisci(percorso);
		}
	}
	if (!fallita && verso_citta) {
		local tb = Merci.FermataCitta(citta, c);
		if (tb == null || tb < 0) {
			if (tb == -2) {
				Autorita.Recupera(ai, citta);
				mesi = 6;
			}
			AILog.Info("Merci: nessuna fermata di scarico possibile a " + AITown.GetName(citta));
			fallita = true;
		} else {
			B = [tb, tb];
		}
	}
	if (fallita) {
		AIRoad.RemoveRoadStation(A[0]);
		if (B != null) AIRoad.RemoveRoadStation(B[0]);
		Merci.Scarta(ai, src, dst, c, mesi, citta);
		return false;
	}

	/* 3. Deposito vicino alla fermata di carico */
	local dep = Linee.CostruisciDeposito(A[0]);
	if (dep == null) dep = Linee.CostruisciDeposito(B[0]);
	if (dep == null) {
		AILog.Warning("Merci: nessun deposito possibile, smonto le fermate");
		AIRoad.RemoveRoadStation(A[0]);
		AIRoad.RemoveRoadStation(B[0]);
		Merci.Scarta(ai, src, dst, c, -1, citta);
		return false;
	}

	/* 4. Gruppo e camion */
	local gr = AIGroup.CreateGroup(AIVehicle.VT_ROAD, AIGroup.GROUP_INVALID);
	local rotta = {
		src = src, dst = dst, citta = citta, cargo = c,
		sa = AIStation.GetStationID(A[0]), sb = AIStation.GetStationID(B[0]),
		ta = A[0], tb = B[0], dep = dep, gr = gr
	};
	if (AIGroup.IsValidGroup(gr)) {
		local nome = AICargo.GetCargoLabel(c) + " " + AIIndustry.GetName(src);
		if (nome.len() > 30) nome = nome.slice(0, 30);
		AIGroup.SetName(gr, nome);
	}
	ai.rotte_merci.append(rotta);
	Merci.Scarta(ai, src, dst, c, -1, citta);

	Merci.AggiungiCamion(ai, rotta);
	Merci.AggiungiCamion(ai, rotta);
	AILog.Info("+ Rotta " + AICargo.GetCargoLabel(c) + ": " + Merci.Nome(rotta) + " (" + AIMap.DistanceManhattan(rotta.ta, rotta.tb) + " caselle)");
	return true;
}

/* Una volta al mese: camion in piu, camion in perdita, industrie chiuse. */
function Merci::Mensile(ai)
{
	local restano = [];
	foreach (r in ai.rotte_merci) {
		local veicoli = AIVehicleList_Group(r.gr);
		foreach (v, _ in ai.da_vendere) {
			if (veicoli.HasItem(v)) veicoli.RemoveItem(v);
		}

		/* Industria chiusa o fermate distrutte: vendi tutto e chiudi la rotta */
		local dest_ok = Merci.VersoCitta(r) ? AITown.IsValidTown(r.citta) : AIIndustry.IsValidIndustry(r.dst);
		if (!AIIndustry.IsValidIndustry(r.src) || !dest_ok ||
		    !AIStation.IsValidStation(r.sa) || !AIStation.IsValidStation(r.sb)) {
			foreach (v, _ in veicoli) {
				if (AIVehicle.SendVehicleToDepot(v)) ai.da_vendere[v] <- true;
			}
			AILog.Warning("Rotta merci chiusa (industria o fermata sparita), camion in vendita");
			continue;
		}
		restano.append(r);

		local n = veicoli.Count();
		if (n == 0) {
			Merci.AggiungiCamion(ai, r);
			continue;
		}
		n = Veicoli.Ridimensiona(ai, veicoli, n, AICargo.GetCargoLabel(r.cargo) + " " + AIIndustry.GetName(r.src));
		if (Veicoli.InPerdita(veicoli)) continue;

		/* camion vecchi in perdita (ne resta almeno 1) */
		local perdita = AIList();
		perdita.AddList(veicoli);
		perdita.Valuate(AIVehicle.GetAge);
		perdita.KeepAboveValue(ETA_VALUTAZIONE);
		perdita.Valuate(AIVehicle.GetProfitLastYear);
		perdita.KeepBelowValue(0);
		foreach (v, _ in perdita) {
			if (n <= 1) break;
			if (AIVehicle.SendVehicleToDepot(v)) {
				ai.da_vendere[v] <- true;
				n--;
			}
		}

		/* merce che si accumula o rating basso alla fermata di carico: un camion in piu */
		local dist = AIMap.DistanceManhattan(r.ta, r.tb);
		local max = Util.Min(MERCI_MAX_CAMION, dist / 6 + 2);
		if (n >= max) continue;
		local cap = AIVehicle.GetCapacity(veicoli.Begin(), r.cargo);
		local attesa = AIStation.GetCargoWaiting(r.sa, r.cargo);
		local rating = AIStation.GetCargoRating(r.sa, r.cargo);
		if (attesa < cap * 2 && rating >= 55) continue;
		local eta = AIList();
		eta.AddList(veicoli);
		eta.Valuate(AIVehicle.GetAge);
		eta.Sort(AIList.SORT_BY_VALUE, true);
		if (eta.GetValue(eta.Begin()) < 30) continue;
		Merci.AggiungiCamion(ai, r);
	}
	ai.rotte_merci = restano;
}

/* Dopo un caricamento. */
function Merci::Ripristina(ai, dati)
{
	if (dati == null || !("rotte_merci" in dati)) return;
	foreach (r in dati.rotte_merci) {
		if (!AIStation.IsValidStation(r.sa) || !AIStation.IsValidStation(r.sb)) continue;
		if (!AIGroup.IsValidGroup(r.gr)) continue;
		ai.rotte_merci.append(r);
	}
	AILog.Info("Ripristinate " + ai.rotte_merci.len() + " rotte merci");
}
