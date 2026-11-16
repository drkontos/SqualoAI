/*
 * SqualoAI - aerei.nut
 * Rotte aeree passeggeri tra citta grandi e lontane.
 *
 * Una rotta aerea e una tabella:
 *   { a, b,        citta collegate
 *     sa, sb,      StationID dei due aeroporti
 *     ta, tb,      casella base (angolo nord) di ciascun aeroporto
 *     gr }         gruppo veicoli
 * Un aeroporto gia nostro in una citta viene riusato da altre rotte.
 */

class Aerei {}

const AEREI_POP_MIN = 1000;
const AEREI_DIST_MIN = 100;
const AEREI_DIST_MAX = 450;
const AEREI_CASSA_MIN = 300000;   /* sotto questa disponibilita non si pensa nemmeno agli aerei */

/* Le costanti non sono visibili da main.nut (compilato prima dei require): si passa da qui. */
function Aerei::CassaMinima() { return AEREI_CASSA_MIN; }

/* Tipi di aeroporto in ordine di preferenza (il primo disponibile nell'anno corrente). */
function Aerei::TipoAeroporto()
{
	foreach (t in [AIAirport.AT_METROPOLITAN, AIAirport.AT_LARGE, AIAirport.AT_COMMUTER, AIAirport.AT_SMALL]) {
		if (AIAirport.IsValidAirportType(t)) return t;
	}
	return AIAirport.AT_INVALID;
}

function Aerei::Piccolo(tipo)
{
	return tipo == AIAirport.AT_SMALL || tipo == AIAirport.AT_COMMUTER;
}

/*
 * Miglior aereo passeggeri: niente elicotteri; niente aerei grandi se uno dei due aeroporti
 * e piccolo (rischio di schianto); autonomia sufficiente per la distanza.
 * tileA/tileB possono essere null (solo per sapere se esiste un aereo).
 */
function Aerei::ScegliAereo(cargo, piccolo, tileA, tileB)
{
	local motori = AIEngineList(AIVehicle.VT_AIR);
	motori.Valuate(AIEngine.IsBuildable);
	motori.KeepValue(1);
	motori.Valuate(function(e, c) {
		return (AIEngine.GetCargoType(e) == c || AIEngine.CanRefitCargo(e, c)) ? 1 : 0;
	}, cargo);
	motori.KeepValue(1);
	motori.Valuate(AIEngine.GetPlaneType);
	motori.RemoveValue(AIAirport.PT_HELICOPTER);
	if (piccolo) motori.RemoveValue(AIAirport.PT_BIG_PLANE);
	if (tileA != null && tileB != null) {
		local d = AIOrder.GetOrderDistance(AIVehicle.VT_AIR, tileA, tileB);
		motori.Valuate(function(e, d) {
			local max = AIEngine.GetMaximumOrderDistance(e);
			return (max == 0 || max >= d) ? 1 : 0;
		}, d);
		motori.KeepValue(1);
	}
	if (motori.IsEmpty()) return null;
	motori.Valuate(function(e) {
		return AIEngine.GetCapacity(e) * AIEngine.GetMaxSpeed(e);
	});
	motori.Sort(AIList.SORT_BY_VALUE, false);
	return motori.Begin();
}

/* Aeroporto nostro gia esistente in quella citta: [StationID, casella] oppure null. */
function Aerei::AeroportoInCitta(ai, citta)
{
	foreach (r in ai.rotte_aeree) {
		if (r.a == citta && AIStation.IsValidStation(r.sa)) return [r.sa, r.ta];
		if (r.b == citta && AIStation.IsValidStation(r.sb)) return [r.sb, r.tb];
	}
	return null;
}

function Aerei::Chiave(a, b)
{
	return "a" + ((a < b) ? (a + "_" + b) : (b + "_" + a));
}

function Aerei::Scarta(ai, a, b, mesi)
{
	ai.coppie[Aerei.Chiave(a, b)] <- (mesi < 0) ? 2000000000 : Util.Oggi() + mesi * 30;
}

