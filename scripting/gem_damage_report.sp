/*
  Description:
  When you die or round ends and you are still alive
  A left side menu shows who and how much you did damage to and who damaged you.
  
  Developed: 
  2007-12-20
  2022-5-3
  
  By:
  [30+]Gemeni (gemeni@30plus.ownit.se)
  [change to new syntax] niceday_zhu#github.com
  
  Version history:
  1.0.0 - First Version
  1.0.1 - Added number of hits
  1.0.2 - Added hitgroup information
  1.0.3 - Created a long and short version of the report. 
          If the Long version that includes hitgroups does not fit 
          in the panel, the short version is displayed
          Added coloring in the panel
  1.1.0 - Added option so you can turn damage report on and off, and also
          decide if it should be printed in menu or chat. Use /damage_report help to get info
          Big thanks to death_beam team since I used their code to learn about
          KeyValues!
  1.1.1 - Stripped chat output. 
          Resetting damage data on round start
  1.1.2 - Added total dmg taken/given and X indicator for kill/killed
  1.1.3 - Removed errors from translation stuff that was not completed
          Still looking at getting translation to work
  1.1.5 - Added support to show again the last report that was shown to a player
  1.1.6 - Fixed saving of settings on map end
  1.1.7 - Problem with bogus entries in damagereportsetting file
  1.1.8 - Added most kills info
  1.1.9 - Fixed memory leak
  1.1.10 - Checking if player still ingame before trying to display.
  1.1.11 - Sometimes it seems that the settings for the users isnt written to file. Forcing this more often now.
  1.1.12 - Making sure damage data is not shown to surviving players if they have switched it off.
  1.1.13 - Added extra option, /damage_report long|short - If hitboxdata should be shown or not
*/

#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>

// Definitions
#define MAXHITGROUPS 7
#define NROFOPTIONS 3
#define MAX_FILE_LEN 80

#define DrON  1
#define DrOFF 0
#define DrPop 1
#define DrChat 0
#define DrLong 1
#define DrShort 0

#define propOnOff 0
#define propPopChat 1
#define propShortLong 2

#define PLUGIN_VERSION "1.1.13-rc"

public Plugin myinfo =
{
    name = "Damage report [new syntax]",
    author = "[30+]Gemeni, niceday_zhu",
    description = "Reports who damaged you and who you damaged",
    version = PLUGIN_VERSION,
    url = "http://30plus.ownit.se/"
};

// Global variables
int g_DamageDone[MAXPLAYERS+1][MAXPLAYERS+1];
int g_HitsDone[MAXPLAYERS+1][MAXPLAYERS+1];
int g_HitboxDone[MAXPLAYERS+1][MAXPLAYERS+1][MAXHITGROUPS+1];

int g_DamageTaken[MAXPLAYERS+1][MAXPLAYERS+1];
int g_HitsTaken[MAXPLAYERS+1][MAXPLAYERS+1];
int g_HitboxTaken[MAXPLAYERS+1][MAXPLAYERS+1][MAXHITGROUPS+1];

char g_PlayerName[MAXPLAYERS+1][32];

int g_KilledPlayer[MAXPLAYERS+1][MAXPLAYERS+1];

int g_PlayerDROption[MAXPLAYERS+1][NROFOPTIONS];
char g_filenameSettings[MAX_FILE_LEN];
Handle KVSettings = INVALID_HANDLE;

int g_defaultPropOnOff = DrON;
int g_defaultPropChatPop = DrPop;
int g_defaultPropShortLong = DrLong;

bool g_lateLoaded;

// History stats
char g_HistDamageDone[MAXPLAYERS+1][512];
char g_HistDamageDoneLong[MAXPLAYERS+1][512];
int g_HistTotalDamageDone[MAXPLAYERS+1];
char g_HistDamageTaken[MAXPLAYERS+1][512];
char g_HistDamageTakenLong[MAXPLAYERS+1][512];
int g_HistTotalDamageTaken[MAXPLAYERS+1];


