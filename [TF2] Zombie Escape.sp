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
	name = "[TF2] Zombie Escape (Unsupported)",
	author = "korki635",
	description = "Zombie Escape gamemode for Team Fortress 2. Not supported.",
	version = SOURCEMOD_VERSION,
	url = "https://esatefekorkmaz.github.io/"
};

ConVar allowCommands;
ConVar defaultTeam;
ConVar balanceCheck;
ConVar autoTeamBalance;
ConVar respawnTime;
ConVar holiday;
Handle bluHud;
Handle restoreSpeedTimer[MAXPLAYERS+1];
Handle g_hWearableEquip;
bool isGameStarted;
bool freeze[MAXPLAYERS+1];
bool slowdown[MAXPLAYERS+1];
bool zombie[MAXPLAYERS+1];
bool speedset[MAXPLAYERS+1];
bool stun[MAXPLAYERS+1];
bool b_Transmit[MAXPLAYERS + 1] = false;


public void OnPluginStart(){
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
	for (new i = 1; i <= MaxClients; i++){
		if (IsValidClient(i)){
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
		}
	}
	allowCommands = FindConVar("sv_allow_point_servercommand");
	defaultTeam = FindConVar("mp_humans_must_join_team");
	balanceCheck = FindConVar("mp_teams_unbalance_limit");
	autoTeamBalance = FindConVar("mp_autoteambalance");
	respawnTime = FindConVar("mp_disable_respawn_times");
	holiday = FindConVar("tf_forced_holiday");
	bluHud = CreateHudSynchronizer();
	g_hWearableEquip = EndPrepSDKCall();

	if (!g_hWearableEquip)
	SetFailState("Failed to create call: CBasePlayer::EquipWearable");
}

public void CheckPlayers(){
	if(isGameStarted){
		int zombieCount = 0;
		int humanCount = 0;
		for (int i = 1; i <= MaxClients; i++){
			if (IsClientInGame(i) && GetClientTeam(i) == 2){
				zombieCount++;
			}
		}
		for (int i = 1; i <= MaxClients; i++){
			if (IsClientInGame(i) && GetClientTeam(i) == 3 && IsPlayerAlive(i)){
				humanCount++;
			}
		}
		if(zombieCount == 0){
			new iFlags = GetCommandFlags("mp_forcewin");
			SetCommandFlags("mp_forcewin", iFlags &= ~FCVAR_CHEAT); 
			ServerCommand("mp_forcewin 3");
			SetCommandFlags("mp_forcewin", iFlags);
		}
		if(humanCount == 0){
			new iFlags = GetCommandFlags("mp_forcewin");
			SetCommandFlags("mp_forcewin", iFlags &= ~FCVAR_CHEAT); 
			ServerCommand("mp_forcewin 2");
			SetCommandFlags("mp_forcewin", iFlags);
		}
	}
}

public void OnClientDisconnect(int client){
	CheckPlayers();
}

public void OnMapStart(){
	CreateTimer(1.0, CheckPlayersTimer, _, TIMER_REPEAT);
	CreateTimer(120.0, AuthorBroadcast, _, TIMER_REPEAT);
	SetConVarString(defaultTeam, "blue", false);
	SetConVarString(allowCommands, "always", false);
	balanceCheck.IntValue = 0;
	autoTeamBalance.IntValue = 0;
	respawnTime.IntValue = 1;
	holiday.IntValue = 2;
}

public Action AuthorBroadcast(Handle timer){
	CPrintToChatAll("{lime}[ZE] {default}Zombie Escape by Esat Efe");
}

public Action CheckPlayersTimer(Handle timer){
	CheckPlayers();
}

