/*
 * SqualoAI - banca.nut
 * Gestione di contanti e prestito.
 * Regola: si chiede prestito solo per costruire; il prestito si restituisce appena c'e eccedenza.
 * Le azioni sulle citta (statue, esclusive, finanziamenti) usano solo soldi propri (saldo - prestito).
 */

class Banca {}

function Banca::Saldo()
{
	return AICompany.GetBankBalance(AICompany.COMPANY_SELF);
}

/* Soldi propri: contanti meno debito. */
function Banca::Netto()
{
	return Banca.Saldo() - AICompany.GetLoanAmount();
}

/*
 * Spese "extra" (statue, esclusive, finanziamenti): si fanno se, dopo la spesa,
 * restano in cassa la riserva e se l'ultimo anno l'azienda ha incassato piu di quanto
 * le costa l'esercizio. Il prestito al 2% non le blocca: un'AI che cresce lo tiene sempre alto.
 */
function Banca::SpesaExtraOk(importo)
{
	if (Banca.Saldo() - Banca.Riserva() < importo) return false;
	local me = AICompany.COMPANY_SELF;
	local entrate = 0, uscite = 0;
	for (local q = 1; q <= 4; q++) {
		entrate += AICompany.GetQuarterlyIncome(me, q);
		uscite += AICompany.GetQuarterlyExpenses(me, q);
	}
	if (uscite < 0) uscite = -uscite;  /* il segno dipende dalla versione: usiamo il valore assoluto */
	/* le uscite possono includere gli investimenti: basta che le entrate siano almeno il 60% */
	return entrate > 0 && entrate * 10 >= uscite * 6;
}

/* Quanto potremmo spendere al massimo, prestito compreso. */
function Banca::Disponibile()
{
	return Banca.Saldo() + AICompany.GetMaxLoanAmount() - AICompany.GetLoanAmount();
}

/* Riserva minima di contanti per non andare in rosso con i costi di esercizio. */
function Banca::Riserva()
{
	local veicoli = AIVehicleList();
	/*
	 * ~2 mesi di costi di esercizio: dai dati di gioco un veicolo costa circa 1.700/anno.
	 * (Prima era 1.500 a veicolo = quasi un anno intero: bloccava rimborsi e azioni sulle citta.)
	 */
	return Util.Max(20000, veicoli.Count() * 300);
}

/* Si assicura di avere in cassa almeno importo + riserva, chiedendo prestito se serve. */
function Banca::Assicura(importo)
{
	local serve = importo + Banca.Riserva();
	local saldo = Banca.Saldo();
	if (saldo >= serve) return true;

	local intervallo = AICompany.GetLoanInterval();
	local mancano = serve - saldo;
	local nuovo = AICompany.GetLoanAmount() + mancano;
	/* arrotonda al multiplo di intervallo superiore */
	if (nuovo % intervallo != 0) nuovo = nuovo + intervallo - (nuovo % intervallo);
	if (nuovo > AICompany.GetMaxLoanAmount()) {
		Util.Log("Banca: servono " + serve + " ma il prestito massimo non basta", 2);
		return false;
	}
	if (!AICompany.SetLoanAmount(nuovo)) {
		Util.Errore("Banca: impossibile aumentare il prestito a " + nuovo);
		return false;
	}
	Util.Log("Banca: prestito portato a " + nuovo, 2);
	return true;
}

/* Restituisce il prestito tenendo in cassa la riserva. */
function Banca::Restituisci()
{
	local prestito = AICompany.GetLoanAmount();
	if (prestito <= 0) return;
	local intervallo = AICompany.GetLoanInterval();
	local eccedenza = Banca.Saldo() - Banca.Riserva() * 2;
	if (eccedenza < intervallo) return;
	local rimborso = eccedenza - (eccedenza % intervallo);
	if (rimborso > prestito) rimborso = prestito;
	if (AICompany.SetLoanAmount(prestito - rimborso)) {
		Util.Log("Banca: restituiti " + rimborso + ", prestito residuo " + (prestito - rimborso), 2);
	} else {
		Util.Errore("Banca: rimborso di " + rimborso + " rifiutato (saldo " + Banca.Saldo() + ")");
	}
}

/* Se il saldo e negativo prova a coprirlo col prestito per evitare la bancarotta. */
function Banca::Emergenza()
{
	if (Banca.Saldo() < 0) {
		Util.Avviso("Banca: saldo negativo, provo a coprire col prestito");
		Banca.Assicura(0);
	}
}