Handle g_versionConVar;

int g_maxClients;

char g_HitboxName[MAXHITGROUPS+1][20];

// Variable for Temp fix
int g_MenuCleared[MAXPLAYERS+1];


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_lateLoaded = late;
    return APLRes_Success;
}

// Hook events on plugin start
public void OnPluginStart()
{
    g_versionConVar = CreateConVar("sm_damage_report_version", PLUGIN_VERSION, "Damage report version", FCVAR_NONE|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
    SetConVarString(g_versionConVar, PLUGIN_VERSION);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_hurt", Event_PlayerHurt);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("round_start", EventRoundStart);

    HookEvent("player_disconnect", Event_PlayerDisconnect);
    HookEvent("player_connect", Event_PlayerConnect);

    RegConsoleCmd("damage_report", Command_DamageReport);
    RegConsoleCmd("last_damage_report", Command_LastDamageReport);
    RegConsoleCmd("ldr", Command_LastDamageReport);

    KVSettings=CreateKeyValues("DamageReportSetting");
    BuildPath(Path_SM, g_filenameSettings, MAX_FILE_LEN, "data/damagereportsetting.txt");
    if(!FileToKeyValues(KVSettings, g_filenameSettings))
    {
        KeyValuesToFile(KVSettings, g_filenameSettings);
    }       

    if(g_lateLoaded)
    {
        // Plugin was not loaded at beginning of round
        // Find settings for all players already connected
        for(int i = 1; i < g_maxClients; i++)
        {
            if(IsClientInGame(i) && !IsFakeClient(i))
            {
                FindSettingsForClient(i);
            }
        }
    }
    g_HitboxName[0] = "Body";
    g_HitboxName[1] = "Head";
    g_HitboxName[2] = "Chest";
    g_HitboxName[3] = "Stomach";
    g_HitboxName[4] = "Left arm";
    g_HitboxName[5] = "Right arm";
    g_HitboxName[6] = "Left leg";
    g_HitboxName[7] = "Right leg";
}

public Action Command_LastDamageReport(int client, int args)
{
    // Dont do anything if command comes from server
    if (client == 0) {
        return Plugin_Handled;
    }

    if ((strcmp(g_HistDamageDone[client], "") != 0) || (strcmp(g_HistDamageTaken[client], "") != 0)) {
        DisplayDamageReport(client, g_HistDamageDone[client] ,g_HistDamageDoneLong[client] ,g_HistDamageTaken[client], g_HistDamageTakenLong[client], g_HistTotalDamageDone[client], g_HistTotalDamageTaken[client]);
    }
    else {
        PrintToChat(client, "\x04No history to display");
    }

    return Plugin_Handled;
}
public Action Command_DamageReport(int client, int args)
{
    // Dont do anything if command comes from server
    if (client == 0) {
        return Plugin_Handled;
    }

    // If you send in to few or to many arguments. Tell them to ask for help 
    if (args != 1)
    {
        PrintToChat(client, "\x04Usage: /damage_report help");
        return Plugin_Handled;
    }

    char option[20];
    GetCmdArg(1, option, sizeof(option));

    if (strcmp(option, "on", false) == 0) {
        g_PlayerDROption[client][propOnOff] = DrON;
        PrintToChat(client, "\x04Damage report switched on");
    }
    else if (strcmp(option, "off", false) == 0) {
        g_PlayerDROption[client][propOnOff] = DrOFF;
        PrintToChat(client, "\x04Damage report switched off");
    }
    else if (strcmp(option, "popup", false) == 0) {
        g_PlayerDROption[client][propPopChat] = DrPop;
        PrintToChat(client, "\x04Damage report printed in popup menu");
    }
    else if (strcmp(option, "chat", false) == 0) {
        g_PlayerDROption[client][propPopChat] = DrChat;
        PrintToChat(client, "\x04Damage report printed in chat");
    }
    else if (strcmp(option, "short", false) == 0) {
        g_PlayerDROption[client][propShortLong] = DrShort;
        PrintToChat(client, "\x04Hitbox data will not be shown");
    }
    else if (strcmp(option, "long", false) == 0) {
        g_PlayerDROption[client][propShortLong] = DrLong;
        PrintToChat(client, "\x04Hitbox data will be shown");
    }
    else if (strcmp(option, "status", false) == 0) {
        if(g_PlayerDROption[client][propOnOff] == DrON) {
            PrintToChat(client, "\x04Damage report is switched on");
            if(g_PlayerDROption[client][propPopChat] == DrPop) {
                PrintToChat(client, "\x04Damage report is printed in popup menu");
            }
            else {
                PrintToChat(client, "\x04Damage report is printed in chat");
            }
            if(g_PlayerDROption[client][propShortLong] == DrShort) {
                PrintToChat(client, "\x04Hitbox data is not shown");
            }
            else {
                PrintToChat(client, "\x04Hitbox data is shown");
            }
        }
        else {
            PrintToChat(client, "\x04Damage report is switched off");
        }
    }
    else {
        char helpString1[200] = "/damage_report on (Turn it on) /damage_report off (Turn it off)\n";
        char helpString2[200] = "/damage_report popup (It will show as a left menu) /damage_report chat (It will show up in the chat)";
        char helpString3[200] = "/damage_report short (Will remove hitbox info)";
        char helpString4[200] = "/damage_report long (Will display hitbox info)";
        char helpString5[200] = "/damage_report status (See current damage report settings)";
        char helpString6[200] = "/last_damage_report or /ldr will display the last damage report that was shown to you";    
        PrintToChat(client, "\x04%s", helpString1);
        PrintToChat(client, "\x04%s", helpString2);
        PrintToChat(client, "\x04%s", helpString3);
        PrintToChat(client, "\x04%s", helpString4);
        PrintToChat(client, "\x04%s", helpString5);
        PrintToChat(client, "\x04%s", helpString6);
    }
  
    StoreSettingsForClient(client);
  
    return Plugin_Handled;
}


// Save all settings on map end
public void OnMapEnd() {
    // Save user settings to a file
    KvRewind(KVSettings);
    KeyValuesToFile(KVSettings, g_filenameSettings);

    clearAllDamageData();
}

public void OnMapStart() {
    g_maxClients = MaxClients;
    // Temp fix to for clearing menues on start
    for (int i=1; i<=g_maxClients; i++)
    {
        g_MenuCleared[i] = 0;
    }
}  

// Initializations to be done at the beginning of the round
public Action EventRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
    clearAllDamageData();
}