public OnClientPutInServer(client){
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

ArrayList PickRandomClients(int team, int count){
    ArrayList arr = new ArrayList();
    for (int i = 1; i <= MaxClients; i++){
        if (IsClientInGame(i) && GetClientTeam(i) == team && IsPlayerAlive(i)){
            arr.Push(i);
		}
	}
    arr.Sort(Sort_Random, Sort_Integer);
    arr.Resize(count);
    return arr;
}

// public Action:JoinTeam(client, const String:command[], argc){
// 	if(isGameStarted){
// 		CPrintToChat(client, "You can't change teams now");
// 		return Plugin_Handled;
// 	}
// 	return Plugin_Continue;
// }

public Action:Suicide(client, const String:command[], argc){
	CPrintToChat(client, "{lime}[ZE] {default}You cannot suicide now");
	return Plugin_Handled;
}

public void Zombify(int client){
	CreateTimer(0.1, DelayZombify, client);
}

public Action Hook_SetTransmit(int entity, int client)
{
	setFlags(entity);
	if(b_Transmit[client])
	{
		return Plugin_Handled;	
	}
	return Plugin_Continue;
}

void setFlags(int edict)
{
	if (GetEdictFlags(edict) & FL_EDICT_ALWAYS)
	{
		SetEdictFlags(edict, (GetEdictFlags(edict) ^ FL_EDICT_ALWAYS));
	}
} 

public void ChangeToZombieSkin(int entity, bool boolean, bool uber)
{
	TFClassType class = view_as<TFClassType>(GetEntProp(entity, Prop_Send, "m_iClass"));
	
	int skinToSet = -1;
	int teamNum = -1;
	if(IsValidClient(entity)){
		if (HasEntProp(entity, Prop_Send, "m_iTeamNum"))
			teamNum = GetEntProp(entity, Prop_Send, "m_iTeamNum");
		else
			teamNum = GetEntProp(entity, Prop_Send, "m_iTeam");
		
		switch (boolean)
		{
			case true:
			{
				switch (teamNum)
				{
					case 2:
					{
						if (class != TFClass_Spy) { 
							if(uber) { 
								skinToSet = 6; 
							}
							else {
								skinToSet = 4; 
							}
						}
						else { 
							if(uber) { 
								skinToSet = 24; 
							}
							else {
								skinToSet = 22; 
							}
						}
						SetEntProp(entity, Prop_Send, "m_nForcedSkin", skinToSet);
						SetEntProp(entity, Prop_Send, "m_bForcedSkin", 1);
					}
				}
			}
			case false:
			{
				SetEntProp(entity, Prop_Send, "m_nForcedSkin", 0);
				SetEntProp(entity, Prop_Send, "m_bForcedSkin", 0);
			}
		}
	}
}

public Action DelayZombify(Handle timer, int client){
	TFClassType class = TF2_GetPlayerClass(client);
	
	switch (class)
	{
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
}

public void CreateVoodoo(int client, int index){
	if(IsClientInGame(client) && GetClientTeam(client) == 2){
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

public void SetPlayerHealth(int client, int multiply){
	DataPack dataPack;
	CreateDataTimer(0.2, SetHealthTimer, dataPack);
	WritePackCell(dataPack, client);
	WritePackCell(dataPack, multiply);
}

public Action SetHealthTimer(Handle timer, DataPack dataPack){
	ResetPack(dataPack, false);
	new client = ReadPackCell(dataPack);
	if(client){
		if(GetClientTeam(client) == 2){
			new melee = GetPlayerWeaponSlot(client, 2);
			int multiply = ReadPackCell(dataPack);
			int defaultHealth = GetClientHealth(client);
			int newHealth = TF2_GetPlayerMaxHealth(client) * multiply;
			int attribHealth = newHealth - defaultHealth;
			TF2Attrib_SetByName(melee, "max health additive bonus", float(attribHealth));
			SetEntityHealth(client, newHealth);
		}
	}
}

public void RegenPlayer(int client){
	TF2Attrib_SetByName(GetPlayerWeaponSlot(client, 2), "max health additive bonus", 0.0);
	TF2_RegeneratePlayer(client);
	CreateTimer(0.1, ResetHealthTimer, client);
}

public Action ResetHealthTimer(Handle timer, int client){
	SetEntityHealth(client, TF2_GetPlayerMaxHealth(client));
}

stock int TF2_GetPlayerMaxHealth(int client) {
	return GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, client);
}

public Action:Event_teamplay_round_win(Handle:event, const String:name[], bool:dontBroadcast){
	isGameStarted = false;
}

public Action:Event_player_spawn(Handle:event, const String:name[], bool:dontBroadcast){
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	TFClassType playerClass = TF2_GetPlayerClass(client);
	RegenPlayer(client);
	new primary = GetPlayerWeaponSlot(client, 0);
	new secondary = GetPlayerWeaponSlot(client, 1);
	new melee = GetPlayerWeaponSlot(client, 2);
	if(IsClientInGame(client) && GetClientTeam(client) == 2){
		TF2Attrib_AddCustomPlayerAttribute(client, "damage force increase", 10.0);
		SetZombie(client);
		if(!freeze[client]){
			ProtectPlayer(client, 3.0);
		}
		if(freeze[client]){
			SetEntityMoveType(client, MOVETYPE_NONE);
		}
		CreateTimer(0.1, SetSpeed, client);
	}
	if(IsClientInGame(client) && GetClientTeam(client) == 3){
		ChangeToZombieSkin(client, false, false);
		zombie[client] = false;
		TF2Attrib_RemoveCustomPlayerAttribute(client, "damage force increase");
		if(playerClass == TFClass_Soldier){
			TF2Attrib_SetByName(primary, "self dmg push force decreased", 0.0);
		}
		if(playerClass == TFClass_Engineer){
			TF2Attrib_SetByName(melee, "bidirectional teleport", 1.0)
			TF2Attrib_SetByName(melee, "mod wrench builds minisentry", 1.0);
			TF2Attrib_SetByName(melee, "engy disposable sentries", 1.0);
			TF2Attrib_SetByName(melee, "alt fire teleport to spawn", 0.0);
		}
		if(playerClass == TFClass_Pyro){
			TF2Attrib_SetByName(primary, "airblast pushback scale", 2.0);
		}
		if(playerClass == TFClass_DemoMan){
			TF2Attrib_RemoveByName(secondary, "sticky arm time bonus");
			TF2Attrib_SetByName(secondary, "sticky arm time penalty", 0.8);
			TF2Attrib_SetByName(secondary, "self dmg push force decreased", 0.0);
		}
		CreateTimer(0.1, SetSpeed, client);
	}
}

public void TF2_OnConditionAdded(int client, TFCond cond){
	if(cond == TFCond_Charging){
		if(GetClientTeam(client) == 2){
			TF2_RemoveCondition(client, cond);
		}
	}
}


public void Knockback(inflictor, client, float amount)
{
	SetEntPropEnt(client, Prop_Send, "m_hGroundEntity", -1);
	float vector[3];       
	float inflictorloc[3];
	float clientloc[3];
	GetEntPropVector(inflictor, Prop_Send, "m_vecOrigin", inflictorloc);
	GetClientAbsOrigin(client, clientloc);      
	MakeVectorFromPoints(clientloc, inflictorloc, vector);      
	NormalizeVector(vector, vector);
	ScaleVector(vector, amount);
	vector[2] = 10.0;     
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vector);
}

public void SetClientSpeed(int client, float speed){
	if(IsClientInGame(client)){
		new playerClass = TF2_GetPlayerClass(client);
		TF2Attrib_RemoveCustomPlayerAttribute(client, "move speed bonus");
		switch(playerClass){
			case TFClass_Scout: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed/400.0);
			case TFClass_Soldier: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed/240.0);
			case TFClass_Pyro: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed/300.0);
			case TFClass_DemoMan: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed/280.0);
			case TFClass_Heavy: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed/230.0);
			case TFClass_Engineer: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed/300.0);
			case TFClass_Medic: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed/320.0);
			case TFClass_Sniper: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed/300.0);
			case TFClass_Spy: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", speed/300.0);
		}
	}
}