function Aerei::ScegliCoppia(ai)
{
	local lista = AITownList();
	lista.Valuate(AITown.GetPopulation);
	lista.KeepAboveValue(AEREI_POP_MIN - 1);
	lista.Sort(AIList.SORT_BY_VALUE, false);
	lista.KeepTop(40);
	local citta = Util.InArray(lista);
	local oggi = Util.Oggi();
	local migliore = null, punteggio_max = 0;
	for (local i = 0; i < citta.len(); i++) {
		for (local j = i + 1; j < citta.len(); j++) {
			local a = citta[i], b = citta[j];
			local k = Aerei.Chiave(a, b);
			if (k in ai.coppie && ai.coppie[k] > oggi) continue;
			local dist = AIMap.DistanceManhattan(AITown.GetLocation(a), AITown.GetLocation(b));
			if (dist < AEREI_DIST_MIN || dist > AEREI_DIST_MAX) continue;
			local p = Util.Min(AITown.GetPopulation(a), AITown.GetPopulation(b)) * dist / 10;
			if (p > punteggio_max) {
				punteggio_max = p;
				migliore = [a, b];
			}
		}
	}
	return migliore;
}

/* Prova la costruzione in modalita test (non spende nulla). */
function Aerei::Fattibile(t, tipo)
{
	local test = AITestMode();
	return AIAirport.BuildAirport(t, tipo, AIStation.STATION_NEW);
}

/*
 * Costruisce un aeroporto vicino al centro, nella posizione che raccoglie piu passeggeri.
 * Ritorna la casella base, -1 se non trova posto, -2 se l'autorita locale rifiuta.
 */
function Aerei::CostruisciAeroporto(citta, tipo, cargo)
{
	local w = AIAirport.GetAirportWidth(tipo);
	local h = AIAirport.GetAirportHeight(tipo);
	local r = AIAirport.GetAirportCoverageRadius(tipo);
	local tiles = Util.Rettangolo(AITown.GetLocation(citta), 15);
	tiles.Valuate(AITile.IsBuildableRectangle, w, h);
	tiles.KeepValue(1);
	tiles.Valuate(AITile.GetCargoAcceptance, cargo, w, h, r);
	tiles.KeepAboveValue(9);
	tiles.Valuate(AITile.GetCargoProduction, cargo, w, h, r);
	tiles.Sort(AIList.SORT_BY_VALUE, false);

	local rifiuto = false;
	local prove = 0;
	foreach (t, _ in tiles) {
		if (prove++ >= 60) break;
		if (!Aerei.Fattibile(t, tipo)) {
			if (AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) rifiuto = true;
			continue;
		}
		if (!Banca.Assicura(AIAirport.GetPrice(tipo) + 10000)) return -1;
		if (AIAirport.BuildAirport(t, tipo, AIStation.STATION_NEW)) return t;
		if (AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) rifiuto = true;
	}
	return rifiuto ? -2 : -1;
}

function Aerei::Nome(r)
{
	return AITown.GetName(r.a) + " - " + AITown.GetName(r.b);
}