// In this event we store how much damage attacker did to victim in one array
// and how much damage victim took from attacker in another array
public Action Event_PlayerHurt(Handle event, const char[] name, bool dontBroadcast)
{
    int healthDmg = GetEventInt(event,"dmg_health");
    int hitgroup = GetEventInt(event, "hitgroup");

    int victim_id = GetEventInt(event, "userid");
    int attacker_id = GetEventInt(event, "attacker");

    int victim = GetClientOfUserId(victim_id);
    int attacker = GetClientOfUserId(attacker_id);

    // Log damage taken to the vicitm and damage done to the attacker
    g_DamageDone[attacker][victim] += healthDmg;
    g_HitsDone[attacker][victim]++;
    g_HitboxDone[attacker][victim][hitgroup]++;

    g_DamageTaken[victim][attacker] += healthDmg;
    g_HitsTaken[victim][attacker]++;
    g_HitboxTaken[victim][attacker][hitgroup]++;
}


// Upon player dead, check who is the victim and attacker and 
// Call up on the buildDamageString function
public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
    int victim_id = GetEventInt(event, "userid");
    int attacker_id = GetEventInt(event, "attacker");

    int victim = GetClientOfUserId(victim_id);
    int attacker = GetClientOfUserId(attacker_id);

    g_KilledPlayer[attacker][victim]=1;

    if ((g_PlayerDROption[victim][propOnOff] == DrON) && (!IsFakeClient(victim)) && IsClientInGame(victim)) {
    BuildDamageString(victim, attacker);  
    }
}