public void SetClientSpeedScale(int client){
	if(IsClientInGame(client)){
		new playerClass = TF2_GetPlayerClass(client);
		TF2Attrib_RemoveCustomPlayerAttribute(client, "move speed bonus");
		if(GetClientTeam(client) == 2){
			switch(playerClass){
				case TFClass_Scout: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 336.0/400.0);
				case TFClass_Soldier: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.05);
				case TFClass_Pyro: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.05);
				case TFClass_DemoMan: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.05);
				case TFClass_Heavy: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.05);
				case TFClass_Engineer: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.05);
				case TFClass_Medic: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.05);
				case TFClass_Sniper: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.05);
				case TFClass_Spy: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 1.05);
			}
		}
		if(GetClientTeam(client) == 3){
			switch(playerClass){
				case TFClass_Scout: TF2Attrib_AddCustomPlayerAttribute(client, "move speed bonus", 320.0/400.0);
			}
		}
	}
}

public Action Timer_RestoreSpeed(Handle timer, int serial){
	int client = GetClientFromSerial(serial);
	if(client){
		SetClientSpeedScale(client);
		slowdown[client] = false;
	}
	restoreSpeedTimer[client] = null;
	return Plugin_Continue;
}

public Action SetSpeed(Handle timer, int client){
	if(client){
		SetClientSpeedScale(client);
	}
	return Plugin_Continue;
}

