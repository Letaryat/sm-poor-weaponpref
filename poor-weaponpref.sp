#include <sourcemod>
#include <sdktools>
#include <cstrike>

Database g_db;

public Plugin myinfo = 
{
    name = "Weapon Preference Manager (SQLite)",
    author = "ChatGPT | github.com/letaryat <- download",
    description = "Player preferences for weapons USP and M4A1S & sqlite",
    version = "1.3"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_set", Command_SetPreference);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("item_purchase", Event_ItemPurchase);

    // Ładowanie SQLite
    Database.Connect(SQL_OnConnect, "weaponprefs_sqlite");
}

public void SQL_OnConnect(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogError("Could not connect to sqlite: %s", error);
        return;
    }

    g_db = db;

    g_db.Query(SQL_OnQuerySuccess, 
        "CREATE TABLE IF NOT EXISTS weapon_preferences (SteamID64 TEXT PRIMARY KEY, USP INTEGER DEFAULT 0, M4A1S INTEGER DEFAULT 0);"
    );
}

public void SQL_OnQuerySuccess(Database db, DBResultSet results, const char[] error, any data) 
{
    if (error[0])
    {
        LogError("SQL Error: %s", error);
    }
}

public Action Command_SetPreference(int client, int args)
{
    if (!IsClientInGame(client) || !IsClientAuthorized(client))
        return Plugin_Handled;

    if (g_db == null)
    {
        PrintToChat(client, "\x02[Pref] \x04 Database not worky.");
        return Plugin_Handled;
    }

    if (args < 1)
    {
        PrintToChat(client, "\x02[Pref] \x04 Use: !set usp or !set m4a1s");
        return Plugin_Handled;
    }

    char arg[16];
    GetCmdArg(1, arg, sizeof(arg));

    char steamid[32];
    GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));

    if (StrEqual(arg, "usp", false))
    {
        // Sprawdź obecną wartość i przełącz
        char query[256];
        Format(query, sizeof(query), "SELECT USP FROM weapon_preferences WHERE SteamID64='%s';", steamid);
        
        DataPack pack = new DataPack();
        pack.WriteCell(client);
        pack.WriteString("usp");
        
        g_db.Query(SQL_Callback_TogglePreference, query, pack);
    }
    else if (StrEqual(arg, "m4a1s", false))
    {
        // Sprawdź obecną wartość i przełącz
        char query[256];
        Format(query, sizeof(query), "SELECT M4A1S FROM weapon_preferences WHERE SteamID64='%s';", steamid);
        
        DataPack pack = new DataPack();
        pack.WriteCell(client);
        pack.WriteString("m4a1s");
        
        g_db.Query(SQL_Callback_TogglePreference, query, pack);
    }
    else
    {
        PrintToChat(client, "\x02[Pref] \x04 Use !set usp or !set m4a1s");
    }

    return Plugin_Handled;
}

public void SQL_Callback_TogglePreference(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = data;
    pack.Reset();
    
    int client = pack.ReadCell();
    char weapon[16];
    pack.ReadString(weapon, sizeof(weapon));
    
    delete pack;
    
    if (error[0])
    {
        LogError("SQL Error in TogglePreference: %s", error);
        return;
    }
    
    if (!IsClientInGame(client))
        return;

    char steamid[32];
    GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
    
    int currentValue = 0;
    int newValue = 1;
    
    // Sprawdź obecną wartość
    if (results != null && results.FetchRow())
    {
        currentValue = results.FetchInt(0);
        newValue = (currentValue == 1) ? 0 : 1;
    }
    
    char query[256];
    
    if (StrEqual(weapon, "usp"))
    {
        Format(query, sizeof(query), "INSERT INTO weapon_preferences (SteamID64, USP) VALUES ('%s', %d) ON CONFLICT(SteamID64) DO UPDATE SET USP = %d;", steamid, newValue, newValue);
        
        if (newValue == 1)
            PrintToChat(client, "\x02[Pref] \x04 USP-S set as default.");
        else
            PrintToChat(client, "\x02[Pref] \x04 USP-S is no longer default. You will be using P2000 from now on.");
    }
    else if (StrEqual(weapon, "m4a1s"))
    {
        Format(query, sizeof(query), "INSERT INTO weapon_preferences (SteamID64, M4A1S) VALUES ('%s', %d) ON CONFLICT(SteamID64) DO UPDATE SET M4A1S = %d;", steamid, newValue, newValue);
        
        if (newValue == 1)
            PrintToChat(client, "\x02[Pref] \x04 M4A1-S set as default.");
        else
            PrintToChat(client, "\x02[Pref] \x04 M4A1-S is no longer default. You will be using M4A4 from now on.");
    }
    
    g_db.Query(SQL_OnQuerySuccess, query);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return;
    if (GetClientTeam(client) != CS_TEAM_CT) return;

    char steamid[32];
    GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));

    char query[256];
    Format(query, sizeof(query), "SELECT USP FROM weapon_preferences WHERE SteamID64='%s';", steamid);
    g_db.Query(SQL_Callback_GiveUSP, query, client);
}

