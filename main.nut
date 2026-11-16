/*
 * SqualoAI - main.nut
 * Ciclo principale, eventi, salvataggio e caricamento.
 *
 * Copyright (C) 2026 DrKontos
 * This program is free software; you can redistribute it and/or modify it under the terms of
 * the GNU General Public License version 2, as published by the Free Software Foundation.
 * It is distributed WITHOUT ANY WARRANTY. See license.txt for the full text.
 */

import("pathfinder.road", "RoadPathFinder", 4);
import("pathfinder.rail", "RailPathFinder", 1);

require("util.nut");
require("banca.nut");
require("strade.nut");
require("linee.nut");
require("veicoli.nut");
require("merci.nut");
require("aerei.nut");
require("ferrovie.nut");
require("autorita.nut");

class SqualoAI extends AIController
{
	linee = null;          /* array di tabelle linea (vedi linee.nut) */
	rotte_merci = null;    /* array di rotte camion (vedi merci.nut) */
	rotte_aeree = null;    /* array di rotte aeree (vedi aerei.nut) */
	prossimo_aereo = 0;    /* data dopo cui ritentare una rotta aerea */
	rotte_treni = null;    /* array di ferrovie (vedi ferrovie.nut) */
	prossimo_treno = 0;    /* data dopo cui ritentare una ferrovia */
	anno_inizio = -1;      /* anno in cui l'AI ha iniziato a giocare (per le acquisizioni) */
	coppie = null;         /* "a_b" -> data fino a cui la coppia di citta non va ritentata */
	da_vendere = null;     /* VehicleID -> true, bus mandati al deposito per la vendita */
	ultime_azioni = null;  /* "citta_azione" -> data dell'ultima volta */
	da_riparare = null;    /* GroupID -> true: gruppi con veicoli persi, strada da ricostruire */
	cargo = null;          /* CargoType passeggeri */
	dati_caricati = null;
	ultimo_mese = -1;
	ultimo_anno = -1;
	prossimo_tentativo = 0;

	constructor()
	{
		linee = [];
		rotte_merci = [];
		rotte_aeree = [];
		rotte_treni = [];
		coppie = {};
		da_vendere = {};
		ultime_azioni = {};
		da_riparare = {};
	}
}

function SqualoAI::Start()
{
	AILog.Info("SqualoAI avviata");
	ImpostaNome();
	AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
	AICompany.SetAutoRenewStatus(true);
	AICompany.SetAutoRenewMonths(0);
	AICompany.SetAutoRenewMoney(20000);

	cargo = Util.CargoPasseggeri();
	if (cargo == null) AILog.Error("Nessun cargo passeggeri in questa partita: non posso fare linee bus");
	Diagnosi();
	CostruisciSede();

	if (dati_caricati != null && "anno_inizio" in dati_caricati) anno_inizio = dati_caricati.anno_inizio;
	if (anno_inizio < 0) anno_inizio = AIDate.GetYear(Util.Oggi());

	if (dati_caricati != null) {
		Linee.Ripristina(this, dati_caricati);
		Merci.Ripristina(this, dati_caricati);
		Aerei.Ripristina(this, dati_caricati);
		Ferrovie.Ripristina(this, dati_caricati);
		Veicoli.PuliziaDepositi(this);
		dati_caricati = null;
	}

	while (true) {
		Manutenzione();

		if (Util.Oggi() >= prossimo_tentativo) {
			if (!CostruisciQualcosa()) {
				/* Niente da fare o fallito: riprova tra 15 giorni di gioco. */
				prossimo_tentativo = Util.Oggi() + 15;
			}
		}

		Banca.Restituisci();
		AIController.Sleep(50);
	}
}

/*
 * Alterna linee bus e rotte merci: si tenta prima il tipo di cui abbiamo meno,
 * e se fallisce si prova l'altro.
 */