public void Infect(int client){
	PrintCenterText(client, "You're infected");
	SetEntProp(client, Prop_Send, "m_lifeState", 2);
	ChangeClientTeam(client, 2);
	SetEntProp(client, Prop_Send, "m_lifeState", 0); 
	TF2_RegeneratePlayer(client);
	ChangeToZombieSkin(client, true, false);
	SetZombie(client);
	TF2_StunPlayer(client, 3.0, 0.0, TF_STUNFLAGS_GHOSTSCARE);
	CheckPlayers();
}

public Action:OnTakeDamage(client, &attacker, &inflictor, &Float:damage, &damagetype){
		if(isGameStarted){
			if(IsClientInGame(client) && GetClientTeam(client) == 3){
				if(IsValidClient(attacker) && GetClientTeam(attacker) == 2){
					new m_nPlayerCond = FindSendPropInfo("CTFPlayer","m_nPlayerCond") ;
					new cond = GetEntData(client, m_nPlayerCond);
					if(cond != 32){
						new health = GetEntProp(client, Prop_Data, "m_iHealth");
						if(TF2_GetPlayerClass(client) == TFClass_DemoMan){
							decl String:shield[32] = "tf_wearable_demoshield";
							decl String:sWeapon[32];
							new secondary = GetPlayerWeaponSlot(client, 1);
							if(secondary != -1){
								GetEntityClassname(secondary, sWeapon, sizeof(sWeapon));
							}
							if(StrEqual(sWeapon, shield, false)){
								float newHealth = health - damage;
								if(newHealth <= 0.0){
									Infect(client);
									return Plugin_Handled;
								}
								if(health < 100){
									if(newHealth <= 0.0){
										Infect(client);
										return Plugin_Handled;
									}
									Infect(client);
									return Plugin_Handled;
								}
							}
							else{
								Infect(client);
								return Plugin_Handled;
							}
						}
						if(TF2_GetPlayerClass(client) == TFClass_Spy){
							float newHealth = health - damage;
							if(newHealth <= 0.0){
								Infect(client);
								return Plugin_Handled;
							}
						}
						else{
							Infect(client);
							return Plugin_Handled;
						}
					}
				}
			}
			if(IsClientInGame(client) && GetClientTeam(client) == 2){
				if(IsClientInGame(attacker) && GetClientTeam(attacker) == 3){
					decl String:inf[32];
					decl String:remote_pipe[32] = "tf_projectile_pipe_remote";
					GetEdictClassname(inflictor, inf, sizeof(inf));
					new attackerClass = TF2_GetPlayerClass(attacker);
					if(damagetype & DMG_CRIT && attackerClass == TFClass_Sniper && IsWeaponSlotActive(attacker, 0)){
						damage *= 5;
						if(!stun[client]){
							TF2_StunPlayer(client, 1.0, 0.0, TF_STUNFLAGS_BIGBONK);
							stun[client] = true;
							CreateTimer(2.0, StunTimer, client);
						}
						return Plugin_Changed;
					}
					if(StrEqual(inf, remote_pipe, false) && attackerClass == TFClass_DemoMan){
						TF2_StunPlayer(client, 1.0, 0.0, TF_STUNFLAGS_BIGBONK);
					}
					if(attackerClass == TFClass_Spy && IsWeaponSlotActive(attacker, 2)){
						if(damagetype & DMG_CRIT){
							damage = 2000.0;
							TF2_StunPlayer(client, 1.0, 0.0, TF_STUNFLAGS_SMALLBONK);
							TF2_AddCondition(attacker, TFCond_Ubercharged, 3.0);
							TF2_AddCondition(attacker, TFCond_SpeedBuffAlly, 3.0);
							return Plugin_Changed;
						}
						else{
							damage = 1000.0;
							return Plugin_Changed;
						}
					}
					delete restoreSpeedTimer[client];
					decl String:sentry[32] = "obj_sentrygun";
					if(!slowdown[client] && attackerClass != TFClass_Pyro){
						if(StrEqual(inf, sentry, false)){
							SetClientSpeed(client, 0.0);
							Knockback(inflictor, client, -150.0);
						}
						else{
							if(attackerClass == TFClass_Heavy && IsWeaponSlotActive(attacker, 0)){
								SetClientSpeed(client, 0.0);
								Knockback(inflictor, client, -320.0);
							}
							SetClientSpeed(client, 150.0);
						}	
						slowdown[client] = true;
					}
					if(StrEqual(inf, sentry, false) || attackerClass == TFClass_Heavy){
						restoreSpeedTimer[client] = CreateTimer(0.1, Timer_RestoreSpeed, GetClientSerial(client));
					}
					else{
						restoreSpeedTimer[client] = CreateTimer(0.5, Timer_RestoreSpeed, GetClientSerial(client));
					}	
				}
			}
		}
	return Plugin_Continue;
}

