/*
 * SqualoAI - util.nut
 * Funzioni di servizio: log, min/max, rettangoli di caselle, cargo passeggeri.
 */

class Util {}

function Util::Log(msg, livello = 1)
{
	/* livello 0-1 si vede sempre; livello 2 solo con debug = 2 */
	if (livello <= 1 || AIController.GetSetting("debug") >= livello) AILog.Info(msg);
}

function Util::Avviso(msg)
{
	AILog.Warning(msg);
}

function Util::Errore(msg)
{
	AILog.Error(msg + " [" + AIError.GetLastErrorString() + "]");
}

function Util::Min(a, b) { return (a < b) ? a : b; }
function Util::Max(a, b) { return (a > b) ? a : b; }
function Util::Abs(a) { return (a < 0) ? -a : a; }

function Util::Me()
{
	return AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
}

function Util::Oggi()
{
	return AIDate.GetCurrentDate();
}

/* Lista di caselle in un quadrato di lato 2*r+1 attorno a centro, dentro i bordi mappa. */
function Util::Rettangolo(centro, r)
{
	local x = AIMap.GetTileX(centro);
	local y = AIMap.GetTileY(centro);
	local x1 = Util.Max(1, x - r);
	local y1 = Util.Max(1, y - r);
	local x2 = Util.Min(AIMap.GetMapSizeX() - 2, x + r);
	local y2 = Util.Min(AIMap.GetMapSizeY() - 2, y + r);
	local l = AITileList();
	l.AddRectangle(AIMap.GetTileIndex(x1, y1), AIMap.GetTileIndex(x2, y2));
	return l;
}

/* Spostamenti verso le 4 caselle vicine. */
function Util::Direzioni()
{
	local mx = AIMap.GetMapSizeX();
	return [1, -1, mx, -mx];
}

/*
 * Quanti veicoli di quel tipo possiamo ancora comprare prima del limite della partita
 * (impostazione "massimo veicoli per compagnia"). 0 se il tipo e vietato alle AI.
 */
function Util::PostiLiberi(tipo)
{
	if (AIGameSettings.IsDisabledVehicleType(tipo)) return 0;
	local nome = "vehicle.max_roadveh";
	if (tipo == AIVehicle.VT_AIR) nome = "vehicle.max_aircraft";
	else if (tipo == AIVehicle.VT_RAIL) nome = "vehicle.max_trains";
	else if (tipo == AIVehicle.VT_WATER) nome = "vehicle.max_ships";
	local lista = AIVehicleList();
	lista.Valuate(AIVehicle.GetVehicleType);
	lista.KeepValue(tipo);
	return AIGameSettings.GetValue(nome) - lista.Count();
}

function Util::CargoPasseggeri()
{
	local lista = AICargoList();
	foreach (c, _ in lista) {
		if (AICargo.HasCargoClass(c, AICargo.CC_PASSENGERS)) return c;
	}
	return null;
}

/* Copia le chiavi di una AIList in un array Squirrel (evita foreach annidati sulla stessa lista). */
function Util::InArray(lista)
{
	local a = [];
	foreach (k, _ in lista) a.append(k);
	return a;
}

/* Costo di un'azione sull'autorita locale, stimato in modalita test. -1 se non fattibile. */
function Util::CostoAzioneCitta(citta, azione)
{
	if (!AITown.IsActionAvailable(citta, azione)) return -1;
	local test = AITestMode();
	local conto = AIAccounting();
	if (!AITown.PerformTownAction(citta, azione)) return -1;
	return conto.GetCosts();
}
