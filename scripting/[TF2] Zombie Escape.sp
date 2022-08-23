#include <sourcemod>

#include <sdktools>

#include <sdkhooks>

#include <clientprefs>

#include <tf2>

#include <tf2_stocks>

#include <tf2attributes>

#include <tf2items>

#include <gimme>

#include <tf_econ_data>

#include <morecolors>

#include <tf2utils>

public Plugin myinfo = {
  name = "[TF2] Zombie Escape",
  author = "Korki",
  description = "Zombie Escape gamemode for Team Fortress 2.",
  version = SOURCEMOD_VERSION,
  url = "https://esatefekorkmaz.github.io/"
};

enum {
  TFWeaponSlot_DisguiseKit = 3,
    TFWeaponSlot_Watch = 4,
    TFWeaponSlot_DestroyKit = 4,
    TFWeaponSlot_BuildKit = 5
}

ConVar allowPointCommands;
ConVar defaultTeam;
ConVar unbalanceLimit;
ConVar autoTeamBalance;
ConVar respawnTime;
ConVar holiday;
ConVar airDashCount;
Handle standHereHud;
Handle statusHud;
Handle restoreSpeedTimer[MAXPLAYERS + 1];
Handle g_hWearableEquip;
bool isGameStarted;
bool playerFrozen[MAXPLAYERS + 1];
bool playerSlowedDown[MAXPLAYERS + 1];
bool isZombie[MAXPLAYERS + 1];
bool isSpeedSet[MAXPLAYERS + 1];
bool isStunned[MAXPLAYERS + 1];
bool b_Transmit[MAXPLAYERS + 1] = false;
int time;

public void OnPluginStart() {
  for (new i = 1; i <= MaxClients; i++) {
    if (IsValidClient(i)) {
      SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
    }
  }

  LoadTranslations("tf2ze.phrases");
  RegServerCmd("ze_map_say", Command_MapSay);
  RegServerCmd("ze_map_timer", Command_MapTimer);
  AddCommandListener(Suicide, "kill");
  AddCommandListener(Suicide, "explode");
  HookEvent("teamplay_setup_finished", Event_teamplay_setup_finished);
  HookEvent("teamplay_round_start", Event_teamplay_round_start);
  HookEvent("teamplay_round_win", Event_teamplay_round_win);
  HookEvent("teamplay_round_stalemate", Event_teamplay_round_win);
  HookEvent("player_spawn", Event_player_spawn);
  HookEvent("player_death", Event_player_death);
  allowPointCommands = FindConVar("sv_allow_point_servercommand");
  defaultTeam = FindConVar("mp_humans_must_join_team");
  unbalanceLimit = FindConVar("mp_teams_unbalance_limit");
  autoTeamBalance = FindConVar("mp_autoteambalance");
  respawnTime = FindConVar("mp_disable_respawn_times");
  holiday = FindConVar("tf_forced_holiday");
  airDashCount = FindConVar("tf_scout_air_dash_count");
  standHereHud = CreateHudSynchronizer();
  statusHud = CreateHudSynchronizer();
  g_hWearableEquip = EndPrepSDKCall();

  if (!g_hWearableEquip)
    SetFailState("Failed to create call: CBasePlayer::EquipWearable");
}

public void PlaySoundToAll(char[] soundPath) {
  for (int i = 1; i <= MaxClients; i++) {
    if (IsClientInGame(i)) {
      ClientCommand(i, "playgamesound %s", soundPath);
    }
  }
}

public void CheckPlayers() {
  if (isGameStarted) {
    int zombieCount = 0;
    int humanCount = 0;
    for (int i = 1; i <= MaxClients; i++) {
      if (IsClientInGame(i)) {
        if (GetClientTeam(i) == 2) {
          zombieCount++;
        } else if (GetClientTeam(i) == 3 && IsPlayerAlive(i)) {
          humanCount++;
        }
      }
    }

    if (zombieCount == 0) {
      ForceTeamWin(3);
    } else if (humanCount == 0) {
      ForceTeamWin(2);
    }
  }
}