public Action StunTimer(Handle timer, int client){
	stun[client] = false;
}

public Action:Event_player_death(Handle:event, const String:name[], bool:dontBroadcast){
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new deathFlag = GetEventInt(event, "death_flags");
	if(isGameStarted){
		if(IsClientInGame(client) && GetClientTeam(client) == 3){
			if(deathFlag != 32){
				ChangeClientTeam(client, 2);
			}
		}
	}
	CheckPlayers();
	return Plugin_Continue;
}

public Action:Event_teamplay_round_start(Handle:event, const String:name[], bool:dontBroadcast){
	isGameStarted = false;
	SetConVarString(defaultTeam, "blue", false);
	for (new i = 1; i <= MaxClients; i++){
		if (IsClientInGame(i) && GetClientTeam(i) == 2){
			ChangeClientTeam(i, 3);
			TF2_RespawnPlayer(i);
			if(freeze[i]){
				SetEntityMoveType(i, MOVETYPE_WALK);
				freeze[i] = false;
			}
		}
	}
	return Plugin_Handled;
}

public void OnClientConnected(int client){
	freeze[client] = false;
	slowdown[client] = false;
	speedset[client] = false;
	zombie[client] = false;
	stun[client] = false;
}

public Action:Event_teamplay_setup_finished(Handle:event, const String:name[], bool:dontBroadcast){
	isGameStarted = true;
	SetConVarString(defaultTeam, "red", false);
	int humanCount = 0;
	for (new i = 1; i <= MaxClients; i++){
		if(IsClientInGame(i)){
			new playerClass = TF2_GetPlayerClass(i);
			if(playerClass == TFClass_Scout){
				if(GetIndexOfWeaponSlot(i, 2) == 44 || GetIndexOfWeaponSlot(i, 2) == 648){
					giveitem(i, 0);
				}
			}	
			if(playerClass == TFClass_Soldier){
				if(GetIndexOfWeaponSlot(i, 0) == 237 || GetIndexOfWeaponSlot(i, 0) == 441){
					giveitem(i, 18);
				}
			}	
			if(playerClass == TFClass_DemoMan){
				if(GetIndexOfWeaponSlot(i, 1) == 265){
					giveitem(i, 20);
				}
			}	
			if(playerClass == TFClass_Sniper){
				if(GetIndexOfWeaponSlot(i, 0) == 230){
					giveitem(i, 14);
				}
			}	
			if(playerClass == TFClass_Spy){
				if(GetIndexOfWeaponSlot(i, 4) == 60){
					giveitem(i, 30);
				}
			}	
		}
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3){
			humanCount++;
		}
	}
	if(humanCount > 0){
		ArrayList clients = new ArrayList();
		if(humanCount <= 5){
			clients = PickRandomClients(3, 1);
		}
		else if(humanCount <= 10){
			clients = PickRandomClients(3, 2);
		}
		else if(humanCount <= 15){
			clients = PickRandomClients(3, 3);
		}
		else if(humanCount >= 20){
			clients = PickRandomClients(3, 4);
		}
		for (int i; i < clients.Length; i++){
			ChangeClientTeam(clients.Get(i), 2);
			freeze[clients.Get(i)] = true;
			TF2_RespawnPlayer(clients.Get(i));
			ProtectPlayer(clients.Get(i), 13.0);
			CreateTimer(10.0, SetMoveTypeBack, clients.Get(i));
			CPrintToChatAll("{lime}[ZE] {default}%N has been infected", clients.Get(i));
		}
		delete clients;  
	}  
	return Plugin_Handled;
}