function SqualoAI::CostruisciQualcosa()
{
	/* Aerei: solo con molta disponibilita, e al massimo un tentativo ogni 2 mesi se falliscono */
	if (AIController.GetSetting("usa_aerei") == 1 &&
	    rotte_aeree.len() < AIController.GetSetting("max_rotte_aeree") &&
	    Util.Oggi() >= prossimo_aereo && Banca.Disponibile() >= Aerei.CassaMinima()) {
		if (Aerei.CostruisciNuova(this)) return true;
		prossimo_aereo = Util.Oggi() + 60;
	}

	/* Treni: dopo che bus e camion sono avviati (almeno 4 rotte stradali) e con cassa */
	if (AIController.GetSetting("usa_treni") == 1 &&
	    rotte_treni.len() < AIController.GetSetting("max_rotte_treni") &&
	    linee.len() + rotte_merci.len() >= 4 &&
	    Util.Oggi() >= prossimo_treno && Banca.Disponibile() >= Ferrovie.CassaMinima()) {
		if (Ferrovie.CostruisciNuova(this)) return true;
		prossimo_treno = Util.Oggi() + 60;
	}

	local bus_ok = linee.len() < AIController.GetSetting("max_linee");
	local camion_ok = AIController.GetSetting("usa_camion") == 1 &&
	                  rotte_merci.len() < AIController.GetSetting("max_rotte_merci");
	if (camion_ok && (!bus_ok || rotte_merci.len() <= linee.len())) {
		if (Merci.CostruisciNuova(this)) return true;
		return bus_ok && Linee.CostruisciNuova(this);
	}
	if (bus_ok) {
		if (Linee.CostruisciNuova(this)) return true;
		return camion_ok && Merci.CostruisciNuova(this);
	}
	return false;
}

/*
 * Lavoro ordinario: eventi, vendite, controlli mensili.
 * Viene chiamato dal ciclo principale e anche durante le ricerche di strade lunghe,
 * cosi l'AI non smette di gestire bus e soldi mentre cerca un percorso.
 */
function SqualoAI::Manutenzione()
{
	GestisciEventi();
	Banca.Emergenza();
	Veicoli.Vendite(this);

	local anno = AIDate.GetYear(Util.Oggi());
	if (anno != ultimo_anno) {
		if (ultimo_anno != -1) RapportoAnnuale();
		ultimo_anno = anno;
	}

	local mese = AIDate.GetMonth(Util.Oggi());
	if (mese != ultimo_mese) {
		ultimo_mese = mese;
		Veicoli.Mensile(this);
		Merci.Mensile(this);
		Aerei.Mensile(this);
		Ferrovie.Mensile(this);
		RiparaStrade();
		CostruisciSede();
		Autorita.Mensile(this);
		Banca.Restituisci();
	}
}

/*
 * Per ogni gruppo con veicoli persi: ricerca di nuovo la strada tra le due fermate
 * e ricostruisce i pezzi mancanti (il pathfinder preferisce le strade esistenti,
 * quindi costruisce solo dove c'e il buco).
 */
function SqualoAI::RiparaStrade()
{
	foreach (gr, _ in da_riparare) {
		local rotta = null;
		foreach (l in linee) if (l.gr == gr) rotta = l;
		foreach (r in rotte_merci) if (r.gr == gr) rotta = r;
		if (rotta == null) continue;
		if (!AIStation.IsValidStation(rotta.sa) || !AIStation.IsValidStation(rotta.sb)) continue;
		local fa = AIRoad.GetRoadStationFrontTile(rotta.ta);
		local fb = AIRoad.GetRoadStationFrontTile(rotta.tb);
		AILog.Info("Riparo la strada tra " + AIStation.GetName(rotta.sa) + " e " + AIStation.GetName(rotta.sb));
		local percorso = Strade.Cerca(fa, fb, null);
		if (percorso == null) {
			AILog.Warning("Riparazione impossibile: nessun percorso");
			continue;
		}
		local costo = Strade.Stima(percorso);
		if (!Banca.Assicura(costo)) continue;
		if (Strade.Costruisci(percorso)) AILog.Info("Strada riparata (" + costo + ")");
		/* e anche il deposito deve essere collegato */
		local fd = AIRoad.GetRoadDepotFrontTile(rotta.dep);
		local pd = Strade.Cerca(fd, fa, null);
		if (pd != null && Banca.Assicura(Strade.Stima(pd))) Strade.Costruisci(pd);
	}
	da_riparare = {};
}

function SqualoAI::ProfittoGruppo(gr)
{
	local tot = 0;
	foreach (v, _ in AIVehicleList_Group(gr)) tot += AIVehicle.GetProfitLastYear(v);
	return tot;
}

/*
 * Una volta l'anno, a gennaio: un riassunto corto da leggere senza scorrere tutto il log.
 * Mostra soldi, numero di linee/rotte, le 5 che rendono di piu e quelle in perdita.
 */