public void ForceTeamWin(int team) {
  int flags = GetCommandFlags("mp_forcewin");
  SetCommandFlags("mp_forcewin", flags &= ~FCVAR_CHEAT);
  ServerCommand("mp_forcewin %i", team);
  SetCommandFlags("mp_forcewin", flags);
}

public void OnClientDisconnect(int client) {
  CheckPlayers();
}

public void OnMapStart() {
  CreateTimer(1.0, CheckPlayersTimer, _, TIMER_REPEAT);
  CreateTimer(120.0, AuthorBroadcast, _, TIMER_REPEAT);
  SetConVarString(defaultTeam, "blue", false);
  SetConVarString(allowPointCommands, "always", false);
  unbalanceLimit.IntValue = 0; // This will remove the limit of the max players in a team
  autoTeamBalance.IntValue = 0; // This will prevent autobalancing
  airDashCount.IntValue = 0; // This will let Scouts double jump only with Atomizer
  respawnTime.IntValue = 1;
  holiday.IntValue = 2; // We need this cause of zombie cosmetics require the Halloween holiday
}

public Action AuthorBroadcast(Handle timer) {
  CPrintToChatAll("%t", "Author");
  return Plugin_Handled;
}

public Action CheckPlayersTimer(Handle timer) {
  CheckPlayers();
  return Plugin_Handled;
}