// Local Function where we loop through all attackers and victims for a client.
// if any damage is taken or done a timer is called that will display a Panel with the info.
void BuildDamageString (int in_victim, int in_attacker) {
    char damageReport[512];
    char damageReportLong[600];
    char damageDone[512];
    char damageTaken[512];
    char damageDoneLong[512];
    char damageTakenLong[512];
    char killer[10];
    char xkiller[10];
    char killed[10];
    char xkilled[10];
    int totalDmgTaken, totalDmgDone;

    // Loop through all damage where you inflicted damage
    for (int i=1; i<=g_maxClients; i++)
    {
        if(g_DamageDone[in_victim][i] >0)
        {
            if (g_KilledPlayer[in_victim][i] == 1) {
                killed=" (Killed)";
                xkilled="X ";
            }
            else {
                killed="";
                xkilled="--";
            }
            
            Format(damageDone, sizeof(damageDone), "%s%s%s [%d dmg, %d hits]%s\n", damageDone, xkilled, g_PlayerName[i], g_DamageDone[in_victim][i], g_HitsDone[in_victim][i], killed);
            Format(damageDoneLong, sizeof(damageDoneLong), "%s%s%s [%d dmg, %d hits]%s\n", damageDoneLong, xkilled, g_PlayerName[i], g_DamageDone[in_victim][i], g_HitsDone[in_victim][i], killed);
            Format(damageDoneLong, sizeof(damageDoneLong), "%s  ", damageDoneLong);
            totalDmgDone += g_DamageDone[in_victim][i];
            for(int j=0; j<=MAXHITGROUPS; j++) {
                if (g_HitboxDone[in_victim][i][j] > 0) {
                    Format(damageDoneLong, sizeof(damageDoneLong), "%s%s:%d ", damageDoneLong, g_HitboxName[j], g_HitboxDone[in_victim][i][j]);
                }
            }
            Format(damageDoneLong, sizeof(damageDoneLong), "%s\n", damageDoneLong);
        }
    }

    // If you did any damage, add it to the report
    if (strcmp(damageDone, "", false) != 0) {
        Format(damageReport, sizeof(damageReport), "%s\n%s", "Damage done:", damageDone);
        Format(damageReportLong, sizeof(damageReportLong), "%s\n%s", "Damage done:", damageDoneLong);
    }

    // Loop through all damage where you took damage
    for (int i=1; i<=g_maxClients; i++)
    {
        if(g_DamageTaken[in_victim][i] >0)
        {
            if (i == in_attacker) {
                killer=" (Killer)";
                xkiller="X ";
            }
            else {
                killer="";
                xkiller="--";
            }
            
            Format(damageTaken, sizeof(damageTaken), "%s%s%s [%d dmg, %d hits]%s\n", damageTaken, xkiller, g_PlayerName[i], g_DamageTaken[in_victim][i], g_HitsTaken[in_victim][i], killer);

            Format(damageTakenLong, sizeof(damageTakenLong), "%s%s%s [%d dmg, %d hits]%s\n", damageTakenLong, xkiller, g_PlayerName[i], g_DamageTaken[in_victim][i], g_HitsTaken[in_victim][i], killer);
            Format(damageTakenLong, sizeof(damageTakenLong), "%s  ", damageTakenLong);
            totalDmgTaken += g_DamageTaken[in_victim][i];
            for(int j=0; j<=MAXHITGROUPS; j++) {
                if (g_HitboxTaken[in_victim][i][j] > 0) {
                    Format(damageTakenLong, sizeof(damageTakenLong), "%s%s:%d ", damageTakenLong, g_HitboxName[j], g_HitboxTaken[in_victim][i][j]);
                }
            }
            Format(damageTakenLong, sizeof(damageTakenLong), "%s\n", damageTakenLong);
        }
    }

    // If you took any damage, add it to the report
    if (strcmp(damageTaken, "") != 0) {
        Format(damageReport, sizeof(damageReport), "%s%s\n%s", damageReport, "Damage taken:", damageTaken);
        Format(damageReportLong, sizeof(damageReportLong), "%s%s\n%s", damageReportLong, "Damage taken:", damageTakenLong);
    }

    // If damageReport is not empy
    if (strcmp(damageReport, "") != 0) {
        // store values if players what to view the last stats shown
        g_HistDamageDone[in_victim] = damageDone;
        g_HistDamageDoneLong[in_victim] = damageDoneLong;
        g_HistTotalDamageDone[in_victim] = totalDmgDone;

        g_HistDamageTaken[in_victim] = damageTaken;
        g_HistDamageTakenLong[in_victim] = damageTakenLong;
        g_HistTotalDamageTaken[in_victim] = totalDmgTaken;

        DisplayDamageReport(in_victim, damageDone ,damageDoneLong ,damageTaken, damageTakenLong, totalDmgDone, totalDmgTaken);
    }
}

