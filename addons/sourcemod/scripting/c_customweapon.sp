/*
 *  12-04:
 *      Fix zombie kills caused by point_hurt explosion not being assigned to player:
 *          Reason: event npc_killed returns WeaponName class as killeridx.
 *          Solution: assign client as owner of point hurt (WeaponName), retrieve owner of WeaponName entity at 
 *                    npc_killed event (pre hook), then set event int killeridx as client id
 *                    Making sure to hook this pre, so other event dependancies get this updated value.
 *      Refactor code: naming scheme, debug, cleanup
 *
 *  TODO:
 *      Default nmrih has flare projectile spawn in middle of screen, yuk. FIX: Teleport projectile to weapon muzzle on entitycreate. 
 *
 *
*/




/* 
weapon_reload
    Name: 	weapon_reload
    Structure: 	
    short 	player_id 	        
    string 	weapon_classname
weapon_fired                    -> does not fire
    Name: 	weapon_fired
    Structure: 	
    short 	player_id 	
    short 	weapon_id 	
ammo_checked
    Name: 	ammo_checked
    Structure: 	
    short 	player_id 	-> invalid client id
    short 	weapon_id 	
player_shoot
Note: Player shot his weapon
Name: 	player_shoot
Structure: 	
short 	userid 	user ID on server
byte 	weapon 	weapon ID
byte 	mode 	weapon mode 
*/
//flare_gun at shoot:
// create flare_projectile
// effectdispatch   (projectile effect)
// event: hit wall:
// effectdispatch   (flare explosion effect)
// effectdispatch   (flare fireflies effect? ) -- has no origin, its a dud
// destroy flare_projectile

// - m_iszFireballSprite (Offset 928) (Save)(4 Bytes)
// - m_sFireballSprite (Offset 932) (Save)(2 Bytes)

//CParticleFire
//CFireTrail
//EntityParticleTrail
//RocketTrail
//ParticleSystem

//flare_projectile

// flaregun_barrelclosed.wav
// flaregun_barrelopen.wav
// flaregun_fire.wav
// flaregun_hammerup.wav
// flaregun_load.wav
// flaregun_spentout.wav
// flare_burnloop.wav
// flare_pop.wav
// flare_whistle.wav

//Voice reload notif spam:
//if you want to mute the reload voice notification spam
//comment or delete: { event AE_WPN_INSERTSHELL 35 "" }
//in the viewmodel .qc

//AMMOCHECK sound overwrite is broken for now due to broken hook client return


#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#include <weaponmodels>

#define PLUGIN_NAME     "[NMRiH] Custom Weapon!"
#define PLUGIN_VERSION     "1.1"

#define MAX_CUSTOM_WEAPONS 50
#define EF_NODRAW 0x20
#define EFFECTNAMEOFFSET 2
#define SIZEOF_INT 4

#define SND_ORIG_PROJEXPLODE "flare_pop.wav"
#define SND_ORIG_FIRE "flaregun_fire.wav"

#define EXPLOSIONEFFECT 

#define DEFAULT_FLARE_GUN_RADIUS 50.0

//#define DEBUG false


public Plugin myinfo =
{
	name        = PLUGIN_NAME,
	author      = "Thijs/Rogue GarlicBread",
	description = "Add a custom projectile weapon :D    ",
	version     = PLUGIN_VERSION,
	url         = "https://steamcommunity.com/id/OwnedThijs/"
};


ConVar g_sv_flare_gun_explode_damage;
ConVar g_mp_friendlyfire;
ConVar g_cfg_friendlyfire;
ConVar g_sm_supplycrate_flare;

float g_default_flare_gun_damage;
int g_iOffset_PlayerViewModel;

enum snd_source
{
    fire,
    firedry,
    reload,
    ammocheck,
    explosionsnd1,
    explosionsnd2,
    unholster
};

enum flare_EffectName
{
    flareexplode = 385,
    grenade_explode 
};



enum struct WeaponInfo{
    char    WeaponName[PLATFORM_MAX_PATH];
    char    ViewModel[PLATFORM_MAX_PATH];
    char    WorldModel[PLATFORM_MAX_PATH];
    char    ProjectileModel[PLATFORM_MAX_PATH];
    char    ParticleExplodeEffect[PLATFORM_MAX_PATH];     //custom particle explosion effect
    char    ParticleTrailEffect[PLATFORM_MAX_PATH];         //custom particle trail effect
    int     Damage;
    float   FlareDamage;
    int     DamageType;
    float   Radius;
    char    ParticleEffect[PLATFORM_MAX_PATH];     // name of particle effect to play on projectile explode
	float	ShakeStrength;
	float	ShakeFrequency;
	float	ShakeDuration;
	float	ShakeRadius;
    char    Fire[PLATFORM_MAX_PATH];
    char    FireDry[PLATFORM_MAX_PATH];
    char    Reload[PLATFORM_MAX_PATH];
    char    AmmoCheck[PLATFORM_MAX_PATH];
    char    ExplosionSnd1[PLATFORM_MAX_PATH];
    char    ExplosionSnd2[PLATFORM_MAX_PATH];
    char    Unholster[PLATFORM_MAX_PATH];
    char    ClassName[PLATFORM_MAX_PATH];
}