public OnClientPutInServer(client) {
  SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

ArrayList PickRandomClients(int team, int count) {
  ArrayList arr = new ArrayList();
  for (int i = 1; i <= MaxClients; i++) {
    if (IsClientInGame(i) && GetClientTeam(i) == team && IsPlayerAlive(i)) {
      arr.Push(i);
    }
  }

  arr.Sort(Sort_Random, Sort_Integer);
  arr.Resize(count);
  return arr;
}

public Action: JoinTeam(client, const String: command[], argc) {
  if (isGameStarted) {
    CPrintToChat(client, "%t", "CannotChangeTeam");
    return Plugin_Handled;
  }

  return Plugin_Continue;
}

public Action: Suicide(client, const String: command[], argc) {
  CPrintToChat(client, "%t", "CannotSuicide");
  return Plugin_Handled;
}

public void Zombify(int client) {
  CreateTimer(0.1, DelayZombify, client);
}

public Action Hook_SetTransmit(int entity, int client) {
  SetFlags(entity);
  if (b_Transmit[client]) {
    return Plugin_Handled;
  }

  return Plugin_Continue;
}

void SetFlags(int edict) {
  if (GetEdictFlags(edict) & FL_EDICT_ALWAYS) {
    SetEdictFlags(edict, (GetEdictFlags(edict) ^ FL_EDICT_ALWAYS));
  }
}

public void ToggleZombieSkin(int entity, bool boolean, bool uber) {
  TFClassType class = view_as < TFClassType > (GetEntProp(entity, Prop_Send, "m_iClass"));
  int skinToSet = -1;
  int teamNum = -1;
  if (IsValidClient(entity)) {
    if (HasEntProp(entity, Prop_Send, "m_iTeamNum"))
      teamNum = GetEntProp(entity, Prop_Send, "m_iTeamNum");
    else
      teamNum = GetEntProp(entity, Prop_Send, "m_iTeam");

    switch (boolean) {
    case true: {
      switch (teamNum) {
      case 2: {
        if (class != TFClass_Spy) {
          if (uber) {
            skinToSet = 6;
          } else {
            skinToSet = 4;
          }
        } else {
          if (uber) {
            skinToSet = 24;
          } else {
            skinToSet = 22;
          }
        }

        SetEntProp(entity, Prop_Send, "m_nForcedSkin", skinToSet);
        SetEntProp(entity, Prop_Send, "m_bForcedSkin", 1);
      }
      }
    }

    case false: {
      SetEntProp(entity, Prop_Send, "m_nForcedSkin", 0);
      SetEntProp(entity, Prop_Send, "m_bForcedSkin", 0);
    }
    }
  }
}

public Action DelayZombify(Handle timer, int client) {
  TFClassType class = TF2_GetPlayerClass(client);

  switch (class) {
  case (TFClass_Scout):
    CreateVoodoo(client, 5617);

  case (TFClass_Soldier):
    CreateVoodoo(client, 5618);

  case (TFClass_Pyro):
    CreateVoodoo(client, 5624);

  case (TFClass_DemoMan):
    CreateVoodoo(client, 5620);

  case (TFClass_Heavy):
    CreateVoodoo(client, 5619);

  case (TFClass_Engineer):
    CreateVoodoo(client, 5621);

  case (TFClass_Medic):
    CreateVoodoo(client, 5622);

  case (TFClass_Sniper):
    CreateVoodoo(client, 5625);

  case (TFClass_Spy):
    CreateVoodoo(client, 5623);
  }
  return Plugin_Handled;
}

public void CreateVoodoo(int client, int index) {
  if (IsClientInGame(client) && GetClientTeam(client) == 2) {
    int voodoo = CreateEntityByName("tf_wearable");
    SetEntProp(voodoo, Prop_Send, "m_iItemDefinitionIndex", index);
    SetEntProp(voodoo, Prop_Send, "m_bInitialized", 1);
    SetEntProp(voodoo, Prop_Send, "m_iEntityQuality", 13);
    SetEntProp(voodoo, Prop_Send, "m_iEntityLevel", 1);
    SetEntProp(voodoo, Prop_Send, "m_bValidatedAttachedEntity", 1);
    DispatchSpawn(voodoo);
    TF2Util_EquipPlayerWearable(client, voodoo);
    TF2Attrib_AddCustomPlayerAttribute(client, "player skin override", 1.0);
    TF2Attrib_AddCustomPlayerAttribute(client, "zombiezombiezombiezombie", 1.0);
    TF2Attrib_AddCustomPlayerAttribute(client, "SPELL: Halloween voice modulation", 1.0);
  }
}

public void MultiplyPlayerHealth(int client, int multiply) {
  DataPack dataPack;
  CreateDataTimer(0.2, SetHealthTimer, dataPack);
  WritePackCell(dataPack, client);
  WritePackCell(dataPack, multiply);
}

public Action SetHealthTimer(Handle timer, DataPack dataPack) {
  ResetPack(dataPack, false);
  new client = ReadPackCell(dataPack);
  if (client) {
    if (GetClientTeam(client) == 2) {
      new melee = GetPlayerWeaponSlot(client, 2);
      int multiply = ReadPackCell(dataPack);
      int defaultHealth = GetClientHealth(client);
      int newHealth = TF2_GetPlayerMaxHealth(client) * multiply;
      int attribHealth = newHealth - defaultHealth;
      TF2Attrib_SetByName(melee, "max health additive bonus", float(attribHealth));
      SetEntityHealth(client, newHealth);
    }
  }
  return Plugin_Handled;
}

public void RegenPlayer(int client) {
  TF2Attrib_SetByName(GetPlayerWeaponSlot(client, 2), "max health additive bonus", 0.0);
  TF2_RegeneratePlayer(client);
  CreateTimer(0.1, ResetHealthTimer, client);
}

public Action ResetHealthTimer(Handle timer, int client) {
  SetEntityHealth(client, TF2_GetPlayerMaxHealth(client));
  return Plugin_Handled;
}

stock int TF2_GetPlayerMaxHealth(int client) {
  return GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, client);
}

public Action: Event_teamplay_round_win(Handle: event, const String: name[], bool: dontBroadcast) {
  isGameStarted = false;
}

public Action: Event_player_spawn(Handle: event, const String: name[], bool: dontBroadcast) {
  new client = GetClientOfUserId(GetEventInt(event, "userid"));
  TFClassType playerClass = TF2_GetPlayerClass(client);
  RegenPlayer(client);
  if (IsClientInGame(client)) {
    if (GetClientTeam(client) == 2) {
      SetZombie(client);
      CreateTimer(0.1, SetClientSpeedTimer, client);
    } else if (GetClientTeam(client) == 3) {
      isZombie[client] = false;
      ToggleZombieSkin(client, false, false);
      RestrictWeapons(client);
      TF2Attrib_RemoveCustomPlayerAttribute(client, "damage force increase");
      HumanAttributes(client, playerClass);
      CreateTimer(0.1, SetClientSpeedTimer, client);
      SetHudTextParams(-1.0, 0.90, 99999.0, 0, 0, 255, 255, 0, 1.0, 1.0, 1.0);
      ShowSyncHudText(client, statusHud, "%t", "Human");
    }
  }
}

