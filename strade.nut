/*
 * SqualoAI - strade.nut
 * Ricerca percorso e costruzione strade con la libreria ufficiale "pathfinder.road" v4.
 */

class Strade {}

/*
 * Pathfinder "pesato": stima la distanza rimanente il 30% piu del minimo teorico.
 * La ricerca diventa molto piu veloce; i percorsi trovati sono a volte un po' piu lunghi
 * dell'ottimo. Tecnica standard (weighted A*), usata anche da altre AI come BorkAI.
 */
class PercorsoVeloce extends RoadPathFinder {}

function PercorsoVeloce::_Estimate(self, cur_tile, cur_direction, goal_tiles)
{
	return ::RoadPathFinder._Estimate(self, cur_tile, cur_direction, goal_tiles) * 13 / 10;
}

/* Cerca un percorso stradale tra due caselle. Ritorna il percorso o null. */
function Strade::Cerca(da, a, ai = null)
{
	local pf = PercorsoVeloce();
	/*
	 * Tetto al costo del percorso: circa 4 volte una strada dritta gia esistente.
	 * I rami troppo costosi (giri attorno ai laghi, tanta strada nuova) vengono scartati,
	 * cosi la ricerca finisce presto invece di esplorare mezza mappa.
	 */
	pf.cost.max_cost = AIMap.DistanceManhattan(da, a) * 100 * 4 + 10000;
	/*
	 * Penalita per strada nuova: lasciata al valore di default della libreria (40).
	 * Valori alti rendono la ricerca lentissima (esplora mezza mappa) e falliscono per limite di passi.
	 */
	pf.cost.no_existing_road = 40;
	pf.cost.max_bridge_length = 15;
	pf.cost.max_tunnel_length = 12;
	pf.InitializePath([da], [a]);

	local inizio = Util.Oggi();
	local percorso = false;
	local giri = 0;
	while (percorso == false && giri < 40) {
		percorso = pf.FindPath(5000);
		giri++;
		if (ai != null) ai.Manutenzione();
		AIController.Sleep(1);
	}
	local giorni = Util.Oggi() - inizio;
	if (percorso == false) {
		AILog.Info("Strade: ricerca interrotta dopo " + giorni + " giorni (troppo lunga)");
		return null;
	}
	if (percorso == null) {
		AILog.Info("Strade: nessun percorso possibile (" + giorni + " giorni di ricerca)");
		return null;
	}
	Util.Log("Strade: percorso trovato in " + giorni + " giorni", 2);
	return percorso;
}

/* Stima quanto costa costruire il percorso (modalita test, non spende nulla). */
function Strade::Stima(percorso)
{
	local test = AITestMode();
	local conto = AIAccounting();
	Strade._Costruisci(percorso, false);
	return conto.GetCosts();
}

/* Costruisce davvero il percorso. Ritorna true se non ci sono stati errori gravi. */
function Strade::Costruisci(percorso)
{
	return Strade._Costruisci(percorso, true);
}

function Strade::_Costruisci(percorso, reale)
{
	local errori = 0;
	local nodo = percorso;
	while (nodo != null) {
		local padre = nodo.GetParent();
		if (padre != null) {
			local t1 = nodo.GetTile();
			local t2 = padre.GetTile();
			if (AIMap.DistanceManhattan(t1, t2) == 1) {
				if (!Strade._Tratto(t1, t2, reale)) errori++;
			} else {
				/* Ponte o galleria */
				if (!AIBridge.IsBridgeTile(t1) && !AITunnel.IsTunnelTile(t1)) {
					if (AIRoad.IsRoadTile(t1) && reale) AITile.DemolishTile(t1);
					if (AITunnel.GetOtherTunnelEnd(t1) == t2) {
						if (!AITunnel.BuildTunnel(AIVehicle.VT_ROAD, t1)) {
							if (reale) Util.Errore("Strade: galleria fallita");
							errori++;
						}
					} else {
						local ponti = AIBridgeList_Length(AIMap.DistanceManhattan(t1, t2) + 1);
						ponti.Valuate(AIBridge.GetMaxSpeed);
						ponti.Sort(AIList.SORT_BY_VALUE, false);
						if (ponti.IsEmpty() || !AIBridge.BuildBridge(AIVehicle.VT_ROAD, ponti.Begin(), t1, t2)) {
							if (reale) Util.Errore("Strade: ponte fallito");
							errori++;
						}
					}
				}
			}
		}
		nodo = padre;
	}
	if (reale && errori > 0) Util.Avviso("Strade: " + errori + " tratti non costruiti");
	return errori == 0;
}

/* Un singolo tratto di strada, con qualche tentativo se c'e un veicolo in mezzo. */
function Strade::_Tratto(t1, t2, reale)
{
	for (local i = 0; i < 5; i++) {
		if (AIRoad.BuildRoad(t1, t2)) return true;
		local e = AIError.GetLastError();
		if (e == AIError.ERR_ALREADY_BUILT) return true;
		if (e == AIError.ERR_VEHICLE_IN_THE_WAY && reale) {
			AIController.Sleep(10);
			continue;
		}
		if (e == AIError.ERR_NOT_ENOUGH_CASH && reale) {
			if (!Banca.Assicura(5000)) return false;
			continue;
		}
		if (reale) Util.Errore("Strade: tratto fallito");
		return false;
	}
	return false;
}