WeaponInfo g_WeaponInfo;

int     g_iEffectFlareExplodeIndex;
int     g_iEffectFlareTrailIndex;
int     g_iEffectExplodeEffect;
int     g_iEffectTrailEffect;

bool    g_bDoShake;
int     g_iEnt_EnvShake

bool    g_bPrecahceFinished;

Handle g_hSDKCall_Animating_GetAttachment;

public void OnPluginStart(){

 

    RegServerCmd("sm_weaponinfo", PrintWeapon, "print custom projectile weapon config informaton");
    RegAdminCmd("play", play_a, ADMFLAG_KICK, "test custom weapon sounds");
    
    g_sv_flare_gun_explode_damage = FindConVar("sv_flare_gun_explode_damage");
    g_default_flare_gun_damage = g_sv_flare_gun_explode_damage.FloatValue;

    g_mp_friendlyfire = FindConVar("mp_friendlyfire");
    g_cfg_friendlyfire = CreateConVar("sm_customweapon_friendlyfire", "1", "0 - Never deal damage to teammates, 1 - Deal damage if FF ConVar is set, 2 -  Always damage teammates.");
    g_sm_supplycrate_flare = CreateConVar("sm_supplycrate_flare", "15", "Add flareguns in supply crates, value set is percentage chance.");

    LoadConfig();
    
    PrintConfig();

    InitSendPropOffset(g_iOffset_PlayerViewModel, "CBasePlayer", "m_hViewModel");


	Handle gameConf = LoadGameConfigFile("customweapon.games");

	if (gameConf == INVALID_HANDLE)
        LogError("unable to Load Game ConfigFile \"customweapon.games\" ");

//-----------------------------------------------------------------------------
// Purpose: Returns the world location and world angles of an attachment
//  Purpose in plugin: get location to teleport flareprojectile to.
// Input  : attachment name
// Output :	location and angles
//-----------------------------------------------------------------------------
//bool CBaseAnimating::GetAttachment( const char *szName, Vector &absOrigin, QAngle &absAngles )

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(gameConf, SDKConf_Virtual, "CBaseAnimating::GetAttachment");

    PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
    PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
    PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef);

	// SDKType_CBaseEntity,    /**< CBaseEntity (always as pointer) */
	// SDKType_CBasePlayer,    /**< CBasePlayer (always as pointer) */
	// SDKType_Vector,         /**< Vector (pointer, byval, or byref) */
	// SDKType_QAngle,         /**< QAngles (pointer, byval, or byref) */
	// SDKType_PlainOldData,   /**< Integer/generic data <=32bit (any) */
	// SDKType_Float,          /**< Float (any) */
	// SDKType_Edict,          /**< edict_t (always as pointer) */
	// SDKType_String,         /**< NULL-terminated string (always as pointer) */
	// SDKType_Bool            /**< Boolean (any) */

	// SDKPass_Pointer,        /**< Pass as a pointer */
	// SDKPass_Plain,          /**< Pass as plain data */
	// SDKPass_ByValue,        /**< Pass an object by value */
	// SDKPass_ByRef           /**< Pass an object by reference */

    if (!(g_hSDKCall_Animating_GetAttachment = EndPrepSDKCall()))
    {
        SetFailState("Failed to load SDK call \"CBaseAnimating::GetAttachment\"!");
    }


    AddNormalSoundHook(SoundHook);
    HookWeaponEvents();
    HookEvent("nmrih_reset_map", Event_Reset_Map);
    HookEvent("npc_killed", Event_npc_killed, EventHookMode_Pre);
    if(g_bDoShake && g_iEnt_EnvShake == -1)
        SetupScreenShake();
    

}

public Action Event_npc_killed(Handle event, char[] name, bool dontBroadcast)
{
	int client = GetEventInt(event, "killeridx");
	char classname[128];
    GetEntityClassname(client, classname, sizeof(classname));
    if ( StrEqual(classname, g_WeaponInfo.WeaponName) )
    {
        int owner = GetEntPropEnt(client, Prop_Send, "m_hOwnerEntity");
        if ( owner < 1 )    return Plugin_Continue;

        //check if valid client? -> eh whatever, broadcasts won't crash server if wrong id
        SetEventInt(event, "killeridx", owner);
        return Plugin_Changed;
    }

	return Plugin_Continue;
}