public void HumanAttributes(int client, TFClassType playerClass) {
  new primarySlot = GetPlayerWeaponSlot(client, 0);
  new secondarySlot = GetPlayerWeaponSlot(client, 1);
  new meleeSlot = GetPlayerWeaponSlot(client, 2);
  if (playerClass == TFClass_Soldier) {
    TF2Attrib_SetByName(primarySlot, "self dmg push force decreased", 0.0);
  }

  if (playerClass == TFClass_DemoMan) {
    TF2Attrib_SetByName(secondarySlot, "health regen", 20.0);
    TF2Attrib_RemoveByName(secondarySlot, "sticky arm time bonus");
    TF2Attrib_SetByName(secondarySlot, "sticky arm time penalty", 0.8);
    TF2Attrib_SetByName(secondarySlot, "self dmg push force decreased", 0.0);
  }

  if (playerClass == TFClass_Engineer) {
    TF2Attrib_SetByName(meleeSlot, "bidirectional teleport", 1.0)
    TF2Attrib_SetByName(meleeSlot, "mod wrench builds minisentry", 1.0);
    TF2Attrib_SetByName(meleeSlot, "engy disposable sentries", 1.0);
    TF2Attrib_SetByName(meleeSlot, "alt fire teleport to spawn", 0.0);
    TF2Attrib_SetByName(meleeSlot, "mod teleporter cost", 9999.0);
  }

  if (playerClass == TFClass_Medic) {
    TF2Attrib_SetByName(secondarySlot, "ubercharge rate bonus", 2.0);
  }
}

public void TF2_OnConditionAdded(int client, TFCond cond) {
  if (IsClientInGame(client) && GetClientTeam(client) == 2) {
    switch (cond) {
    case TFCond_Charging:
      TF2_RemoveCondition(client, cond);
    case TFCond_Jarated:
      UpdateClientSpeed(client, 230.0);
    }
  }
}

public void TF2_OnConditionRemoved(int client, TFCond cond) {
  if (IsClientInGame(client) && GetClientTeam(client) == 2) {
    switch (cond) {
    case TFCond_Jarated:
      restoreSpeedTimer[client] = CreateTimer(0.1, RestoreSpeedTimer, GetClientSerial(client));
    }
  }
}

public void Knockback(inflictor, client, float amount) {
  SetEntPropEnt(client, Prop_Send, "m_hGroundEntity", -1);
  float vector[3];
  float inflictorLocation[3];
  float clientLocation[3];
  GetEntPropVector(inflictor, Prop_Send, "m_vecOrigin", inflictorLocation);
  GetClientAbsOrigin(client, clientLocation);
  MakeVectorFromPoints(clientLocation, inflictorLocation, vector);
  NormalizeVector(vector, vector);
  ScaleVector(vector, amount);
  vector[2] = 10.0;
  TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vector);
}

public void UpdateClientSpeed(int client, float speed) {
  if (IsClientInGame(client)) {
    TFClassType playerClass = TF2_GetPlayerClass(client);
    TF2Attrib_RemoveCustomPlayerAttribute(client, "move speed bonus");
    switch (playerClass) {
    case TFClass_Scout:
      TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed / 400.0);
    case TFClass_Soldier:
      TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed / 240.0);
    case TFClass_Pyro:
      TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed / 300.0);
    case TFClass_DemoMan:
      TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed / 280.0);
    case TFClass_Heavy:
      TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed / 230.0);
    case TFClass_Engineer:
      TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed / 300.0);
    case TFClass_Medic:
      TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed / 320.0);
    case TFClass_Sniper:
      TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed / 300.0);
    case TFClass_Spy:
      TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed / 300.0);
    }
  }
}