stock int SetWeaponAmmo(const int weapon, const int ammo){
	int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	if (owner <= 0)
		return 0;
	if (IsValidEntity(weapon)){
		int iOffset = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType", 1)*4;
		int iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
		SetEntData(owner, iAmmoTable+iOffset, ammo, 4, true);
	}
	return 0;
}

public void SetZombie(int client){
	if(IsClientInGame(client) && IsPlayerAlive(client)){
		Zombify(client);
		zombie[client] = true;
		new playerClass = TF2_GetPlayerClass(client);
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", GetPlayerWeaponSlot(client, 2)); 
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", 2);
		if(weapon != -1){
			if(GetEntProp(weapon, Prop_Data, "m_iClip1") != -1){
				SetEntProp(weapon, Prop_Send, "m_iClip1", 0);
			}
			if(GetEntProp(weapon, Prop_Data, "m_iClip2") != -1){
				SetEntProp(weapon, Prop_Send, "m_iClip2", 0);
			}
			SetEntProp(client, Prop_Send, "m_iAmmo", 0, 4, 3);
			SetWeaponAmmo(weapon, 0);
		}
		for(new i = 0; i < 5; i++){
			if(i != 2 && i != 1){
				TF2_RemoveWeaponSlot(client, i);
			}
			if(i == 1){
				if(playerClass == TFClass_Heavy){
					decl String:lunchbox[32] = "tf_weapon_lunchbox";
					decl String:sWeapon[32];
					new secondary = GetPlayerWeaponSlot(client, 1);
					if(secondary != -1){
						GetEntityClassname(secondary, sWeapon, sizeof(sWeapon));
					}
					if(!StrEqual(sWeapon, lunchbox, false)){
						TF2_RemoveWeaponSlot(client, 1);
					}
				}
				else if(playerClass == TFClass_DemoMan){
					decl String:shield[32] = "tf_wearable_demoshield";
					decl String:sWeapon[32];
					new secondary = GetPlayerWeaponSlot(client, 1);
					if(secondary != -1){
						GetEntityClassname(secondary, sWeapon, sizeof(sWeapon));
					}
					if(!StrEqual(sWeapon, shield, false)){
						TF2_RemoveWeaponSlot(client, 1);
					}
				}
				else{
					TF2_RemoveWeaponSlot(client, 1);
				}
			}
		}
		SetPlayerHealth(client, 100);
	}
}