/* Compra un aereo per la rotta. */
function Aerei::AggiungiAereo(ai, rotta)
{
	local piccolo = Aerei.Piccolo(AIAirport.GetAirportType(rotta.ta)) || Aerei.Piccolo(AIAirport.GetAirportType(rotta.tb));
	if (Util.PostiLiberi(AIVehicle.VT_AIR) <= 0) return false;  /* limite aerei raggiunto */
	local motore = Aerei.ScegliAereo(ai.cargo, piccolo, rotta.ta, rotta.tb);
	if (motore == null) return false;
	if (!Banca.Assicura(AIEngine.GetPrice(motore))) return false;

	local hangar = AIAirport.GetHangarOfAirport(rotta.ta);
	local v = AIVehicle.BuildVehicle(hangar, motore);
	if (!AIVehicle.IsValidVehicle(v)) {
		Util.Errore("Acquisto aereo fallito");
		return false;
	}
	if (AIEngine.GetCargoType(motore) != ai.cargo) AIVehicle.RefitVehicle(v, ai.cargo);

	local esistenti = AIVehicleList_Group(rotta.gr);
	esistenti.RemoveItem(v);
	if (!esistenti.IsEmpty()) {
		AIOrder.ShareOrders(v, esistenti.Begin());
	} else {
		AIOrder.AppendOrder(v, rotta.ta, AIOrder.OF_NONE);
		AIOrder.AppendOrder(v, rotta.tb, AIOrder.OF_NONE);
	}
	/* un aereo si ed uno no parte verso l'altra citta, per non viaggiare in coppia */
	if (esistenti.Count() % 2 == 0) AIOrder.SkipToOrder(v, 1);
	AIGroup.MoveVehicle(rotta.gr, v);
	AIVehicle.StartStopVehicle(v);
	Util.Log("Nuovo aereo " + Aerei.Nome(rotta) + " (ora " + AIVehicleList_Group(rotta.gr).Count() + ")", 2);
	return true;
}

/* Prova ad aprire una nuova rotta aerea. */
function Aerei::CostruisciNuova(ai)
{
	if (ai.cargo == null) return false;
	if (Util.PostiLiberi(AIVehicle.VT_AIR) < 3) return false;
	if (Banca.Disponibile() < AEREI_CASSA_MIN) return false;
	local tipo = Aerei.TipoAeroporto();
	if (tipo == AIAirport.AT_INVALID) return false;
	if (Aerei.ScegliAereo(ai.cargo, Aerei.Piccolo(tipo), null, null) == null) {
		Util.Log("Aerei: nessun aereo passeggeri adatto disponibile", 2);
		return false;
	}

	local coppia = Aerei.ScegliCoppia(ai);
	if (coppia == null) {
		Util.Log("Aerei: nessuna coppia di citta valida", 2);
		return false;
	}
	local a = coppia[0], b = coppia[1];

	/* stima: due aeroporti nuovi (se non li abbiamo gia) + due aerei */
	local prezzo_aereo = AIEngine.GetPrice(Aerei.ScegliAereo(ai.cargo, Aerei.Piccolo(tipo), null, null));
	local esisteA = Aerei.AeroportoInCitta(ai, a);
	local esisteB = Aerei.AeroportoInCitta(ai, b);
	local costo = prezzo_aereo * 2;
	if (esisteA == null) costo += AIAirport.GetPrice(tipo);
	if (esisteB == null) costo += AIAirport.GetPrice(tipo);
	if (costo > Banca.Disponibile() * 6 / 10) {
		Util.Log("Aerei: rotta troppo cara per ora (" + costo + ")", 1);
		Aerei.Scarta(ai, a, b, 6);
		return false;
	}

	local ta, tb;
	local nuovoA = false;
	if (esisteA != null) {
		ta = esisteA[1];
	} else {
		ta = Aerei.CostruisciAeroporto(a, tipo, ai.cargo);
		if (ta < 0) {
			if (ta == -2) Autorita.Recupera(ai, a);
			AILog.Info("Aerei: nessun aeroporto possibile a " + AITown.GetName(a));
			Aerei.Scarta(ai, a, b, (ta == -2) ? 6 : -1);
			return false;
		}
		nuovoA = true;
	}
	if (esisteB != null) {
		tb = esisteB[1];
	} else {
		tb = Aerei.CostruisciAeroporto(b, tipo, ai.cargo);
		if (tb < 0) {
			if (tb == -2) Autorita.Recupera(ai, b);
			AILog.Info("Aerei: nessun aeroporto possibile a " + AITown.GetName(b));
			if (nuovoA) AIAirport.RemoveAirport(ta);
			Aerei.Scarta(ai, a, b, (tb == -2) ? 6 : -1);
			return false;
		}
	}

	local gr = AIGroup.CreateGroup(AIVehicle.VT_AIR, AIGroup.GROUP_INVALID);
	local rotta = {
		a = a, b = b,
		sa = AIStation.GetStationID(ta), sb = AIStation.GetStationID(tb),
		ta = ta, tb = tb, gr = gr
	};
	if (AIGroup.IsValidGroup(gr)) {
		local nome = "Aereo " + AITown.GetName(a) + "-" + AITown.GetName(b);
		if (nome.len() > 30) nome = nome.slice(0, 30);
		AIGroup.SetName(gr, nome);
	}
	ai.rotte_aeree.append(rotta);
	Aerei.Scarta(ai, a, b, -1);

	Aerei.AggiungiAereo(ai, rotta);
	Aerei.AggiungiAereo(ai, rotta);
	AILog.Info("+ Rotta aerea: " + Aerei.Nome(rotta) + " (" + AIMap.DistanceManhattan(ta, tb) + " caselle)");
	return true;
}