void DisplayDamageReport(int in_victim, char[] damageDone ,char[] damageDoneLong, char[] damageTaken, char[] damageTakenLong, int totalDmgDone, int totalDmgTaken) {
    if (g_PlayerDROption[in_victim][propPopChat] == DrPop) {
        // Display damage report to the dead vicitm
        Handle pack;
        CreateDataTimer(1.0,DisplayDamageReportMenu, pack, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
        WritePackCell(pack, in_victim);
        //LogToGame("%s", damageReport);
        if (strlen(damageTakenLong)+strlen(damageDoneLong)<512-30 && (g_PlayerDROption[in_victim][propShortLong] == DrLong)) {
            WritePackString(pack, damageDoneLong);
            WritePackString(pack, damageTakenLong);
            WritePackCell(pack, totalDmgDone);
            WritePackCell(pack, totalDmgTaken);
        }
        else {
            WritePackString(pack, damageDone);
            WritePackString(pack, damageTaken);
            WritePackCell(pack, totalDmgDone);
            WritePackCell(pack, totalDmgTaken);
        }
    }
    else {
        if (strcmp(damageDoneLong, "", false) != 0) {
            PrintToChat(in_victim, "\x04\n--Victims (Total dmg:%d)--\n", totalDmgDone);
            PrintToChat(in_victim, "\x04%s", damageDoneLong);
        }
        if (strcmp(damageTakenLong, "", false) != 0) {
            PrintToChat(in_victim, "\x04--Attackers (Total dmg:%d)--\n", totalDmgTaken);
            PrintToChat(in_victim, "\x04%s", damageTakenLong);
        }
    }
}

// This is called by the timer.
// It checks if a menu/panel already is displayed ... if so
// let the timer try again after the delay, hoping the menu is closed
public Action DisplayDamageReportMenu(Handle timer, Handle pack) {
    char p_damageDone[512];
    char p_damageTaken[512];
    char victimItem[100];
    char attackerItem[100];
    int p_victim;
    int p_totalDmgDone;
    int p_totalDmgTaken;

    ResetPack(pack);
    p_victim = ReadPackCell(pack);
    ReadPackString(pack, p_damageDone, sizeof(p_damageDone));
    ReadPackString(pack, p_damageTaken, sizeof(p_damageTaken));
    p_totalDmgDone = ReadPackCell(pack);
    p_totalDmgTaken = ReadPackCell(pack);

    if (!IsClientInGame(p_victim)) {
        return Plugin_Stop;
    }  


    if (GetClientMenu(p_victim)!=MenuSource_None) {
        return Plugin_Continue;
    }

    Handle damageReportPanel = CreatePanel();

    if (strcmp(p_damageDone, "") != 0) {
        //LogToGame("%s", p_damageReport);

        Format(victimItem, sizeof(victimItem), "Victims (Total dmg:%d)", p_totalDmgDone);
        DrawPanelItem(damageReportPanel, victimItem);
        DrawPanelText(damageReportPanel, p_damageDone);
    }
    if (strcmp(p_damageTaken, "") != 0) {
        //LogToGame("%s", p_damageReport);
        Format(attackerItem, sizeof(attackerItem), "Attackers (Total dmg:%d)", p_totalDmgTaken);
        DrawPanelItem(damageReportPanel, attackerItem);
        DrawPanelText(damageReportPanel, p_damageTaken);
    }
    DrawPanelItem(damageReportPanel, "Exit");
    DrawPanelText(damageReportPanel, "Type \"/damage_report help\" in chat for settings");

    SendPanelToClient(damageReportPanel, p_victim, Handler_MyPanel, 8);
    CloseHandle(damageReportPanel);
    return Plugin_Stop;
}


// Display time timer will close my panel ... no need to handle anything
// CloseHandle seems to be called when the timer for the panel runs out
public int Handler_MyPanel(Handle menu, MenuAction action, int param1,int param2) {
    return;
}


// Store the name of the player at time of spawn. If player disconnects before
// round end, the name can still be displayed in the damage reports.
public Action Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast){
  int userid = GetEventInt(event,"userid");
  int client = GetClientOfUserId(userid);
  // Temp fix menu
  if (g_MenuCleared[client] == 0) {
    Handle TempPanel = CreatePanel();
    DrawPanelText(TempPanel, "DR Fix");
    SendPanelToClient(TempPanel, client, Handler_MyPanel, 1);
    g_MenuCleared[client] = 1;
    CloseHandle(TempPanel);
  }
  // Store Player names if they disconnect before round has ended
  char clientName[32];
  GetClientName(client, clientName, sizeof(clientName));
  strcopy(g_PlayerName[client], sizeof(g_PlayerName[]), clientName);
  
  // This shows that there is something strange when you spawn for the first time.
}