public void Event_Reset_Map(Event event, const char[] eventName, bool dontBrodcast){
    //re-create a env_shake entity as it is deleted on map reset
    if(g_bDoShake)
        SetupScreenShake();
}

//TODO: customize all particle effects

public void OnMapStart(){
    //CreateVScriptProxy();
    g_iEffectFlareExplodeIndex      = FindParticleIndex("NMRiH_model_flare_explosion");
    g_iEffectFlareTrailIndex        = FindParticleIndex("NMRIH_Static_flare_model");
    if (!g_iEffectFlareExplodeIndex){
        LogError("---%s--- Could not find NMRiH_model_flare_explosion particle effect", PLUGIN_NAME);
    }
    else if (!g_iEffectFlareTrailIndex){
        LogError("---%s--- Could not find NMRIH_Static_flare_model particle effect", PLUGIN_NAME);
    }
    g_iEffectExplodeEffect = FindParticleIndex(g_WeaponInfo.ParticleExplodeEffect);
    if (!g_iEffectExplodeEffect){
        LogError("---%s---Could not find %s particle effect", PLUGIN_NAME, g_WeaponInfo.ParticleExplodeEffect);
    }
    g_iEffectTrailEffect = FindParticleIndex(g_WeaponInfo.ParticleTrailEffect);
    if (!g_iEffectTrailEffect){
        LogError("---%s---Could not find %s particle effect", PLUGIN_NAME, g_WeaponInfo.ParticleTrailEffect);
    }

    PrecacheWeaponInfo_PrecahceStuff();
    AddNormalSoundHook(SoundHook);
    HookWeaponEvents();
    
    //set env_shake entity
    if(g_bDoShake)
        SetupScreenShake();




}

public void OnConfigsExecuted(){
    if (g_WeaponInfo.FlareDamage != 0.0 )
        SetFlareGunDamage(g_WeaponInfo.FlareDamage);

    int result = WeaponModels_AddWeaponByClassName("tool_flare_gun", g_WeaponInfo.ViewModel, g_WeaponInfo.WorldModel, WeaponModels_OnWeapon);
    if (result == -1){
        LogError("---%s--- error setting weaponmodels override", PLUGIN_NAME);
    }
    AddTempEntHook("EffectDispatch", CB_TempEntFlare);  //change the explosion effect!
}


public void OnMapEnd(){
    //on map change: wait until everything i cached before performing model overwrites
    g_bPrecahceFinished = false;
    //reset entity references,
    g_iEnt_EnvShake = -1;
}

public void OnPluginEnd(){
    SetFlareGunDamage(g_default_flare_gun_damage);
    //reset env_shake entity
    // if(g_bDoShake && g_iEnt_EnvShake <= 1){  
    //     AcceptEntityInput(g_iEnt_EnvShake, "kill");
    //     g_iEnt_EnvShake = -1;
    //     }
}


// Weaponmodels overwrite callback
// Don't forget you can both share or have individual callbacks for weapons. In this case we share the callback
public bool WeaponModels_OnWeapon(int weaponIndex, int client, int weapon, const char[] className, int itemDefIndex)
{
	// All conditions have passed, show the weapon!
	return true;
}


//-----Weapon hooks!-----
public void OnClientPostAdminCheck(int client)
{
	SDKHook(client, SDKHook_WeaponSwitchPost, cb_OnWeaponSwitchPost);
	SDKHook(client, SDKHook_OnTakeDamage, cb_OnTakeDamage);
}





public void HookWeaponEvents(){
    HookEvent("weapon_reload",  cb_Event_WeaponReload);
    //HookEvent("ammo_checked",   cb_Event_AmmoChecked);
}