function Aerei::MaxAerei(rotta)
{
	local piccolo = Aerei.Piccolo(AIAirport.GetAirportType(rotta.ta)) || Aerei.Piccolo(AIAirport.GetAirportType(rotta.tb));
	local dist = AIMap.DistanceManhattan(rotta.ta, rotta.tb);
	return Util.Min(piccolo ? 4 : 10, dist / 40 + 2);
}

/* Una volta al mese: aerei in piu dove i passeggeri si accumulano, vendita di quelli in perdita. */
function Aerei::Mensile(ai)
{
	foreach (r in ai.rotte_aeree) {
		if (!AIStation.IsValidStation(r.sa) || !AIStation.IsValidStation(r.sb)) continue;
		local veicoli = AIVehicleList_Group(r.gr);
		foreach (v, _ in ai.da_vendere) {
			if (veicoli.HasItem(v)) veicoli.RemoveItem(v);
		}
		local n = veicoli.Count();
		if (n == 0) {
			Aerei.AggiungiAereo(ai, r);
			continue;
		}
		n = Veicoli.Ridimensiona(ai, veicoli, n, "aereo " + Aerei.Nome(r));
		if (Veicoli.InPerdita(veicoli)) continue;

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

		if (n >= Aerei.MaxAerei(r)) continue;
		/*
		 * Un aereo in piu se i passeggeri si accumulano OPPURE se il rating di un aeroporto
		 * scende sotto il 60% (con pochi aerei passano di rado e il rating cala: si perdono passeggeri).
		 */
		local cap = AIVehicle.GetCapacity(veicoli.Begin(), ai.cargo);
		local attesa = Util.Max(AIStation.GetCargoWaiting(r.sa, ai.cargo), AIStation.GetCargoWaiting(r.sb, ai.cargo));
		local rating = Util.Min(AIStation.GetCargoRating(r.sa, ai.cargo), AIStation.GetCargoRating(r.sb, ai.cargo));
		if (attesa < cap && rating >= 60) continue;
		local eta = AIList();
		eta.AddList(veicoli);
		eta.Valuate(AIVehicle.GetAge);
		eta.Sort(AIList.SORT_BY_VALUE, true);
		if (eta.GetValue(eta.Begin()) < 60) continue;
		Aerei.AggiungiAereo(ai, r);
	}
}

function Aerei::Ripristina(ai, dati)
{
	if (dati == null || !("rotte_aeree" in dati)) return;
	foreach (r in dati.rotte_aeree) {
		if (!AIStation.IsValidStation(r.sa) || !AIStation.IsValidStation(r.sb)) continue;
		if (!AIGroup.IsValidGroup(r.gr)) continue;
		ai.rotte_aeree.append(r);
	}
	AILog.Info("Ripristinate " + ai.rotte_aeree.len() + " rotte aeree");
}