public void SetClientSpeed(int client) {
  if (IsClientInGame(client)) {
    TFClassType playerClass = TF2_GetPlayerClass(client);
    TF2Attrib_RemoveCustomPlayerAttribute(client, "move speed bonus");
    if (GetClientTeam(client) == 2) {
      switch (playerClass) {
      case TFClass_Scout:
        TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 352.0 / 400.0);
      case TFClass_Soldier:
        TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.25);
      case TFClass_Pyro:
        TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.25);
      case TFClass_DemoMan:
        TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.25);
      case TFClass_Heavy:
        TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.25);
      case TFClass_Engineer:
        TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.25);
      case TFClass_Medic:
        TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.25);
      case TFClass_Sniper:
        TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.25);
      case TFClass_Spy:
        TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.25);
      }
    }

    if (GetClientTeam(client) == 3) {
      switch (playerClass) {
      case TFClass_Scout:
        TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 336.0 / 400.0);
      }
    }
  }
}

public Action RestoreSpeedTimer(Handle timer, int serial) {
  int client = GetClientFromSerial(serial);
  if (client) {
    SetClientSpeed(client);
    playerSlowedDown[client] = false;
  }

  restoreSpeedTimer[client] = null;
  return Plugin_Continue;
}

public Action SetClientSpeedTimer(Handle timer, int client) {
  if (client) {
    SetClientSpeed(client);
  }

  return Plugin_Continue;
}

public void Infect(int client) {
  PlaySoundToAll("npc/fast_zombie/fz_scream1.wav");
  PrintCenterText(client, "%t", "YoureInfected");
  ChangeTeamInstantly(client, 2);
  TF2_RegeneratePlayer(client);
  ToggleZombieSkin(client, true, false);
  SetZombie(client);
  CheckPlayers();
}

public void ChangeTeamInstantly(int client, int team) {
  SetEntProp(client, Prop_Send, "m_lifeState", 2);
  ChangeClientTeam(client, team);
  SetEntProp(client, Prop_Send, "m_lifeState", 0);
}

public Action: OnTakeDamage(client, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3], damagecustom) {
  if (isGameStarted) {
    if (IsClientInGame(client)) {
      if (GetClientTeam(client) == 3) {
        if (IsValidClient(attacker) && GetClientTeam(attacker) == 2) {
          new m_nPlayerCond = FindSendPropInfo("CTFPlayer", "m_nPlayerCond");
          new cond = GetEntData(client, m_nPlayerCond);
          if (cond != 32) {
            new health = GetEntProp(client, Prop_Data, "m_iHealth");

            if (TF2_GetPlayerClass(client) == TFClass_Spy || TF2_GetPlayerClass(client) == TFClass_DemoMan) {
              float newHealth = health - damage;
              if (newHealth <= 0.0) {
                Infect(client);
                return Plugin_Handled;
              }
            } else {
              Infect(client);
              return Plugin_Handled;
            }
          }
        }
      } else if (GetClientTeam(client) == 2) {
        if (IsValidClient(attacker) && GetClientTeam(attacker) == 3) {
          decl String: inf[32];
          decl String: remotePipe[32] = "tf_projectile_pipe_remote";
          GetEdictClassname(inflictor, inf, sizeof(inf));
          TFClassType clientClass = TF2_GetPlayerClass(client);
          TFClassType attackerClass = TF2_GetPlayerClass(attacker);
          if (attackerClass == TFClass_Sniper && damagecustom == TF_CUSTOM_HEADSHOT) {
            damage *= 5;
            if (!isStunned[client]) {
              TF2_StunPlayer(client, 1.0, 0.0, TF_STUNFLAGS_BIGBONK);
              isStunned[client] = true;
              CreateTimer(2.0, StunTimer, client);
            }

            return Plugin_Changed;
          }

          if (StrEqual(inf, remotePipe, false) && attackerClass == TFClass_DemoMan) {
            if (!isStunned[client]) {
              TF2_StunPlayer(client, 1.0, 0.0, TF_STUNFLAGS_BIGBONK);
              isStunned[client] = true;
              CreateTimer(2.0, StunTimer, client);
            }
          }

          if (attackerClass == TFClass_Spy && IsWeaponSlotActive(attacker, 2)) {
            if (damagecustom == TF_CUSTOM_BACKSTAB) {
              damage = 2000.0;
              TF2_StunPlayer(client, 2.0, 0.0, TF_STUNFLAGS_SMALLBONK);
              TF2_AddCondition(attacker, TFCond_Ubercharged, 5.0);
              TF2_AddCondition(attacker, TFCond_SpeedBuffAlly, 5.0);
              return Plugin_Changed;
            } else {
              damage = 1000.0;
              return Plugin_Changed;
            }
          }

          delete restoreSpeedTimer[client];
          decl String: sentry[32] = "obj_sentrygun";
          if (!playerSlowedDown[client]) {
            if (StrEqual(inf, sentry, false)) {
              if (clientClass == TFClass_Heavy) {
                Knockback(inflictor, client, -70.0);
              } else {
                UpdateClientSpeed(client, 70.0);
                Knockback(inflictor, client, -150.0);
              }
            } else {
              if (attackerClass == TFClass_Heavy && IsWeaponSlotActive(attacker, 0)) {
                if (clientClass == TFClass_Heavy) {
                  Knockback(inflictor, client, -150.0);
                } else {
                  UpdateClientSpeed(client, 70.0);
                  Knockback(inflictor, client, -320.0);
                }
              } else if (attackerClass == TFClass_Pyro) {
                UpdateClientSpeed(client, 230.0);
              }

              UpdateClientSpeed(client, 150.0);
            }

            playerSlowedDown[client] = true;
          }

          restoreSpeedTimer[client] = CreateTimer(1.0, RestoreSpeedTimer, GetClientSerial(client));
        }
      }
    }
  }

  return Plugin_Continue;
}

