/*
 * SqualoAI - info.nut
 * Competitive AI for OpenTTD 15.x (API "15"). License: GPL v2 (see license.txt).
 */

class SqualoAI extends AIInfo
{
	function GetAuthor()        { return "DrKontos"; }
	function GetName()          { return "SqualoAI"; }
	function GetDescription()   { return "Competitive AI: bus lines between towns, trucks between industries, aircraft between big towns, freight trains, goods to towns, statues, advertising, exclusive transport rights, building funding, bribing local authorities and buying bankrupt competitors."; }
	function GetVersion()       { return 15; }
	function MinVersionToLoad() { return 1; }
	function GetDate()          { return "2026-11-16"; }
	function CreateInstance()   { return "SqualoAI"; }
	function GetShortName()     { return "SQLO"; }
	function GetAPIVersion()    { return "15"; }
	/* Mostrato nella lista delle AI e nel messaggio "l'AI si e bloccata" */
	function GetURL()           { return "https://github.com/drkontos/SqualoAI/issues"; }

	function GetSettings()
	{
		AddSetting({
			name = "max_linee",
			description = "Maximum number of bus lines",
			min_value = 1,
			max_value = 200,
			default_value = 60,
			step_size = 1,
			flags = CONFIG_INGAME
		});

		AddSetting({
			name = "usa_camion",
			description = "Use trucks for freight (industries and towns)",
			default_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});

		AddSetting({
			name = "max_rotte_merci",
			description = "Maximum number of truck routes",
			min_value = 1,
			max_value = 200,
			default_value = 60,
			step_size = 1,
			flags = CONFIG_INGAME
		});

		AddSetting({
			name = "usa_aerei",
			description = "Use aircraft between large, distant towns",
			default_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});

		AddSetting({
			name = "max_rotte_aeree",
			description = "Maximum number of air routes",
			min_value = 1,
			max_value = 100,
			default_value = 40,
			step_size = 1,
			flags = CONFIG_INGAME
		});

		AddSetting({
			name = "usa_treni",
			description = "Use freight trains (one train per single-track line)",
			default_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});

		AddSetting({
			name = "max_rotte_treni",
			description = "Maximum number of rail lines",
			min_value = 1,
			max_value = 50,
			default_value = 20,
			step_size = 1,
			flags = CONFIG_INGAME
		});

		AddSetting({
			name = "usa_statue",
			description = "Build statues in served towns",
			default_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});

		AddSetting({
			name = "usa_pubblicita",
			description = "Run advertising campaigns when station ratings are low",
			default_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});

		AddSetting({
			name = "usa_esclusive",
			description = "Buy exclusive transport rights where competitors operate",
			default_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});

		AddSetting({
			name = "usa_finanziamenti",
			description = "Fund new buildings in served towns (only with spare cash)",
			default_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});

		AddSetting({
			name = "usa_acquisizioni",
			description = "Buy bankrupt competitors when offered (after 5 years, cash only)",
			default_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});

		AddSetting({
			name = "usa_corruzione",
			description = "Bribe the local authority when the rating is too low",
			default_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});

		AddSetting({
			name = "debug",
			description = "Log level (0 = errors only, 1 = normal, 2 = detailed)",
			min_value = 0,
			max_value = 2,
			default_value = 1,
			step_size = 1,
			flags = CONFIG_INGAME
		});
	}
}

RegisterAI(SqualoAI());