public void OnEntityCreated(int entity, const char[] classname)
{

    if (StrEqual( classname, "flare_projectile", false )){

        if (!g_bPrecahceFinished) return;   //wait until precaching done before overriding things
        /**
        * Hook newly fired flare projectile
        */
        #if defined DEBUG
            PrintToServer("I am flare :D! %s", classname);
        #endif
        float vOrigin[3];
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vOrigin);

        SetEntityModel(entity, g_WeaponInfo.ProjectileModel);
        EmitSoundToAll(g_WeaponInfo.Fire, entity, SNDCHAN_WEAPON);
    }


    if (g_sm_supplycrate_flare.IntValue == 0){   //supply crate spawning is disabled, we are done here
        return;
    }
    /*
    *  Random add flares to supply crates. (item_inventory_box)
    *  Remove the contents, add flaregun, add other items
    */
    if ( StrEqual( classname, "item_inventory_box", false) )
    {
        int randInt = GetRandomInt(0, 100);
        if (randInt < g_sm_supplycrate_flare.IntValue)
        {
            AcceptEntityInput(entity, "RemoveAllItems");
            SetVariantString("tool_flare_gun");
            AcceptEntityInput(entity, "AddItem");
            // SetVariantInt(8);
            // AcceptEntityInput(entity, "AddRandomWeapon");
            // SetVariantInt(3);
            // AcceptEntityInput(entity, "AddRandomGear"); 
            // SetVariantInt(8);
            // AcceptEntityInput(entity, "AddRandomAmmo");
        }
    }

}


public void GetAttachment(int entity, const char[] szName, float absOrigin[3], float absAngles[3])    {
    SDKCall(g_hSDKCall_Animating_GetAttachment, entity, szName, absOrigin, absAngles);
} 



/**
 * Hook exploded flare
 */
public void OnEntityDestroyed(int entity){
    if (!IsValidEntity(entity)) return;
    
    char classname[128];
    GetEntityClassname(entity, classname, sizeof(classname));
    if( StrEqual( classname, "flare_projectile", false )){

        int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
        #if defined DEBUG
            if (owner<1){PrintToServer("FlareProjectile has No owner");}
            else 
                PrintToServer("FlareProjectile owner: %d", owner);
        #endif
        float vOrigin[3];
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vOrigin);
        SplashDamage(vOrigin, g_WeaponInfo.Damage, g_WeaponInfo.DamageType, g_WeaponInfo.Radius, owner);


        if (g_bDoShake)
        {
            StartShake(g_iEnt_EnvShake, vOrigin);
        }
        //explosion sound is done in soundhook
    }
}  




public void cb_Event_WeaponReload(Event event, const char[] eventName, bool dontBrodcast){

    
    int client = GetClientOfUserId(event.GetInt("player_id"));
    if (client<1){
        return;
    }
    char weaponclass[128];
    int weapon_id = event.GetInt("weapon_id");

    if (!event.GetString("weapon_classname", weaponclass, sizeof(weaponclass))){

        if (!GetEntityClassname(weapon_id, weaponclass, sizeof(weaponclass))){
            LogError("---%s--- Could not retrieve classname ", PLUGIN_NAME);
        }
    }
    if ( StrEqual(weaponclass, "tool_flare_gun", false))
    {
        SoundHandler(client, reload);
    }
}

// public void cb_Event_AmmoChecked(Event event, const char[] eventName, bool dontBrodcast){   //invalid client name... broken for now
//     int client = GetClientOfUserId(event.GetInt("player_id"));
//     if (client<1){
//         PrintToServer("invalid client id");
//         return;
//     }
//     char weaponclass[128];
//     int weapon_id = event.GetInt("weapon_id");

//     if (!event.GetString("weapon_classname", weaponclass, sizeof(weaponclass))){

//         if (!GetEntityClassname(weapon_id, weaponclass, sizeof(weaponclass))){
//             LogError("---%s--- Could not retrieve classname ", PLUGIN_NAME);
//         }
//     }
//     if ( StrEqual(weaponclass, "tool_flare_gun", false))
//     {
//         SoundHandler(client, ammocheck);
//     }
// }


/**
 * Play unholster sound
 */
public void cb_OnWeaponSwitchPost(int client, int weapon){
	// Callback is sometimes called on disconnected clients
	if (!IsClientConnected(client))
	{
		return;
	}
    if (!IsValidEdict(weapon ) && weapon<1 ) {
        return;}
    char buffer[64];
    if (!GetEntityClassname(weapon, buffer, sizeof(buffer))) return;
    if ( StrEqual(buffer, "tool_flare_gun", false))
    {
        SoundHandler(client, unholster);
    }
}


/**
 * Hook flare explosion sound and overwrite with new explosion sound
 */
public Action SoundHook(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
	  int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
	  char soundEntry[PLATFORM_MAX_PATH], int &seed){

    if ( StrContains( sample, SND_ORIG_PROJEXPLODE, false ) != -1){

        sample = g_WeaponInfo.ExplosionSnd1;
        //EmitSoundToAll(g_WeaponInfo.ExplosionSnd1, entity);
        return Plugin_Changed;
    }   
    return Plugin_Continue;
}
 