public Action StunTimer(Handle timer, int client) {
  isStunned[client] = false;
  return Plugin_Handled;
}

public Action: Event_player_death(Handle: event, const String: name[], bool: dontBroadcast) {
  new client = GetClientOfUserId(GetEventInt(event, "userid"));
  new deathFlag = GetEventInt(event, "death_flags");
  if (isGameStarted) {
    if (IsClientInGame(client) && GetClientTeam(client) == 3) {
      if (deathFlag != 32) {
        ChangeClientTeam(client, 2);
      }
    }
  }

  CheckPlayers();
  return Plugin_Continue;
}

public Action: Event_teamplay_round_start(Handle: event, const String: name[], bool: dontBroadcast) {
  isGameStarted = false;
  SetConVarString(defaultTeam, "blue", false);
  for (new i = 1; i <= MaxClients; i++) {
    if (IsClientInGame(i) && GetClientTeam(i) == 2) {
      ChangeTeamInstantly(i, 3);
      TF2_RespawnPlayer(i);
      if (playerFrozen[i]) {
        SetEntityMoveType(i, MOVETYPE_WALK);
        playerFrozen[i] = false;
      }
    }
  }

  return Plugin_Handled;
}

public void OnClientConnected(int client) {
  playerFrozen[client] = false;
  playerSlowedDown[client] = false;
  isSpeedSet[client] = false;
  isZombie[client] = false;
  isStunned[client] = false;
}

public Action: Event_teamplay_setup_finished(Handle: event, const String: name[], bool: dontBroadcast) {
  isGameStarted = true;
  SetConVarString(defaultTeam, "red", false);
  int humanCount = 0;
  for (new i = 1; i <= MaxClients; i++) {
    if (IsClientInGame(i)) {
      if (IsPlayerAlive(i) && GetClientTeam(i) == 3) {
        humanCount++;
      }

    }
  }

  if (humanCount > 0) {
    ArrayList clients = new ArrayList();
    if (humanCount <= 5) {
      clients = PickRandomClients(3, 1);
    } else if (humanCount <= 10) {
      clients = PickRandomClients(3, 2);
    } else if (humanCount <= 15) {
      clients = PickRandomClients(3, 3);
    } else if (humanCount >= 20) {
      clients = PickRandomClients(3, 4);
    }

    for (int i; i < clients.Length; i++) {
      ChangeClientTeam(clients.Get(i), 2);
      playerFrozen[clients.Get(i)] = true;
      TF2_RespawnPlayer(clients.Get(i));
      SetEntityMoveType(clients.Get(i), MOVETYPE_NONE);
      CreateTimer(10.0, SetMoveTypeBack, clients.Get(i));
      CPrintToChatAll("%t", "HasBeenInfected", clients.Get(i));
    }

    delete clients;
  }

  PlaySoundToAll("ambient/creatures/town_zombie_call1.wav");

  return Plugin_Handled;
}