stock GetIndexOfWeaponSlot(iClient, iSlot)
{
    return GetWeaponIndex(GetPlayerWeaponSlot(iClient, iSlot));
}

stock GetClientCloakIndex(iClient)
{
    return GetWeaponIndex(GetPlayerWeaponSlot(iClient, TFWeaponSlot_Watch));
}

stock GetWeaponIndex(iWeapon)
{
    return IsValidEnt(iWeapon) ? GetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex"):-1;
}

stock GetActiveIndex(iClient)
{
    return GetWeaponIndex(GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon"));
}

stock bool:IsWeaponSlotActive(iClient, iSlot)
{
    return GetPlayerWeaponSlot(iClient, iSlot) == GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
}

stock bool:IsIndexActive(iClient, iIndex)
{
    return iIndex == GetWeaponIndex(GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon"));
}

stock bool:IsSlotIndex(iClient, iSlot, iIndex)
{
    return iIndex == GetIndexOfWeaponSlot(iClient, iSlot);
}

stock bool:IsValidEnt(iEnt)
{
    return iEnt > MaxClients && IsValidEntity(iEnt);
}

stock GetSlotFromPlayerWeapon(iClient, iWeapon)
{
    for (new i = 0; i <= 5; i++)
    {
        if (iWeapon == GetPlayerWeaponSlot(iClient, i))
        {
            return i;
        }
    }
    return -1;
} 

public void ProtectPlayer(int client, float protectTime){
	if(IsClientInGame(client) && IsPlayerAlive(client)){
		TF2_AddCondition(client, TFCond_Ubercharged, protectTime);
		ChangeToZombieSkin(client, true, true);
		CreateTimer(protectTime, UberSkin, client);
	}
}

public Action UberSkin(Handle timer, int client){
	ChangeToZombieSkin(client, true, false);
}

public Action SetMoveTypeBack(Handle timer, int client){
	freeze[client] = false;
	SetEntityMoveType(client, MOVETYPE_WALK);
}

public Action Command_MapSay(int args){
	if(args < 1){
		return Plugin_Handled;
	}
	char text[192];
	GetCmdArgString(text, sizeof(text));
	CPrintToChatAll(text);
	return Plugin_Handled;		
}

public Action Command_MapTimer(int args){
	if(args < 1){
		return Plugin_Handled;
	}
	char arg[5];
	GetCmdArg(1, arg, sizeof(arg));
	int time = StringToInt(arg);
	SetHudTextParams(-1.0, 0.20, float(time), 0, 255, 0, 255, 0, 1.0, 1.0, 1.0);
	for (new i = 1; i <= MaxClients; i++){
		if (IsClientInGame(i) && (!IsFakeClient(i) && GetClientTeam(i) == 3)){
			ShowSyncHudText(i, bluHud, "Stand here for %i seconds", time);
		}
	}
	return Plugin_Handled;
}

stock bool:IsValidClient(client)
{
	if(client <= 0 ) return false;
	if(client > MaxClients) return false;
	if(!IsClientConnected(client)) return false;
	return IsClientInGame(client);
}