public void SoundHandler(int  client, snd_source snd_src){
    switch (snd_src){
        case fire:      {
            EmitSoundToClient(client, g_WeaponInfo.Fire, SOUND_FROM_PLAYER, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE);}  //Fire is client sided, cannot overwrite in code :c
        case firedry:   {
            EmitSoundToClient(client, g_WeaponInfo.FireDry, SOUND_FROM_PLAYER, SNDCHAN_WEAPON);}
        case reload:    {
            EmitSoundToClient(client, g_WeaponInfo.Reload, SOUND_FROM_PLAYER, SNDCHAN_WEAPON);}
        case ammocheck: {
            EmitSoundToClient(client, g_WeaponInfo.AmmoCheck, SOUND_FROM_PLAYER, SNDCHAN_WEAPON);}
        case unholster: {
            EmitSoundToClient(client, g_WeaponInfo.Unholster, SOUND_FROM_PLAYER, SNDCHAN_REPLACE, SNDLEVEL_DRYER,_, 0.7);}             //SNDCHAN_REPLACE to prevent clipping
        }
}



//////////////////////////////////////////////////////////////////////////////////////////////////////
//---------------------------------Custom Particles-------------------------------------------------//

//Hooked specific tempent particles ( Flare Gun explosion )
//cp tempent data and stop it, set new tempent particle and dispatch effect
//TODO: Find a way to add NEW particle effects!
public Action CB_TempEntFlare(const char[] te_name, const int[] Players, int numClients, float delay)
{   
    int effect = TE_ReadNum("m_nHitBox");
    //int effectNAME = TE_ReadNum("m_iEffectName");

    if ( effect == g_iEffectFlareExplodeIndex /*&& effectNAME == EFFECTNAMEOFFSET*/){
        float m_vOrigin[3];
        float m_vStart[3];
        float m_vAngles[3];
        m_vOrigin[0] =  TE_ReadFloat("m_vOrigin[0]");   //m_vOrigin&m_vStart cannot be accesses as the entire vector, only per cell ¯\_(ツ)_/¯
        m_vOrigin[1] =  TE_ReadFloat("m_vOrigin[1]");
        m_vOrigin[2] =  TE_ReadFloat("m_vOrigin[2]");
        m_vStart[0] =   TE_ReadFloat("m_vStart[0]");
        m_vStart[1] =   TE_ReadFloat("m_vStart[1]");
        m_vStart[2] =   TE_ReadFloat("m_vStart[2]");
        TE_ReadVector("m_vAngles", m_vAngles);
        TE_EffectDispatch(g_iEffectExplodeEffect, m_vOrigin, m_vStart, m_vAngles, delay);

        return Plugin_Handled;
    }
    else if ( effect == g_iEffectFlareTrailIndex ){
        float m_vOrigin[3];
        float m_vStart[3];
        float m_vAngles[3];
        m_vOrigin[0] =  TE_ReadFloat("m_vOrigin[0]");   //m_vOrigin&m_vStart cannot be accesses as the entire vector, only per cell ¯\_(ツ)_/¯
        m_vOrigin[1] =  TE_ReadFloat("m_vOrigin[1]");
        m_vOrigin[2] =  TE_ReadFloat("m_vOrigin[2]");
        m_vStart[0] =   TE_ReadFloat("m_vStart[0]");
        m_vStart[1] =   TE_ReadFloat("m_vStart[1]");
        m_vStart[2] =   TE_ReadFloat("m_vStart[2]");
        TE_ReadVector("m_vAngles", m_vAngles);
        TE_EffectDispatch(g_iEffectTrailEffect, m_vOrigin, m_vStart, m_vAngles, delay);
        return Plugin_Stop;
    }
    return Plugin_Continue;
}


//Find particle index n in the particleeffectsnames table. To be used to overwrite effect in TempEnts, or creating particle systems.
public int FindParticleIndex(char[] ParticleName)
    {
    // find string table
    int ParticleEffectNamesTable = FindStringTable("ParticleEffectNames");
    if (ParticleEffectNamesTable==INVALID_STRING_TABLE) 
    {
        LogError("Could not find string table: ParticleEffectNames");
        return 0;
    }
    
    // find particle index
    char tmp[256];
    int count = GetStringTableNumStrings(ParticleEffectNamesTable);
    int stridx = INVALID_STRING_INDEX;
    
    for (int i=0; i<count; i++)
    {
        ReadStringTable(ParticleEffectNamesTable, i, tmp, sizeof(tmp));
        if (StrEqual(tmp, ParticleName, false))
        {
            stridx = i;
            break;
        }
    }
    if (stridx==INVALID_STRING_INDEX)
    {
        LogError("Could not find particle:%s", ParticleName);
        return 0;
    }
    else   
        return stridx;
}