public void RestrictWeapons(int client) {
  TFClassType playerClass = TF2_GetPlayerClass(client);
  if (playerClass == TFClass_Scout) {
    new bannedPrimary[] = {772};
    new bannedMelee[] = {44, 648};
    for (new i = 0; i < sizeof(bannedPrimary); i++) {
      if (GetIndexOfWeaponSlot(client, 0) == bannedPrimary[i]) {
        giveitem(client, 13);
      }
    }

    for (new i = 0; i < sizeof(bannedMelee); i++) {
      if (GetIndexOfWeaponSlot(client, 2) == bannedMelee[i]) {
        giveitem(client, 0);
      }
    }
  }

  if (playerClass == TFClass_Soldier) {
    new bannedPrimary[] = {441};
    for (new i = 0; i < sizeof(bannedPrimary); i++) {
      if (GetIndexOfWeaponSlot(client, 0) == bannedPrimary[i]) {
        giveitem(client, 18);
      }
    }
  }

  if (playerClass == TFClass_Sniper) {
    new bannedPrimary[] = {230};
    for (new i = 0; i < sizeof(bannedPrimary); i++) {
      if (GetIndexOfWeaponSlot(client, 0) == bannedPrimary[i]) {
        giveitem(client, 14);
      }
    }
  }

  if (playerClass == TFClass_Spy) {
    new bannedCloak[] = {60};
    for (new i = 0; i < sizeof(bannedCloak); i++) {
      if (GetIndexOfWeaponSlot(client, 4) == bannedCloak[i]) {
        giveitem(client, 30);
      }
    }
  }
}

stock int SetWeaponAmmo(const int weapon, const int ammo) {
  int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
  if (owner <= 0)
    return 0;
  if (IsValidEntity(weapon)) {
    int iOffset = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType", 1) * 4;
    int iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
    SetEntData(owner, iAmmoTable + iOffset, ammo, 4, true);
  }

  return 0;
}

public void SetZombie(int client) {
  if (IsClientInGame(client) && IsPlayerAlive(client)) {
    isZombie[client] = true;
    Zombify(client);
    TFClassType playerClass = TF2_GetPlayerClass(client);
    SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", GetPlayerWeaponSlot(client, 2));
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", 2);
    if (weapon != -1) {
      if (GetEntProp(weapon, Prop_Data, "m_iClip1") != -1) {
        SetEntProp(weapon, Prop_Send, "m_iClip1", 0);
      }

      if (GetEntProp(weapon, Prop_Data, "m_iClip2") != -1) {
        SetEntProp(weapon, Prop_Send, "m_iClip2", 0);
      }

      SetEntProp(client, Prop_Send, "m_iAmmo", 0, 4, 3);
      SetWeaponAmmo(weapon, 0);
    }

    for (new i = 0; i < 5; i++) {
      if (i != 2 && i != 1) {
        TF2_RemoveWeaponSlot(client, i);
      }

      if (i == 1) {
        if (playerClass == TFClass_Heavy) {
          decl String: lunchbox[32] = "tf_weapon_lunchbox";
          decl String: sWeapon[32];
          new secondary = GetPlayerWeaponSlot(client, 1);
          if (secondary != -1) {
            GetEntityClassname(secondary, sWeapon, sizeof(sWeapon));
          }

          if (!StrEqual(sWeapon, lunchbox, false)) {
            TF2_RemoveWeaponSlot(client, 1);
          }
        } else if (playerClass == TFClass_DemoMan) {
          decl String: shield[32] = "tf_wearable_demoshield";
          decl String: sWeapon[32];
          new secondary = GetPlayerWeaponSlot(client, 1);
          if (secondary != -1) {
            GetEntityClassname(secondary, sWeapon, sizeof(sWeapon));
          }

          if (!StrEqual(sWeapon, shield, false)) {
            TF2_RemoveWeaponSlot(client, 1);
          }
        } else {
          TF2_RemoveWeaponSlot(client, 1);
        }
      }
    }

    MultiplyPlayerHealth(client, 100);

    SetHudTextParams(-1.0, 0.90, 99999.0, 255, 0, 0, 255, 0, 1.0, 1.0, 1.0);
    ShowSyncHudText(client, statusHud, "%t", "Zombie");
  }
}

