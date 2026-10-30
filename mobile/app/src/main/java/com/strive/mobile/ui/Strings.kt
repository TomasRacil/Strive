package com.strive.mobile.ui

/**
 * Minimal translation layer: two maps and a lookup. No resource plumbing, so
 * adding a language is one map rather than a build configuration.
 */
object Strings {

    private val en = mapOf(
        "app.name" to "Strive",
        "nav.home" to "Home",
        "nav.train" to "Train",
        "nav.history" to "History",
        "nav.settings" to "Settings",

        "home.streak" to "Day streak",
        "home.subtitle" to "Welcome back",
        "home.total" to "Sessions",
        "home.week" to "This week",
        "home.recent" to "Recent activity",
        "home.empty" to "No workouts yet",
        "home.emptyHint" to "Start a session and it will appear here.",
        "home.start" to "Start training",

        "train.title" to "Training",
        "train.exercise" to "Exercise",
        "train.weight" to "Weight",
        "train.reps" to "Reps",
        "train.rir" to "RIR",
        "train.logSet" to "Log set",
        "train.finish" to "Finish session",
        "train.rest" to "Rest",
        "train.skip" to "Skip rest",
        "train.sets" to "sets",
        "train.suggested" to "Suggested",
        "train.startHint" to "Start a session to log sets.",
        "train.summary" to "Session saved",

        "history.title" to "History",
        "history.empty" to "Nothing recorded yet.",
        "history.delete" to "Delete",
        "history.volume" to "Volume",
        "history.duration" to "Duration",

        "settings.title" to "Settings",
        "settings.appearance" to "Appearance",
        "settings.theme" to "Theme",
        "settings.theme.system" to "System",
        "settings.theme.dark" to "Dark",
        "settings.theme.light" to "Light",
        "settings.units" to "Units",
        "settings.unit.kg" to "Kilograms",
        "settings.unit.lb" to "Pounds",
        "settings.language" to "Language",
        "settings.about" to "About",
        "settings.aboutText" to "Strive is a local-first strength tracker. Your data stays on this device.",
        "settings.privacy" to "Privacy",
        "settings.privacyText" to "No account, no server, no analytics. Everything you log is stored on the phone and, when paired, on your watch.",
        "settings.version" to "Version",

        "watch.title" to "Garmin watch",
        "watch.subtitle" to "Send your plan to the watch app and pull logged sets back.",
        "watch.search" to "Find watches",
        "watch.connecting" to "Searching…",
        "watch.none" to "No watches found. Make sure the watch is paired and the Strive app is installed.",
        "watch.send" to "Send plan",
        "watch.connected" to "Connected",
        "watch.notConnected" to "Not connected"
    )

    private val cs = mapOf(
        "app.name" to "Strive",
        "nav.home" to "Domů",
        "nav.train" to "Trénink",
        "nav.history" to "Historie",
        "nav.settings" to "Nastavení",

        "home.streak" to "Dní v řadě",
        "home.subtitle" to "Vítej zpět",
        "home.total" to "Tréninků",
        "home.week" to "Tento týden",
        "home.recent" to "Poslední aktivita",
        "home.empty" to "Zatím žádné tréninky",
        "home.emptyHint" to "Začni trénink a objeví se tady.",
        "home.start" to "Začít trénink",

        "train.title" to "Trénink",
        "train.exercise" to "Cvik",
        "train.weight" to "Váha",
        "train.reps" to "Opakování",
        "train.rir" to "RIR",
        "train.logSet" to "Zapsat sérii",
        "train.finish" to "Ukončit trénink",
        "train.rest" to "Pauza",
        "train.skip" to "Přeskočit pauzu",
        "train.sets" to "série",
        "train.suggested" to "Doporučeno",
        "train.startHint" to "Začni trénink pro zápis sérií.",
        "train.summary" to "Trénink uložen",

        "history.title" to "Historie",
        "history.empty" to "Zatím nic nezapsáno.",
        "history.delete" to "Smazat",
        "history.volume" to "Objem",
        "history.duration" to "Trvání",

        "settings.title" to "Nastavení",
        "settings.appearance" to "Vzhled",
        "settings.theme" to "Motiv",
        "settings.theme.system" to "Podle systému",
        "settings.theme.dark" to "Tmavý",
        "settings.theme.light" to "Světlý",
        "settings.units" to "Jednotky",
        "settings.unit.kg" to "Kilogramy",
        "settings.unit.lb" to "Libry",
        "settings.language" to "Jazyk",
        "settings.about" to "O aplikaci",
        "settings.aboutText" to "Strive je lokální tracker silového tréninku. Data zůstávají v tomto zařízení.",
        "settings.privacy" to "Soukromí",
        "settings.privacyText" to "Žádný účet, žádný server, žádná analytika. Vše, co zapíšeš, zůstává v telefonu a po spárování v hodinkách.",
        "settings.version" to "Verze",

        "watch.title" to "Garmin hodinky",
        "watch.subtitle" to "Pošli plán do aplikace v hodinkách a stáhni zapsané série zpět.",
        "watch.search" to "Najít hodinky",
        "watch.connecting" to "Hledám…",
        "watch.none" to "Žádné hodinky nenalezeny. Zkontroluj spárování a instalaci aplikace Strive.",
        "watch.send" to "Poslat plán",
        "watch.connected" to "Připojeno",
        "watch.notConnected" to "Nepřipojeno"
    )

    fun t(lang: String, key: String): String {
        val table = if (lang == "cs") cs else en
        return table[key] ?: en[key] ?: key
    }

    /** "1 set" / "3 sets", and the Czech forms, in one place. */
    fun sets(lang: String, count: Int): String = when (lang) {
        "cs" -> if (count == 1) "1 série" else "$count série"
        else -> if (count == 1) "1 set" else "$count sets"
    }
}