public void SQL_Callback_GiveUSP(Database db, DBResultSet results, const char[] error, any data)
{
    int client = data;
    
    if (error[0])
    {
        LogError("SQL Error in GiveUSP: %s", error);
        return;
    }
    
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) 
        return;

    // Jeśli nie ma wyników, gracz nie ma preferencji USP
    if (results == null || !results.FetchRow()) 
        return;

    int uspPref = results.FetchInt(0);
    
    if (uspPref == 1)
    {
        // Używamy timera żeby dać broń po spawn
        CreateTimer(0.1, Timer_GiveUSP, client);
    }
}

public void Event_ItemPurchase(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClientInGame(client)) return;

    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));

    // DEBUGGING - sprawdź wszystkie kupowane bronie
    PrintToServer("[DEBUG] Player %N bought weapon: '%s'", client, weapon);

    // Sprawdź czy kupuje M4A4 (może być różnie nazywane w eventach)
    if (!StrEqual(weapon, "m4a1", false) && 
        !StrEqual(weapon, "m4a4", false) && 
        !StrEqual(weapon, "rifle_m4a1", false) &&
        !StrEqual(weapon, "weapon_m4a1", false) &&
        !StrEqual(weapon, "weapon_m4a4", false)) 
    {
        return;
    }

    PrintToServer("[DEBUG] M4 weapon detected, checking preferences for %N", client);

    char steamid[32];
    GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));

    char query[256];
    Format(query, sizeof(query), "SELECT M4A1S FROM weapon_preferences WHERE SteamID64='%s';", steamid);
    g_db.Query(SQL_Callback_ReplaceM4, query, client);
}

public void SQL_Callback_ReplaceM4(Database db, DBResultSet results, const char[] error, any data)
{
    int client = data;
    
    if (error[0])
    {
        LogError("SQL Error in ReplaceM4: %s", error);
        return;
    }
    
    if (!IsClientInGame(client)) return;
    
    PrintToServer("[DEBUG] SQL_Callback_ReplaceM4 called for %N", client);
    
    if (results == null || !results.FetchRow()) 
    {
        PrintToServer("[DEBUG] No M4A1S preference found for %N", client);
        return;
    }

    int m4a1s = results.FetchInt(0);
    PrintToServer("[DEBUG] M4A1S preference for %N: %d", client, m4a1s);
    
    if (m4a1s == 1)
    {
        PrintToServer("[DEBUG] Starting M4 replacement timer for %N", client);
        // Krótkie opóźnienie przed wymianą broni
        CreateTimer(0.1, Timer_ReplaceM4, client);
    }
}

public Action Timer_ReplaceM4(Handle timer, any client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    // Usuń M4A4 (prawidłowa nazwa klasy)
    StripWeaponByName(client, "weapon_m4a1"); // M4A4 w CSS nazywa się weapon_m4a1_s
    
    // Daj M4A1-S
    int newWeapon = GivePlayerItem(client, "weapon_m4a1_silencer");
    if (newWeapon != -1)
    {
        EquipPlayerWeapon(client, newWeapon);
        PrintToChat(client, "\x02[Pref] \x04 You bought M4A1-S!");
        PrintToServer("[DEBUG] M4A1-S given to %N", client);
    }
    else
    {
        PrintToServer("[DEBUG] FAILED to give M4A1-S to %N", client);
    }

    return Plugin_Stop;
}

void StripWeaponByName(int client, const char[] weaponName)
{
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, weaponName)) != -1)
    {
        if (GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
        {
            RemovePlayerItem(client, entity);
            AcceptEntityInput(entity, "Kill");
        }
    }
}

public Action Timer_GiveUSP(Handle timer, any client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    // Usuń obecną broń z slot 1 (secondary)
    int weapon = GetPlayerWeaponSlot(client, 1);
    if (weapon != -1)
    {
        char weaponClass[32];
        GetEntityClassname(weapon, weaponClass, sizeof(weaponClass));
        
        // Usuń tylko jeśli to P2000
        if (StrEqual(weaponClass, "weapon_hkp2000"))
        {
            RemovePlayerItem(client, weapon);
            AcceptEntityInput(weapon, "Kill");
            
            // Krótkie opóźnienie przed daniem USP-S
            CreateTimer(0.05, Timer_DelayedUSP, client);
        }
    }

    return Plugin_Stop;
}

public Action Timer_DelayedUSP(Handle timer, any client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    // Daj USP-S
    int newWeapon = GivePlayerItem(client, "weapon_usp_silencer");
    if (newWeapon != -1)
    {
        EquipPlayerWeapon(client, newWeapon);
        PrintToChat(client, "\x02[Pref] \x04 You got USP-S!");
        PrintToServer("[DEBUG] USP-S given and equipped to %N", client);
    }
    else
    {
        PrintToServer("[DEBUG] FAILED to give USP-S to %N", client);
    }

    return Plugin_Stop;
}