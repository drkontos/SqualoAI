/*
 * SqualoAI - veicoli.nut
 * Aggiunta bus sulle linee piene, vendita dei bus in perdita, pulizia depositi.
 */

class Veicoli {}

const ATTESA_PER_NUOVO_BUS = 100;   /* passeggeri in attesa che giustificano un bus in piu */
const ETA_MIN_NUOVO_BUS = 45;       /* giorni: non aggiungere bus se l'ultimo e troppo recente */
const ETA_VALUTAZIONE = 730;        /* giorni: un bus si giudica dopo 2 anni */

/*
 * Tetto di bus per linea: 4 bus per ogni casella di fermata (la fermata piu piccola delle due decide).
 * Una casella passante ha 2 posti di carico; oltre ~4 bus si formano code.
 * Le fermate si ampliano fino a 3 caselle in fila quando c'e coda.
 */
const BUS_PER_CASELLA = 4;
const MAX_CASELLE_FERMATA = 3;

function Veicoli::Caselle(stazione)
{
	if (!AIStation.IsValidStation(stazione)) return 0;
	return AITileList_StationType(stazione, AIStation.STATION_BUS_STOP).Count();
}

function Veicoli::MaxBus(linea)
{
	local dist = AIMap.DistanceManhattan(linea.ta, linea.tb);
	local caselle = Util.Min(Veicoli.Caselle(linea.sa), Veicoli.Caselle(linea.sb));
	return Util.Max(2, Util.Min(caselle * BUS_PER_CASELLA, dist / 8 + 2));
}

/*
 * Aggiunge una casella passante in fila a una fermata esistente, sulla stessa strada dritta.
 * Ritorna true se ci riesce.
 */
function Veicoli::AmpliaFermata(stazione)
{
	local caselle = AITileList_StationType(stazione, AIStation.STATION_BUS_STOP);
	if (caselle.Count() >= MAX_CASELLE_FERMATA) return false;
	foreach (t, _ in caselle) {
		local asse = AIRoad.GetRoadStationFrontTile(t) - t;
		foreach (c in [t + asse, t - asse]) {
			if (!AIRoad.IsRoadTile(c)) continue;
			if (AIRoad.IsRoadStationTile(c) || AIRoad.IsRoadDepotTile(c)) continue;
			if (AITile.GetSlope(c) != AITile.SLOPE_FLAT) continue;
			if (AIRail.IsLevelCrossingTile(c) || AIBridge.IsBridgeTile(c) || AITunnel.IsTunnelTile(c)) continue;
			local f = Linee.Rettilineo(c);
			if (f == null || (f - c != asse && c - f != asse)) continue;
			if (!Banca.Assicura(3000)) return false;
			if (AIRoad.BuildDriveThroughRoadStation(c, c + asse, AIRoad.ROADVEHTYPE_BUS, stazione)) {
				AILog.Info("Fermata " + AIStation.GetName(stazione) + " ampliata a " + (caselle.Count() + 1) + " caselle");
				return true;
			}
			Util.Log("Ampliamento fallito: " + AIError.GetLastErrorString(), 2);
		}
	}
	return false;
}

/* Quanti bus della linea sono fermi in strada (non in fermata ne in deposito): segno di coda. */
function Veicoli::InCoda(veicoli)
{
	local n = 0;
	foreach (v, _ in veicoli) {
		if (AIVehicle.GetState(v) != AIVehicle.VS_RUNNING) continue;
		if (AIVehicle.GetCurrentSpeed(v) > 0) continue;
		if (AIStation.GetStationID(AIVehicle.GetLocation(v)) != AIStation.STATION_INVALID &&
		    AITile.IsStationTile(AIVehicle.GetLocation(v))) continue;
		n++;
	}
	return n;
}

/*
 * La rotta ha perso soldi nell'ultimo anno ed e abbastanza vecchia da giudicarla?
 * (Il primo anno e escluso: acquisto e avvio pesano sui conti.)
 */
function Veicoli::InPerdita(veicoli)
{
	local tot = 0, eta_max = 0;
	foreach (v, _ in veicoli) {
		tot += AIVehicle.GetProfitLastYear(v);
		eta_max = Util.Max(eta_max, AIVehicle.GetAge(v));
	}
	return tot < 0 && eta_max > 400;
}

/*
 * Rotta in perdita con piu di 2 veicoli: ne toglie uno al mese finche torna a 2.
 * Evita il circolo vizioso "merce accumulata -> altro veicolo -> piu perdite".
 * Ritorna il nuovo numero di veicoli.
 */
function Veicoli::Ridimensiona(ai, veicoli, n, nome)
{
	if (n <= 2 || !Veicoli.InPerdita(veicoli)) return n;
	foreach (v, _ in veicoli) {
		if (v in ai.da_vendere) continue;
		if (AIVehicle.SendVehicleToDepot(v)) {
			ai.da_vendere[v] <- true;
			AILog.Info("In perdita: tolgo un veicolo da " + nome + " (" + n + " -> " + (n - 1) + ")");
			return n - 1;
		}
	}
	return n;
}