void TE_EffectDispatch(int sParticle, const float m_vOrigin[3], const float vStart[3], const float m_vAngles[3], float delay) 
{
    TE_Start("EffectDispatch");
    TE_WriteFloat("m_vOrigin[0]", m_vOrigin[0]);
    TE_WriteFloat("m_vOrigin[1]", m_vOrigin[1]);
    TE_WriteFloat("m_vOrigin[2]", m_vOrigin[2]);
    TE_WriteFloat("m_vStart[0]", vStart[0]);
    TE_WriteFloat("m_vStart[1]", vStart[1]);
    TE_WriteFloat("m_vStart[2]", vStart[2]);
    TE_WriteVector("m_vAngles", m_vAngles);
    TE_WriteNum("m_nHitBox", sParticle);
    TE_SendToAll(delay);
} 



//////////////////////////////////////////////////////////////////////////////////////////////////////
//---------------------------------      Edit Damage     -------------------------------------------//

/**
 * Change blast damage of flare gun.
 */
void SetFlareGunDamage(float damage)
{
    g_sv_flare_gun_explode_damage.FloatValue = damage;
}

/**
 *  Add Splash Damage to projectile (Explosion! :D)
 *  Deals Area of affect damage. Damage to players is filtered out in cb_OnTakeDamage.
 */
public int SplashDamage(const float vecCenter[3], int damage, int type, float radius, int client)
{
    int pointHurt = CreateEntityByName("point_hurt");    // Create point_hurt
    TeleportEntity(pointHurt, vecCenter, NULL_VECTOR, NULL_VECTOR);
    
    if ( client > 0 && client <= 9 ){   //set owner so as to set extract info and set the damage dealer in npc_killed, to fix kill messages
        SetEntPropEnt(pointHurt,  Prop_Data,  "m_hOwnerEntity", client);
    }

    SetEntProp(pointHurt, Prop_Data, "m_nDamage", damage);
    
    SetEntPropFloat(pointHurt, Prop_Data, "m_flRadius", radius);
    SetEntProp(pointHurt, Prop_Data, "m_bitsDamageType", damage);
    SetEntPropFloat(pointHurt, Prop_Data, "m_flDelay", 0.1);

    DispatchSpawn(pointHurt);
    SetEntPropString(pointHurt, Prop_Data, "m_iClassname", g_WeaponInfo.WeaponName);    //change classname for easy future filtering
    AcceptEntityInput(pointHurt, "Hurt", client, client);
    RemoveEdict(pointHurt);
}
/**
 * Filter players from SplashDamage
 */
public Action cb_OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype){
    //case: is valid player?
	if ( !(victim > 0	&& victim <= MaxClients	&& IsClientInGame(victim)) )
	{
		return Plugin_Continue;
	}

    //added pvp check.
    char clsnamebuff[128];
    GetEntityClassname(attacker, clsnamebuff, sizeof(clsnamebuff));
    bool isCustomWeapon = StrEqual(clsnamebuff, g_WeaponInfo.WeaponName);
    if ( g_cfg_friendlyfire.IntValue == 2 )                                             return Plugin_Continue;     //is custom weapon FF mode on always do damage?
    else if ( g_mp_friendlyfire.BoolValue && g_cfg_friendlyfire.IntValue == 1 )         return Plugin_Continue;     //is custom weapon FF mode on, and server FF on?
    else if ( isCustomWeapon && !g_mp_friendlyfire.BoolValue )                          return Plugin_Stop;         //is custom weapon and FF off?

    return Plugin_Continue;
}