function SqualoAI::RapportoAnnuale()
{
	local anno = AIDate.GetYear(Util.Oggi()) - 1;
	AILog.Info("##### RAPPORTO " + anno + " #####");
	AILog.Info("Saldo " + Banca.Saldo() + " | prestito " + AICompany.GetLoanAmount() +
	           " su " + AICompany.GetMaxLoanAmount() + " | veicoli " + AIVehicleList().Count());
	AILog.Info("Posti liberi (limite partita): stradali " + Util.PostiLiberi(AIVehicle.VT_ROAD) +
	           " | aerei " + Util.PostiLiberi(AIVehicle.VT_AIR) + " | treni " + Util.PostiLiberi(AIVehicle.VT_RAIL));

	local voci = [];
	local tot_bus = 0, tot_merci = 0;
	foreach (l in linee) {
		local p = ProfittoGruppo(l.gr);
		tot_bus += p;
		voci.append([p, "Bus " + AITown.GetName(l.a) + "-" + AITown.GetName(l.b) +
		                " [" + AIVehicleList_Group(l.gr).Count() + " bus]"]);
	}
	foreach (r in rotte_merci) {
		local p = ProfittoGruppo(r.gr);
		tot_merci += p;
		voci.append([p, AICargo.GetCargoLabel(r.cargo) + " " + AIIndustry.GetName(r.src) +
		                " [" + AIVehicleList_Group(r.gr).Count() + " camion]"]);
	}
	local tot_aerei = 0;
	foreach (r in rotte_aeree) {
		local p = ProfittoGruppo(r.gr);
		tot_aerei += p;
		voci.append([p, "Aereo " + AITown.GetName(r.a) + "-" + AITown.GetName(r.b) +
		                " [" + AIVehicleList_Group(r.gr).Count() + " aerei]"]);
	}
	local tot_treni = 0;
	foreach (r in rotte_treni) {
		local p = ProfittoGruppo(r.gr);
		tot_treni += p;
		voci.append([p, "Treno " + AICargo.GetCargoLabel(r.cargo) + " " + AIIndustry.GetName(r.src)]);
	}
	AILog.Info("Ferrovie " + rotte_treni.len() + " (profitto " + tot_treni + ")");
	AILog.Info("Linee bus " + linee.len() + " (profitto " + tot_bus + ") | rotte merci " +
	           rotte_merci.len() + " (profitto " + tot_merci + ") | rotte aeree " +
	           rotte_aeree.len() + " (profitto " + tot_aerei + ")");

	voci.sort(function(x, y) {
		if (x[0] > y[0]) return -1;
		if (x[0] < y[0]) return 1;
		return 0;
	});
	AILog.Info("Migliori:");
	for (local i = 0; i < voci.len() && i < 5; i++) AILog.Info("  " + voci[i][0] + "  " + voci[i][1]);
	local perdite = 0;
	foreach (v in voci) {
		if (v[0] < 0) {
			if (perdite == 0) AILog.Info("In perdita:");
			AILog.Info("  " + v[0] + "  " + v[1]);
			perdite++;
		}
	}
	if (perdite == 0) AILog.Info("Nessuna linea o rotta in perdita");

	local statue = 0, esclusive = 0;
	local me = Util.Me();
	foreach (t, _ in Autorita.CittaServite(this)) {
		if (AITown.HasStatue(t)) statue++;
		if (AITown.GetExclusiveRightsCompany(t) == me) esclusive++;
	}
	AILog.Info("Citta servite " + Autorita.CittaServite(this).len() + " | con nostra statua " + statue +
	           " | esclusive attive " + esclusive);
	/* Perche le azioni sulle citta partono o no: costo tipico contro soldi disponibili per extra */
	foreach (t, _ in Autorita.CittaServite(this)) {
		if (AITown.HasStatue(t)) continue;
		AILog.Info("Statua a " + AITown.GetName(t) + ": costo " + Util.CostoAzioneCitta(t, AITown.TOWN_ACTION_BUILD_STATUE) +
		           " | contanti oltre riserva " + (Banca.Saldo() - Banca.Riserva()) +
		           " | conti annuali ok " + Banca.SpesaExtraOk(0));
		break;
	}
	AILog.Info("##########################");
}