/* Ogni giro: vende i bus mandati al deposito che sono arrivati. */
function Veicoli::Vendite(ai)
{
	local venduti = [];
	foreach (v, _ in ai.da_vendere) {
		if (!AIVehicle.IsValidVehicle(v)) {
			venduti.append(v);
			continue;
		}
		if (AIVehicle.IsStoppedInDepot(v)) {
			if (AIVehicle.SellVehicle(v)) {
				Util.Log("Veicolo venduto", 2);
				venduti.append(v);
			}
		} else if (AIOrder.GetOrderCount(v) > 0 && !AIOrder.IsGotoDepotOrder(v, AIOrder.ORDER_CURRENT)) {
			/* L'ordine di andare al deposito si e perso: lo ridiamo. */
			AIVehicle.SendVehicleToDepot(v);
		}
	}
	foreach (v in venduti) delete ai.da_vendere[v];
}

/* Una volta al mese: per ogni linea decide se aggiungere o togliere bus. */
function Veicoli::Mensile(ai)
{
	foreach (linea in ai.linee) {
		if (!AIStation.IsValidStation(linea.sa) || !AIStation.IsValidStation(linea.sb)) continue;
		local veicoli = AIVehicleList_Group(linea.gr);
		/* togli dal conteggio quelli gia in vendita */
		foreach (v, _ in ai.da_vendere) {
			if (veicoli.HasItem(v)) veicoli.RemoveItem(v);
		}
		local n = veicoli.Count();

		if (n == 0) {
			Linee.AggiungiBus(ai, linea);
			continue;
		}
		local nome = "bus " + AITown.GetName(linea.a) + "-" + AITown.GetName(linea.b);
		n = Veicoli.Ridimensiona(ai, veicoli, n, nome);
		if (Veicoli.InPerdita(veicoli)) continue;  /* in perdita: mai aggiungere */

		/* Vendi i bus vecchi abbastanza da essere giudicati e in perdita (ne resta sempre almeno 1). */
		local da_togliere = AIList();
		da_togliere.AddList(veicoli);
		da_togliere.Valuate(AIVehicle.GetAge);
		da_togliere.KeepAboveValue(ETA_VALUTAZIONE);
		da_togliere.Valuate(AIVehicle.GetProfitLastYear);
		da_togliere.KeepBelowValue(0);
		foreach (v, _ in da_togliere) {
			if (n <= 1) break;
			if (AIVehicle.SendVehicleToDepot(v)) {
				ai.da_vendere[v] <- true;
				n--;
				Util.Log("Bus in perdita mandato al deposito per la vendita", 1);
			}
		}

		/* Coda: prima si amplia la fermata; se non si puo, si toglie un bus. */
		local coda = Veicoli.InCoda(veicoli);
		if (coda >= 2) {
			AILog.Info("Coda sulla linea " + AITown.GetName(linea.a) + " - " + AITown.GetName(linea.b) +
			           ": " + coda + " bus fermi su " + n);
			local ampliata = Veicoli.AmpliaFermata(linea.sa);
			if (Veicoli.AmpliaFermata(linea.sb)) ampliata = true;
			if (!ampliata && n > Veicoli.MaxBus(linea)) {
				local v = null;
				foreach (x, _ in veicoli) { if (!(x in ai.da_vendere)) { v = x; break; } }
				if (v != null && AIVehicle.SendVehicleToDepot(v)) {
					ai.da_vendere[v] <- true;
					AILog.Info("Fermate non ampliabili: tolgo un bus dalla linea");
				}
			}
			continue;
		}

		/* Aggiungi un bus se ci sono troppi passeggeri in attesa. */
		local attesa = Util.Max(AIStation.GetCargoWaiting(linea.sa, ai.cargo),
		                        AIStation.GetCargoWaiting(linea.sb, ai.cargo));
		if (attesa < ATTESA_PER_NUOVO_BUS) continue;
		if (n >= Veicoli.MaxBus(linea)) {
			/* linea al tetto ma gente in attesa: proviamo ad allargare le fermate per il mese prossimo */
			Veicoli.AmpliaFermata(linea.sa);
			Veicoli.AmpliaFermata(linea.sb);
			continue;
		}
		local eta = AIList();
		eta.AddList(veicoli);
		eta.Valuate(AIVehicle.GetAge);
		eta.Sort(AIList.SORT_BY_VALUE, true);
		if (!eta.IsEmpty() && eta.GetValue(eta.Begin()) < ETA_MIN_NUOVO_BUS) continue;
		Linee.AggiungiBus(ai, linea);
	}
}

/* Dopo un caricamento: vende i nostri veicoli fermi nei depositi (probabili vendite lasciate a meta). */
function Veicoli::PuliziaDepositi(ai)
{
	local tutti = AIVehicleList();
	foreach (v, _ in tutti) {
		if (AIVehicle.IsStoppedInDepot(v)) ai.da_vendere[v] <- true;
	}
}
