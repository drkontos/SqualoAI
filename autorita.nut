/*
 * SqualoAI - autorita.nut
 * Azioni sulle autorita locali delle citta servite:
 *   alberi (rating, legale ed economico), statua, pubblicita, diritti esclusivi,
 *   finanziamento edifici, corruzione.
 * Regola di prudenza: statue, esclusive e finanziamenti si fanno solo con soldi propri
 * (saldo meno prestito), mai indebitandosi.
 */

class Autorita {}

const MESI_TRA_PUBBLICITA = 3;
const MESI_TRA_FINANZIAMENTI = 3;
const MESI_TRA_CORRUZIONI = 6;
const RATING_FERMATA_BASSO = 55;   /* % sotto cui si fa pubblicita */

/* Passa troppo poco tempo dall'ultima volta che abbiamo fatto questa azione in questa citta? */
function Autorita::Recente(ai, citta, nome, mesi)
{
	local k = citta + "_" + nome;
	return (k in ai.ultime_azioni) && (Util.Oggi() - ai.ultime_azioni[k] < mesi * 30);
}

function Autorita::Segna(ai, citta, nome)
{
	ai.ultime_azioni[citta + "_" + nome] <- Util.Oggi();
}

/*
 * Esegue un'azione se i soldi propri coprono costo * margine.
 * Con con_prestito = true (solo per sbloccare una costruzione) puo usare il prestito.
 */
function Autorita::Esegui(citta, azione, nome, margine, con_prestito = false)
{
	local costo = Util.CostoAzioneCitta(citta, azione);
	if (costo < 0) return false;
	if (con_prestito) {
		if (!Banca.Assicura(costo)) return false;
	} else if (!Banca.SpesaExtraOk(costo * margine)) {
		Util.Log(nome + " a " + AITown.GetName(citta) + " rimandata: costa " + costo, 2);
		return false;
	}
	if (!AITown.PerformTownAction(citta, azione)) {
		Util.Errore(nome + " fallita a " + AITown.GetName(citta));
		return false;
	}
	AILog.Info(nome + " a " + AITown.GetName(citta) + " (" + costo + ")");
	return true;
}

/* Ci sono stazioni di altre compagnie vicino al centro? */
function Autorita::Concorrenti(citta)
{
	local me = Util.Me();
	local tiles = Util.Rettangolo(AITown.GetLocation(citta), 12);
	tiles.Valuate(AITile.IsStationTile);
	tiles.KeepValue(1);
	foreach (t, _ in tiles) {
		local proprietario = AITile.GetOwner(t);
		if (proprietario != me && AICompany.ResolveCompanyID(proprietario) != AICompany.COMPANY_INVALID) return true;
	}
	return false;
}

/* Pianta alberi attorno alla citta: alza il rating in modo legale e costa poco. */
function Autorita::PiantaAlberi(citta, quanti)
{
	local tiles = Util.Rettangolo(AITown.GetLocation(citta), 10);
	tiles.Valuate(AITile.IsBuildable);
	tiles.KeepValue(1);
	tiles.Valuate(AITile.HasTreeOnTile);
	tiles.KeepValue(0);
	tiles.Valuate(AIBase.RandItem);
	tiles.Sort(AIList.SORT_BY_VALUE, true);
	local piantati = 0;
	foreach (t, _ in tiles) {
		if (piantati >= quanti) break;
		if (!Banca.Assicura(500)) break;
		if (AITile.PlantTree(t)) piantati++;
	}
	if (piantati > 0) Util.Log("Piantati " + piantati + " alberi a " + AITown.GetName(citta), 1);
	return piantati;
}