/* Riepilogo all'avvio: serve a capire subito perche l'AI potrebbe restare ferma. */
function SqualoAI::Diagnosi()
{
	AILog.Info("=== Diagnosi SqualoAI ===");
	AILog.Info("Mappa " + AIMap.GetMapSizeX() + "x" + AIMap.GetMapSizeY());
	AILog.Info("Saldo " + Banca.Saldo() + " | prestito " + AICompany.GetLoanAmount() + " su max " + AICompany.GetMaxLoanAmount());
	AILog.Info("Bus vietati alle AI: " + AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD) +
	           " | max veicoli stradali: " + AIGameSettings.GetValue("vehicle.max_roadveh"));
	local citta = AITownList();
	citta.Valuate(AITown.GetPopulation);
	local tot = citta.Count();
	local c500 = AIList(); c500.AddList(citta); c500.KeepAboveValue(500);
	local c150 = AIList(); c150.AddList(citta); c150.KeepAboveValue(150);
	AILog.Info("Citta: " + tot + " | sopra 500 ab.: " + c500.Count() + " | sopra 150 ab.: " + c150.Count());
	if (cargo != null) {
		local bus = Linee.ScegliBus(cargo);
		if (bus == null) {
			AILog.Error("Nessun bus utilizzabile! Dettaglio:");
			Linee.DiagnosiBus(cargo);
		} else {
			AILog.Info("Bus scelto: " + AIEngine.GetName(bus) + " (" + AIEngine.GetPrice(bus) + ")");
		}
	}
	local merci = Merci.CargoCamion();
	local nomi = "";
	foreach (c in merci) nomi += AICargo.GetCargoLabel(c) + " ";
	AILog.Info("Merci con camion disponibili: " + merci.len() + " (" + nomi + ")");
	local coal = null;
	foreach (c in Merci.CargoTreno()) if (AICargo.GetCargoLabel(c) == "COAL") coal = c;
	if (coal != null) {
		local tr = Ferrovie.ScegliTreno(coal);
		AILog.Info("Treno per COAL: " + ((tr == null) ? "nessuno" :
		           AIEngine.GetName(tr.loco) + " + vagoni " + AIEngine.GetName(tr.vagone) + " (binario " + tr.rt + ")"));
	}
	local tipo = Aerei.TipoAeroporto();
	if (tipo == AIAirport.AT_INVALID) {
		AILog.Info("Aeroporti: nessun tipo disponibile quest'anno");
	} else if (cargo != null) {
		local aereo = Aerei.ScegliAereo(cargo, Aerei.Piccolo(tipo), null, null);
		AILog.Info("Aeroporto tipo " + tipo + " (" + AIAirport.GetPrice(tipo) + ") | aereo: " +
		           ((aereo == null) ? "nessuno" : AIEngine.GetName(aereo) + " (" + AIEngine.GetPrice(aereo) + ")"));
	}
	AILog.Info("=========================");
}

/* Sede (HQ) 2x2 vicino alla citta piu grande servita, o alla piu grande della mappa. */
function SqualoAI::CostruisciSede()
{
	if (AICompany.GetCompanyHQ(AICompany.COMPANY_SELF) != AIMap.TILE_INVALID) return;

	local citta = AITownList();
	if (linee.len() > 0) {
		citta.Clear();
		foreach (l in linee) { citta.AddItem(l.a, 0); citta.AddItem(l.b, 0); }
	}
	citta.Valuate(AITown.GetPopulation);
	citta.Sort(AIList.SORT_BY_VALUE, false);
	if (citta.IsEmpty()) return;
	local centro = AITown.GetLocation(citta.Begin());

	local tiles = Util.Rettangolo(centro, 12);
	tiles.Valuate(AITile.IsBuildableRectangle, 2, 2);
	tiles.KeepValue(1);
	tiles.Valuate(AIMap.DistanceManhattan, centro);
	tiles.KeepAboveValue(3);
	tiles.Sort(AIList.SORT_BY_VALUE, true);
	local tentativi = 0;
	foreach (t, _ in tiles) {
		if (tentativi++ >= 20) break;
		if (!Banca.Assicura(20000)) return;
		if (AICompany.BuildCompanyHQ(t)) {
			AILog.Info("Sede costruita a " + AITown.GetName(citta.Begin()));
			return;
		}
	}
	Util.Log("Sede non costruita: " + AIError.GetLastErrorString(), 1);
}

function SqualoAI::ImpostaNome()
{
	if (AICompany.SetName("Squalo Trasporti")) return;
	for (local i = 2; i < 20; i++) {
		if (AICompany.SetName("Squalo Trasporti " + i)) return;
	}
}