// Temp Fix
public Action Event_PlayerDisconnect(Handle event, const char[] name, bool dontBroadcast){
    int userid = GetEventInt(event,"userid");
    int client = GetClientOfUserId(userid);
    g_MenuCleared[client] = 0;

    g_HistDamageDone[client] = "";
    g_HistDamageDoneLong[client] = "";
    g_HistTotalDamageDone[client] = 0;

    g_HistDamageTaken[client] = "";
    g_HistDamageTakenLong[client] = "";
    g_HistTotalDamageTaken[client] = 0;
}

public Action Event_PlayerConnect(Handle event, const char[] name, bool dontBroadcast){
    int userid = GetEventInt(event,"userid");
    int client = GetClientOfUserId(userid);
    g_MenuCleared[client] = 0;

    g_HistDamageDone[client] = "";
    g_HistDamageDoneLong[client] = "";
    g_HistTotalDamageDone[client] = 0;

    g_HistDamageTaken[client] = "";
    g_HistDamageTakenLong[client] = "";
    g_HistTotalDamageTaken[client] = 0;
}

public void OnClientPostAdminCheck(int client) {
    FindSettingsForClient(client);
}

void FindSettingsForClient(int client) {
    char steamId[20];
    GetClientAuthId(client, AuthId_Steam2, steamId, 20);

    KvRewind(KVSettings);
    if(KvJumpToKey(KVSettings, steamId))
    {
        g_PlayerDROption[client][propOnOff]  = KvGetNum(KVSettings, "OnOff", g_defaultPropOnOff);
        g_PlayerDROption[client][propPopChat]  = KvGetNum(KVSettings, "PopChat", g_defaultPropChatPop);
        g_PlayerDROption[client][propShortLong]  = KvGetNum(KVSettings, "ShortLong", g_defaultPropChatPop);
    } else {
        g_PlayerDROption[client][propOnOff]  = g_defaultPropOnOff;
        g_PlayerDROption[client][propPopChat]  = g_defaultPropChatPop;
        g_PlayerDROption[client][propShortLong]  = g_defaultPropShortLong;
    }
    KvRewind(KVSettings);
}