stock GetIndexOfWeaponSlot(iClient, iSlot) {
  return GetWeaponIndex(GetPlayerWeaponSlot(iClient, iSlot));
}

stock GetClientCloakIndex(iClient) {
  return GetWeaponIndex(GetPlayerWeaponSlot(iClient, TFWeaponSlot_Watch));
}

stock GetWeaponIndex(iWeapon) {
  return IsValidEnt(iWeapon) ? GetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex") : -1;
}

stock GetActiveIndex(iClient) {
  return GetWeaponIndex(GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon"));
}

stock bool: IsWeaponSlotActive(iClient, iSlot) {
  return GetPlayerWeaponSlot(iClient, iSlot) == GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
}

stock bool: IsIndexActive(iClient, iIndex) {
  return iIndex == GetWeaponIndex(GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon"));
}

stock bool: IsSlotIndex(iClient, iSlot, iIndex) {
  return iIndex == GetIndexOfWeaponSlot(iClient, iSlot);
}

stock bool: IsValidEnt(iEnt) {
  return iEnt > MaxClients && IsValidEntity(iEnt);
}

stock GetSlotFromPlayerWeapon(iClient, iWeapon) {
  for (new i = 0; i <= 5; i++) {
    if (iWeapon == GetPlayerWeaponSlot(iClient, i)) {
      return i;
    }
  }

  return -1;
}

public void ProtectPlayer(int client, float protectTime) {
  if (IsClientInGame(client) && IsPlayerAlive(client)) {
    TF2_AddCondition(client, TFCond_Ubercharged, protectTime);
    ToggleZombieSkin(client, true, true);
    CreateTimer(protectTime, UberSkin, client);
  }
}

public Action UberSkin(Handle timer, int client) {
  ToggleZombieSkin(client, true, false);
  return Plugin_Handled;
}

public Action SetMoveTypeBack(Handle timer, int client) {
  playerFrozen[client] = false;
  SetEntityMoveType(client, MOVETYPE_WALK);
  return Plugin_Handled;
}

public Action Command_MapSay(int args) {
  if (args < 1) {
    return Plugin_Handled;
  }

  char text[192];
  GetCmdArgString(text, sizeof(text));
  CPrintToChatAll(text);
  return Plugin_Handled;
}

public Action Command_MapTimer(int args) {
  if (args < 1) {
    return Plugin_Handled;
  }

  char arg[5];
  GetCmdArg(1, arg, sizeof(arg));
  time = StringToInt(arg);

  CreateTimer(1.0, Timer_MapTimer, _, TIMER_REPEAT);

  return Plugin_Handled;
}

public Action Timer_MapTimer(Handle timer) {
  if (time > 0) {
    SetHudTextParams(-1.0, 0.20, 1.0, 0, 255, 0, 255, 0, 1.0, 1.0, 1.0);
    for (new i = 1; i <= MaxClients; i++) {
      if (IsClientInGame(i) && (!IsFakeClient(i) && GetClientTeam(i) == 3)) {
        ShowSyncHudText(i, standHereHud, "%t", "StandHereForSeconds", time);
      }
    }
    time--;
    return Plugin_Continue;
  }
  else{
    return Plugin_Stop;
  }
}

stock bool: IsValidClient(client) {
  if (client <= 0) return false;
  if (client > MaxClients) return false;
  if (!IsClientConnected(client)) return false;
  return IsClientInGame(client);
}