//Start env_shake entity shake
void StartShake(g_iEnt_Ref, float origin[3]){  
    int shakeindex = EntRefToEntIndex( g_iEnt_Ref );
    if( shakeindex<1 ){
        PrintToServer("---%s--- Invalid or no env_shake entity", PLUGIN_NAME);
        return;
    }
    TeleportEntity(shakeindex, origin, NULL_VECTOR, NULL_VECTOR);
    AcceptEntityInput(shakeindex, "StartShake");
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////
//---------------------           Configurations, Downloads and Precaching            ----------------------//

public void LoadConfig()
{
    char path[PLATFORM_MAX_PATH];
	char buffer[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, path, sizeof(path), "configs/customweapon_config.cfg");

	if (FileExists(path))
	{
		KeyValues keyValues = new KeyValues("WeaponConfig");

		keyValues.ImportFromFile(path);

		if (keyValues.GotoFirstSubKey())
		{
			do
			{
				keyValues.GetSectionName(buffer, sizeof(buffer));
			
                keyValues.GetString("WeaponName", g_WeaponInfo.WeaponName, PLATFORM_MAX_PATH);
                keyValues.GetString("ViewModel", g_WeaponInfo.ViewModel, PLATFORM_MAX_PATH);
                keyValues.GetString("WorldModel", g_WeaponInfo.WorldModel, PLATFORM_MAX_PATH);
                keyValues.GetString("ProjectileModel", g_WeaponInfo.ProjectileModel, PLATFORM_MAX_PATH);
                keyValues.GetString("ParticleExplodeEffect", g_WeaponInfo.ParticleExplodeEffect, PLATFORM_MAX_PATH);
                keyValues.GetString("ParticleTrailEffect", g_WeaponInfo.ParticleTrailEffect, PLATFORM_MAX_PATH);
                keyValues.GetString("Fire", g_WeaponInfo.Fire, PLATFORM_MAX_PATH) ;
                keyValues.GetString("FireDry", g_WeaponInfo.FireDry, PLATFORM_MAX_PATH);
                keyValues.GetString("Reload", g_WeaponInfo.Reload, PLATFORM_MAX_PATH);
                keyValues.GetString("AmmoCheck", g_WeaponInfo.AmmoCheck, PLATFORM_MAX_PATH);
                keyValues.GetString("ExplosionSnd1", g_WeaponInfo.ExplosionSnd1, PLATFORM_MAX_PATH);
                keyValues.GetString("ExplosionSnd2", g_WeaponInfo.ExplosionSnd2, PLATFORM_MAX_PATH);
                keyValues.GetString("Unholster", g_WeaponInfo.Unholster, PLATFORM_MAX_PATH) ;
                keyValues.GetString("ParticleEffect", g_WeaponInfo.ParticleEffect, PLATFORM_MAX_PATH) ;
                g_WeaponInfo.FlareDamage = keyValues.GetFloat("FlareDamage")

                g_WeaponInfo.Radius = keyValues.GetFloat("Radius");

                g_WeaponInfo.Damage = keyValues.GetNum("Damage");
                g_WeaponInfo.DamageType = keyValues.GetNum("DamageType");

                if (keyValues.GetNum("DoShake")){
                    g_bDoShake = true;
                    g_WeaponInfo.ShakeStrength = keyValues.GetFloat("ShakeStrength");
                    g_WeaponInfo.ShakeFrequency = keyValues.GetFloat("ShakeFrequency");
                    g_WeaponInfo.ShakeDuration =  keyValues.GetFloat("ShakeDuration");
                    g_WeaponInfo.ShakeRadius   =  keyValues.GetFloat("ShakeRadius");
                }

			}
			while (keyValues.GotoNextKey());
		}

		keyValues.Close();
	}
	else
	{
		SetFailState("Failed to open config file: \"%s\"!", path);
	}

	BuildPath(Path_SM, path, sizeof(path), "configs/customweapon_downloadlist.cfg");

	File file = OpenFile(path, "r");

	if (file != INVALID_HANDLE)
	{
		while (!file.EndOfFile() && file.ReadLine(buffer, sizeof(buffer)))
		{
			if (SplitString(buffer, "//", buffer, sizeof(buffer)) == 0)
			{
				continue;
			}

			if (TrimString(buffer))
			{
				if (FileExists(buffer))
				{
					AddFileToDownloadsTable(buffer);
				}
				else
				{
					LogError("File \"%s\" was not found!", buffer);
				}
			}
		}

		file.Close();
	}
	else
	{
		LogError("Failed to open config file: \"%s\" !", path);
	}
}



/**
 * Set up env_shake entity for screenshakes in for e.g. explosion
 * 
 * @return     true on success, false otherwise
 */
bool SetupScreenShake(){
    PrintToServer("setting up screenshake");
    int envShake = CreateEntityByName("env_shake"); 
    if (envShake==-1)   {
        LogError("---%s--- Unable to create env_shake entity");
        return false;
    }

    g_iEnt_EnvShake = EntIndexToEntRef(envShake) ;
    SetEntProp(envShake, Prop_Data, "m_iEFlags", 56);
    SetEntPropFloat(envShake, Prop_Data, "m_Amplitude", g_WeaponInfo.ShakeStrength);
    SetEntPropFloat(envShake, Prop_Data, "m_Frequency", g_WeaponInfo.ShakeFrequency);
    SetEntPropFloat(envShake, Prop_Data, "m_Duration",  g_WeaponInfo.ShakeDuration);
    SetEntPropFloat(envShake, Prop_Data, "m_Radius",    g_WeaponInfo.ShakeRadius);
    
    return DispatchSpawn(envShake);
}

public void PrintConfig(){

    PrintToServer("-%s- Custom weapon information:", PLUGIN_NAME);
    PrintToServer("%s",g_WeaponInfo.WeaponName );
    PrintToServer("%s",g_WeaponInfo.ViewModel );
    PrintToServer("%s",g_WeaponInfo.WorldModel);
    PrintToServer("%s",g_WeaponInfo.ProjectileModel);
    PrintToServer("%s",g_WeaponInfo.ParticleExplodeEffect);
    PrintToServer("%s",g_WeaponInfo.ParticleTrailEffect);
    PrintToServer("%s",g_WeaponInfo.Fire);
    PrintToServer("%s",g_WeaponInfo.FireDry);
    PrintToServer("%s",g_WeaponInfo.Reload);
    PrintToServer("%s",g_WeaponInfo.AmmoCheck);
    PrintToServer("%s",g_WeaponInfo.ExplosionSnd1);
    //PrintToServer("%s",g_WeaponInfo.ExplosionSnd2);
    PrintToServer("%s",g_WeaponInfo.Unholster);
}


public void PrecacheWeaponInfo_PrecahceStuff(){

    int i = 0;
    i += PrecacheWeaponInfo_PrecahceModel(g_WeaponInfo.ViewModel);
    i += PrecacheWeaponInfo_PrecahceModel(g_WeaponInfo.WorldModel);
    i += PrecacheWeaponInfo_PrecahceModel(g_WeaponInfo.ProjectileModel);
    if(i==0){
        LogError("---%s--- Error precaching models", PLUGIN_NAME);
    }
    PrecacheWeaponInfo_PrecahceSound(g_WeaponInfo.Fire);
    PrecacheWeaponInfo_PrecahceSound(g_WeaponInfo.FireDry);
    PrecacheWeaponInfo_PrecahceSound(g_WeaponInfo.Reload);
    PrecacheWeaponInfo_PrecahceSound(g_WeaponInfo.AmmoCheck);
    PrecacheWeaponInfo_PrecahceSound(g_WeaponInfo.ExplosionSnd1);
    PrecacheWeaponInfo_PrecahceSound(g_WeaponInfo.ExplosionSnd2);
    PrecacheWeaponInfo_PrecahceSound(g_WeaponInfo.Unholster);

    g_bPrecahceFinished = true;
    PrintToServer("-%s- Finished Precaching weapon models and sounds.", PLUGIN_NAME);
}

int PrecacheWeaponInfo_PrecahceSound(const char[] sound){
	return sound[0] != '\0' ? view_as<int>(PrecacheSound(sound, true)) : 0;
}

int PrecacheWeaponInfo_PrecahceModel(const char[] model){
	return model[0] != '\0' ? PrecacheModel(model, true) : 0;
}





//////////////////////////////////////////////////////////////////////////////////////////////////////////////
//--------------------------------         Debug Stuff              ----------------------------------------//

public Action play_a(int client, int args){
    char buffer[128];
    GetCmdArg(1, buffer, sizeof(buffer));
    int argument = StringToInt(buffer);

    switch (argument){
        case fire:      {
            EmitSoundToClient(client, g_WeaponInfo.Fire, SOUND_FROM_PLAYER, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE);}
        case firedry:   {
            EmitSoundToClient(client, g_WeaponInfo.FireDry, SOUND_FROM_PLAYER, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE);}
        case reload:    {
            EmitSoundToClient(client, g_WeaponInfo.Reload, SOUND_FROM_PLAYER, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE);}
        case ammocheck: {
            EmitSoundToClient(client, g_WeaponInfo.AmmoCheck, SOUND_FROM_PLAYER, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE);}
        case explosionsnd1: {
            EmitSoundToClient(client, g_WeaponInfo.ExplosionSnd1, SOUND_FROM_PLAYER, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE);}
        case explosionsnd2: {
            EmitSoundToClient(client, g_WeaponInfo.ExplosionSnd2, SOUND_FROM_PLAYER, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE);}
        case unholster: {
            EmitSoundToClient(client, g_WeaponInfo.Unholster, SOUND_FROM_PLAYER, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE);}
        }
}

public Action PrintWeapon(int args){
    PrintToServer("WeaponName %s", g_WeaponInfo.WeaponName)
    PrintToServer("ViewModel %s", g_WeaponInfo.ViewModel)
    PrintToServer("WorldModel %s", g_WeaponInfo.WorldModel)
    PrintToServer("ProjectileModel %s", g_WeaponInfo.ProjectileModel)
}

void InitSendPropOffset(int &offsetDest, const char[] serverClass, const char[] propName, bool failOnError = true)
{
	if ((offsetDest = FindSendPropInfo(serverClass, propName)) < 1 && failOnError)
	{
		SetFailState("Failed to find offset: \"%s\"!", propName);
	}
}