public void StoreSettingsForClient(int client) {
    char steamId[40];
    GetClientAuthId(client, AuthId_Steam2, steamId, 20);

    if(StrContains(steamId, "steam", false) != -1) {
        
    KvRewind(KVSettings);
    if ((g_PlayerDROption[client][propOnOff] == g_defaultPropOnOff) && (g_PlayerDROption[client][propPopChat] == g_defaultPropChatPop) && (g_PlayerDROption[client][propShortLong] == g_defaultPropShortLong)) {
        if(KvJumpToKey(KVSettings, steamId))
        { 
        KvDeleteThis(KVSettings);
        }
    }
    else {
        KvJumpToKey(KVSettings, steamId, true);
        KvSetNum(KVSettings, "OnOff", g_PlayerDROption[client][propOnOff]);
        KvSetNum(KVSettings, "PopChat", g_PlayerDROption[client][propPopChat]);
        KvSetNum(KVSettings, "ShortLong", g_PlayerDROption[client][propShortLong]);
    }
    KvRewind(KVSettings);
    KeyValuesToFile(KVSettings, g_filenameSettings);
    }
}

// Check if there are any living players. If so, trigger a timer for them so they will see their damage report
// Calculate who did max damage and display it as a hint.
// clear global damage done/taken arrays
public Action Event_RoundEnd (Handle event, const char[] name, bool dontBroadcast)
{
    // Make sure that we have a normal round end
    // reason 16 is game commencing
    // other reasons are real round ends
    int reason = GetEventInt(event, "reason");
    if(reason == 16) {
        return;
    }

    int damage, hits, mostDamage, mostDamagePlayer, mostHits, kills, mostKills, mostKillsPlayer;

    // Display damage report to living players
    // -1 in the damage string will make sure noone will be shown as the (Killer)
    for (int i=1; i<=g_maxClients; i++)
    { 
        if(IsClientInGame (i)) {
            if ((g_PlayerDROption[i][propOnOff] == DrON) && IsClientConnected (i) && !IsFakeClient (i) && IsPlayerAlive (i)) {
                BuildDamageString(i, -1);        
            }
        }
    }

    // Finding out who did the most damage
    for (int i=1; i<=g_maxClients; i++)
    {
        damage = 0;
        hits = 0;
        for (int j=1; j<=g_maxClients; j++)
        { 
            damage = damage + g_DamageDone[i][j];
            hits = hits + g_HitsDone[i][j];
        }
        if (damage > mostDamage) {
            mostDamage = damage;
            mostDamagePlayer = i;
            mostHits = hits;
        }
    }

    mostKills = 0;
    for (int i=1; i<=g_maxClients; i++)
    {
        kills = 0;
        for (int j=1; j<=g_maxClients; j++)
        {
            kills = kills + g_KilledPlayer[i][j];
        }
        if (kills > mostKills) {
            mostKills = kills;
            mostKillsPlayer = i;
        }
    }

    // Display to all the player that did the most damage this round
    if(mostDamage > 0) {
        PrintToChatAll("\x04%s inflicted most damage, %d dmg in %d hits!", g_PlayerName[mostDamagePlayer], mostDamage, mostHits);
    }
    if(mostKills > 0) {
        PrintToChatAll("\x04Most kills:%s with %d kills" ,g_PlayerName[mostKillsPlayer], mostKills);
    }
}

public void clearAllDamageData() 
{
    // Clear all logged damage
    for (int i=1; i<=g_maxClients; i++)
    {
        for (int j=1; j<=g_maxClients; j++)
        { 
            g_DamageDone[i][j]=0;
            g_DamageTaken[i][j]=0;
            g_HitsDone[i][j]=0;
            g_HitsTaken[i][j]=0;
            g_KilledPlayer[i][j]=0;
            for (int k=0; k<=MAXHITGROUPS; k++) 
            {
                g_HitboxDone[i][j][k]=0;
                g_HitboxTaken[i][j][k]=0;
            }
        }
    }
}
