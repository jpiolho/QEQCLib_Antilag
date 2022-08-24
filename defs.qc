// QCAntilag: global defines/constants
#define ANTILAG_STATES				0x10
#define ANTILAG_MASK				0x0F
#define	ANTILAG_MAX_RESPONSETIME	150

enumflags {
    ANTILAG_FL_SPAWNTEST,
    ANTILAG_FL_RESPONSECHECK
};


#define ANTILAG_REWIND_SCOPE(owner,func) Antilag::antilag_rewind_players(owner.antilag_responsetime, owner);\
func\
Antilag::antilag_restore_players()

// QCAntilag: entity properties
.float 	antilag_flags;
.vector	antilag_lastorigin[ANTILAG_STATES];
.float 	antilag_lastorigintime[ANTILAG_STATES];
.float 	antilag_updatetime;
.vector antilag_hold_origin;
.vector	antilag_spawn_angles;
.float 	antilag_spawn_time;
.float 	antilag_responsetime;
.float 	antilag_responsetime1;
.float 	antilag_responsetime2;
.float 	antilag_responsetime3;
.float 	antilag_spamtime;

// QCAntilag: PlayerEXFlags for FTE
.float	antilag_playerexflags;

string(entity e, string key) infokey = #0:infokey;
float(entity e, string key) infokeyf = #0:infokeyf;
float(string s1, string sub, optional float startidx) strstrofs = #0:strstrofs;

// QCAntilag: parse PlayerEXFlags in FTE
string(float) argv = #0:argv;
float(string) tokenize = #0:tokenize;
void(entity e, string s) clientcommand = #0:clientcommand;
float(string) stof = #0:stof;

// QCAntilag: globals
float is_running_fte;
float responsetimecheck;