/* Rating basso: prima alberi, poi statua, infine corruzione. */
function Autorita::Recupera(ai, citta)
{
	local me = Util.Me();
	local r = AITown.GetRating(citta, me);
	Util.Log("Rating basso a " + AITown.GetName(citta) + " (" + r + "), provo a recuperare", 1);

	Autorita.PiantaAlberi(citta, 25);

	if (AIController.GetSetting("usa_statue") && !AITown.HasStatue(citta)) {
		if (Autorita.Esegui(citta, AITown.TOWN_ACTION_BUILD_STATUE, "Statua", 1, true)) return;
	}

	r = AITown.GetRating(citta, me);
	if (r != AITown.TOWN_RATING_NONE && r <= AITown.TOWN_RATING_POOR &&
	    AIController.GetSetting("usa_corruzione") &&
	    !Autorita.Recente(ai, citta, "corruzione", MESI_TRA_CORRUZIONI)) {
		/* Se scoperti il rating crolla: la si tenta al massimo ogni 6 mesi per citta. */
		if (Autorita.Esegui(citta, AITown.TOWN_ACTION_BRIBE, "Corruzione", 1, true)) {
			Autorita.Segna(ai, citta, "corruzione");
		}
	}
}

/* Citta servite, senza doppioni. */
function Autorita::CittaServite(ai)
{
	local t = {};
	foreach (l in ai.linee) {
		t[l.a] <- true;
		t[l.b] <- true;
	}
	foreach (r in ai.rotte_aeree) {
		t[r.a] <- true;
		t[r.b] <- true;
	}
	return t;
}

/* Rating peggiore (in %) delle nostre fermate in quella citta. */
function Autorita::RatingFermate(ai, citta)
{
	local peggiore = 100;
	foreach (l in ai.linee) {
		if (l.a == citta && AIStation.IsValidStation(l.sa)) peggiore = Util.Min(peggiore, AIStation.GetCargoRating(l.sa, ai.cargo));
		if (l.b == citta && AIStation.IsValidStation(l.sb)) peggiore = Util.Min(peggiore, AIStation.GetCargoRating(l.sb, ai.cargo));
	}
	return peggiore;
}

function Autorita::Mensile(ai)
{
	local me = Util.Me();
	foreach (citta, _ in Autorita.CittaServite(ai)) {
		if (!AITown.IsValidTown(citta)) continue;

		/* 1. Rating dell'autorita locale */
		local r = AITown.GetRating(citta, me);
		if (r != AITown.TOWN_RATING_NONE && r <= AITown.TOWN_RATING_POOR) {
			Autorita.Recupera(ai, citta);
		}

		/* 2. Statua: rating stabile in quella citta, una volta sola */
		if (AIController.GetSetting("usa_statue") && !AITown.HasStatue(citta)) {
			Autorita.Esegui(citta, AITown.TOWN_ACTION_BUILD_STATUE, "Statua", 1);
		}

		/* 3. Diritti esclusivi: solo se c'e concorrenza da tagliare fuori */
		if (AIController.GetSetting("usa_esclusive")) {
			local titolare = AITown.GetExclusiveRightsCompany(citta);
			if (titolare != me && Autorita.Concorrenti(citta)) {
				Autorita.Esegui(citta, AITown.TOWN_ACTION_BUY_RIGHTS, "Diritti esclusivi", 1);
			}
		}

		/* 4. Pubblicita: se le nostre fermate hanno un rating basso */
		if (AIController.GetSetting("usa_pubblicita") &&
		    !Autorita.Recente(ai, citta, "pubblicita", MESI_TRA_PUBBLICITA) &&
		    Autorita.RatingFermate(ai, citta) < RATING_FERMATA_BASSO) {
			local azione = (AITown.GetPopulation(citta) > 2500) ? AITown.TOWN_ACTION_ADVERTISE_MEDIUM : AITown.TOWN_ACTION_ADVERTISE_SMALL;
			if (Autorita.Esegui(citta, azione, "Pubblicita", 2)) Autorita.Segna(ai, citta, "pubblicita");
		}

		/* 5. Finanziamento edifici: piu abitanti = piu passeggeri. Solo con molta liquidita. */
		if (AIController.GetSetting("usa_finanziamenti") &&
		    !Autorita.Recente(ai, citta, "finanziamento", MESI_TRA_FINANZIAMENTI)) {
			if (Autorita.Esegui(citta, AITown.TOWN_ACTION_FUND_BUILDINGS, "Finanziamento edifici", 2)) {
				Autorita.Segna(ai, citta, "finanziamento");
			}
		}
	}
}