function SqualoAI::GestisciEventi()
{
	while (AIEventController.IsEventWaiting()) {
		local e = AIEventController.GetNextEvent();
		switch (e.GetEventType()) {
			case AIEvent.ET_VEHICLE_CRASHED:
				Util.Avviso("Un nostro veicolo e stato distrutto");
				break;
			case AIEvent.ET_VEHICLE_LOST: {
				local perso = AIEventVehicleLost.Convert(e);
				local v = perso.GetVehicleID();
				if (AIVehicle.IsValidVehicle(v)) {
					Util.Avviso("Veicolo perso: " + AIVehicle.GetName(v) + " (strada interrotta?)");
					if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_ROAD) da_riparare[AIVehicle.GetGroupID(v)] <- true;
				}
				break;
			}
			case AIEvent.ET_COMPANY_ASK_MERGER: {
				ValutaAcquisizione(AIEventCompanyAskMerger.Convert(e));
				break;
			}
			case AIEvent.ET_COMPANY_IN_TROUBLE: {
				local guai = AIEventCompanyInTrouble.Convert(e);
				if (guai.GetCompanyID() == Util.Me()) Util.Avviso("La compagnia e in difficolta economica!");
				break;
			}
			default:
				break;
		}
	}
}

/*
 * Il gioco offre di comprare a poco prezzo una compagnia in fallimento.
 * (Le AI non possono lanciare un'acquisizione ostile: possono solo accettare queste offerte.)
 * Accettiamo se: impostazione attiva, siamo in gioco da almeno ANNI_PRIMA_ACQUISIZIONI anni,
 * e dopo l'acquisto restano in cassa la riserva + 100.000. Si paga solo con contanti, mai a debito.
 */
function SqualoAI::ValutaAcquisizione(offerta)
{
	local id = offerta.GetCompanyID();
	local valore = offerta.GetValue();
	local nome = AICompany.GetName(id);
	local anni = AIDate.GetYear(Util.Oggi()) - anno_inizio;
	AILog.Info("Offerta di acquisto: " + nome + " per " + valore);
	if (AIController.GetSetting("usa_acquisizioni") != 1) {
		AILog.Info("  rifiutata: acquisizioni disattivate");
		return;
	}
	if (anni < 5) {
		AILog.Info("  rifiutata: siamo in gioco da " + anni + " anni (servono 5)");
		return;
	}
	local libero = Banca.Saldo() - Banca.Riserva() - valore;
	if (libero < 100000) {
		AILog.Info("  rifiutata: contanti insufficienti (dopo l'acquisto resterebbero " + libero + ")");
		return;
	}
	if (offerta.AcceptMerger()) {
		AILog.Info("+ ACQUISITA " + nome + " per " + valore + ": i suoi veicoli continuano con i loro ordini");
	} else {
		Util.Errore("Acquisizione di " + nome + " fallita");
	}
}

function SqualoAI::Save()
{
	local l = [];
	foreach (x in linee) {
		l.append({ a = x.a, b = x.b, sa = x.sa, sb = x.sb, ta = x.ta, tb = x.tb, dep = x.dep, gr = x.gr });
	}
	local m = [];
	foreach (x in rotte_merci) {
		m.append({ src = x.src, dst = x.dst, citta = (("citta" in x) ? x.citta : -1), cargo = x.cargo,
		           sa = x.sa, sb = x.sb, ta = x.ta, tb = x.tb, dep = x.dep, gr = x.gr });
	}
	local ae = [];
	foreach (x in rotte_aeree) {
		ae.append({ a = x.a, b = x.b, sa = x.sa, sb = x.sb, ta = x.ta, tb = x.tb, gr = x.gr });
	}
	local tr = [];
	foreach (x in rotte_treni) {
		tr.append({ src = x.src, dst = x.dst, cargo = x.cargo, sa = x.sa, sb = x.sb,
		            ta = x.ta, tb = x.tb, dep = x.dep, rt = x.rt, gr = x.gr });
	}
	local c = {};
	foreach (k, v in coppie) c[k] <- v;
	return { linee = l, rotte_merci = m, rotte_aeree = ae, rotte_treni = tr, coppie = c, anno_inizio = anno_inizio };
}

function SqualoAI::Load(versione, dati)
{
	dati_caricati = dati;
}
